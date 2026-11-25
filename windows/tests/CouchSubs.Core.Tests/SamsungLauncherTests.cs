// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core.LgTv;

namespace CouchSubs.Core.Tests;

/// <summary>
/// #1248: <c>was_execute</c> "resumed" dediğinde (uygulama çalışıyor ama akışa bağlı değil) bekçi 8002 uzaktan kumanda
/// yoluna düşmez (TV "AS400" diyordu); uygulamaya kendisi bağlanması için süre tanır, bağlanmazsa sdb ile kapatıp açar.
/// Mac/iPhone (SSAPClientTests) ve Android (SamsungSdbOpenTest) ile aynı.
/// </summary>
public class SamsungLauncherTests
{
    private sealed class Remote : ITvControl
    {
        public int Launches { get; private set; }
        public Task LaunchAsync(string appId, IReadOnlyDictionary<string, string> parameters, CancellationToken cancellationToken = default)
        {
            Launches++;
            return Task.CompletedTask;
        }
        public Task<string> ForegroundAppIdAsync(CancellationToken cancellationToken = default) => Task.FromResult("");
        public void Dispose() { }
    }

    private static readonly Dictionary<string, string> NoParams = [];

    [Fact]
    public async Task LaunchedAndFailedKeepTheirOldPaths()
    {
        var remote = new Remote();
        var connects = 0;
        await new SamsungLauncher(_ => Task.FromResult(SamsungSdbOpen.Launched), () => false,
            () => { connects++; return Task.FromResult<ITvControl>(remote); }, log: _ => { }).LaunchAsync("x", NoParams);
        Assert.Equal(0, connects);
        await new SamsungLauncher(_ => Task.FromResult(SamsungSdbOpen.Failed), () => false,
            () => { connects++; return Task.FromResult<ITvControl>(remote); }, log: _ => { }).LaunchAsync("x", NoParams);
        Assert.Equal(1, connects);
        Assert.Equal(1, remote.Launches);
    }

    [Fact]
    public async Task ResumedAppThatReconnectsIsLeftAlone()
    {
        var connected = false;
        List<bool> opens = [];
        var connects = 0;
        var launcher = new SamsungLauncher(restart =>
        {
            opens.Add(restart);
            connected = true;
            return Task.FromResult(SamsungSdbOpen.Resumed);
        }, () => connected, () => { connects++; return Task.FromResult<ITvControl>(new Remote()); },
            resumeWait: TimeSpan.FromSeconds(2), poll: TimeSpan.FromMilliseconds(10), log: _ => { });
        await launcher.LaunchAsync("x", NoParams);
        Assert.Equal([false], opens);
        Assert.Equal(0, connects);
    }

    [Fact]
    public async Task ResumedAppThatStaysAwayIsRestartedNotSentTo8002()
    {
        List<bool> opens = [];
        List<string> lines = [];
        var connects = 0;
        var launcher = new SamsungLauncher(restart =>
        {
            opens.Add(restart);
            return Task.FromResult(restart ? SamsungSdbOpen.Launched : SamsungSdbOpen.Resumed);
        }, () => false, () => { connects++; return Task.FromResult<ITvControl>(new Remote()); },
            resumeWait: TimeSpan.FromMilliseconds(50), poll: TimeSpan.FromMilliseconds(10), log: lines.Add);
        await launcher.LaunchAsync("x", NoParams);
        Assert.Equal([false, true], opens);
        Assert.Equal(0, connects);
        Assert.Contains(lines, line => line.Contains("kapatılıp yeniden açılıyor"));

        // Kapatıp açma da tutmadı: yine 8002'ye geçilmez, bekçi sonra yeniden dener.
        var stuck = new SamsungLauncher(_ => Task.FromResult(SamsungSdbOpen.Resumed), () => false,
            () => { connects++; return Task.FromResult<ITvControl>(new Remote()); },
            resumeWait: TimeSpan.FromMilliseconds(20), poll: TimeSpan.FromMilliseconds(5), log: _ => { });
        await stuck.LaunchAsync("x", NoParams);
        Assert.Equal(0, connects);
    }
}
