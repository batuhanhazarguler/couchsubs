// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core.LgTv;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Android TV bekçisi Samsung'daki #1248 yolunu izler: uygulama TV'de çalışıyor ama 10 sn'de bağlanmıyorsa bir kez
/// kapatılıp (am force-stop) temiz açılır; bağlanırsa uygulamaya dokunulmaz. Mac/iPhone (AndroidTVLauncherTests) ve
/// Android (AndroidTvLauncherTest) ile aynı.
/// </summary>
public class AndroidTvLauncherTests
{
    private const string Started = "Starting: Intent { cmp=com.couchsubs.tv/.MainActivity }";
    private const string BroughtToFront = "Starting: Intent { cmp=com.couchsubs.tv/.MainActivity }\nWarning: Activity not started, its current task has been brought to the front";

    [Theory]
    [InlineData(AndroidTvOpenRule.AlreadyRunning, true)]
    [InlineData(BroughtToFront, true)]
    [InlineData("Warning: Activity not started, intent has been delivered to currently running top-most instance.", true)]
    [InlineData(Started, false)]
    [InlineData("", false)]
    public void RecognisesARunningApp(string output, bool resumed) => Assert.Equal(resumed, AndroidTvLauncher.IsResumed(output));

    [Fact]
    public async Task ClosedAppIsOpenedOnce()
    {
        List<bool> opens = [];
        var output = await new AndroidTvLauncher(restart => { opens.Add(restart); return Task.FromResult(Started); }, () => false,
            TimeSpan.FromMilliseconds(50), TimeSpan.FromMilliseconds(5)).OpenAsync();
        Assert.Equal([false], opens);
        Assert.Equal(Started, output);
    }

    [Fact]
    public async Task RunningAppThatConnectsIsLeftAlone()
    {
        List<bool> opens = [];
        var connected = false;
        var launcher = new AndroidTvLauncher(restart =>
        {
            opens.Add(restart);
            _ = Task.Delay(30).ContinueWith(_ => connected = true);
            return Task.FromResult(AndroidTvOpenRule.AlreadyRunning);
        }, () => connected, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(5));
        Assert.Equal(AndroidTvOpenRule.AlreadyRunning, await launcher.OpenAsync());
        Assert.Equal([false], opens);
    }

    [Fact]
    public async Task RunningAppThatDoesNotConnectIsForceStoppedAndStartedOnce()
    {
        List<bool> opens = [];
        List<string> lines = [];
        var launcher = new AndroidTvLauncher(restart =>
        {
            opens.Add(restart);
            return Task.FromResult(restart ? Started : AndroidTvOpenRule.AlreadyRunning);
        }, () => false, TimeSpan.FromMilliseconds(60), TimeSpan.FromMilliseconds(5), lines.Add);
        Assert.Equal(Started, await launcher.OpenAsync());
        // Önce normal açma, sonra bir kez "kapat ve aç"; yeniden "zaten açık" dense de üçüncü deneme yok (bekçi yeniden dener).
        Assert.Equal([false, true], opens);
        Assert.Contains(lines, line => line.Contains("am force-stop"));
    }

    [Fact]
    public async Task BroughtToFrontAlsoCountsAsRunning()
    {
        List<bool> opens = [];
        await new AndroidTvLauncher(restart => { opens.Add(restart); return Task.FromResult(restart ? Started : BroughtToFront); },
            () => false, TimeSpan.FromMilliseconds(30), TimeSpan.FromMilliseconds(5)).OpenAsync();
        Assert.Equal([false, true], opens);
    }

    [Fact]
    public async Task FailureIsNotRetriedHere()
    {
        List<bool> opens = [];
        await Assert.ThrowsAsync<IOException>(() => new AndroidTvLauncher(restart =>
        {
            opens.Add(restart);
            return Task.FromException<string>(new IOException("ADB kapalı"));
        }, () => false, TimeSpan.FromMilliseconds(30)).OpenAsync());
        Assert.Equal([false], opens);
    }

    /// <summary>Bekçi turu: çalışan ama bağlanmayan uygulama kapatılıp açılır ve bu bir açılış sayılır.</summary>
    [Fact]
    public async Task KeeperRestartsARunningAppThatDoesNotConnect()
    {
        List<bool> opens = [];
        List<string> lines = [];
        var launcher = new AndroidTvLauncher(restart =>
        {
            opens.Add(restart);
            return Task.FromResult(restart ? Started : AndroidTvOpenRule.AlreadyRunning);
        }, () => false, TimeSpan.FromMilliseconds(30), TimeSpan.FromMilliseconds(5));
        using var keeper = new AndroidTvKeeper(() => launcher.OpenAsync(), () => false, _ => TvOpenProblem.DebugOff, log: lines.Add);
        await keeper.TickAsync();
        Assert.Equal([false, true], opens);
        Assert.Contains(lines, line => line.Contains("açıldı: " + Started));
    }
}
