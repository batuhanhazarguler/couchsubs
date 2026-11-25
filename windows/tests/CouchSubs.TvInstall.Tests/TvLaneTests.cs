// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.TvInstall.Samsung;

namespace CouchSubs.TvInstall.Tests;

/// <summary>
/// #1223 (Windows beta.93): bekçinin açma denemesi ile kurulum aynı Samsung TV'ye aynı anda sdb oturumu açıyor, TV
/// bağlantıyı zorla kapatıyordu; "güncelle"ye üç kez basılınca üç kurulum başlıyordu. TV başına tek kanal: işlemler sırayla,
/// ikinci kurulum isteği sürenin sonucunu bekler.
/// </summary>
public class TvLaneTests
{
    [Fact]
    public async Task SameTvRunsOneOperationAtATime()
    {
        var lane = new TvLane();
        var running = 0;
        var most = 0;
        var order = new List<string>();
        async Task<int> Work(string name)
        {
            var now = Interlocked.Increment(ref running);
            lock (order) { most = Math.Max(most, now); order.Add(name + " başladı"); }
            await Task.Delay(60);
            lock (order) order.Add(name + " bitti");
            Interlocked.Decrement(ref running);
            return 0;
        }
        await Task.WhenAll(
            lane.RunAsync("192.168.1.147", "kurulum", () => Work("a")),
            lane.RunAsync("192.168.1.147 ", "açma", () => Work("b")),
            lane.RunAsync("192.168.1.147", "açma", () => Work("c")));
        Assert.Equal(1, most);
        for (var i = 0; i < order.Count; i += 2)
            Assert.Equal(order[i].Split(' ')[0], order[i + 1].Split(' ')[0]);
    }

    [Fact]
    public async Task DifferentTvsDoNotWaitForEachOther()
    {
        var lane = new TvLane();
        var release = new TaskCompletionSource();
        var first = lane.RunAsync("192.168.1.10", "kurulum", async () => { await release.Task; return 1; });
        var second = await lane.RunAsync("192.168.1.11", "açma", () => Task.FromResult(2)).WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(2, second);
        Assert.False(first.IsCompleted);
        release.SetResult();
        Assert.Equal(1, await first);
    }

    [Fact]
    public async Task OpenWaitsWhileTheInstallIsRunning()
    {
        var lane = new TvLane();
        var lines = new List<string>();
        var release = new TaskCompletionSource();
        var installDone = false;
        var install = lane.InstallAsync("tv", async () => { await release.Task; installDone = true; return ("0.9.104", true); });
        var openedDuringInstall = (bool?)null;
        var open = lane.RunAsync("tv", "açma", () => { openedDuringInstall = !installDone; return Task.FromResult(0); }, lines.Add);
        await Task.Delay(100);
        Assert.False(open.IsCompleted);
        Assert.True(lane.IsInstalling("tv"));
        release.SetResult();
        await Task.WhenAll(install, open);
        Assert.False(openedDuringInstall);
        Assert.Contains(lines, line => line.Contains("sırasını bekliyor"));
        Assert.False(lane.IsInstalling("tv"));
    }

    [Fact]
    public async Task SecondInstallRequestDoesNotStartANewInstall()
    {
        var lane = new TvLane();
        var lines = new List<string>();
        var release = new TaskCompletionSource();
        var started = 0;
        async Task<(string, bool)> Install()
        {
            Interlocked.Increment(ref started);
            await release.Task;
            return ("0.9.104", true);
        }
        var first = lane.InstallAsync("tv", Install, lines.Add);
        var second = lane.InstallAsync("tv", Install, lines.Add);
        var third = lane.InstallAsync("tv", Install, lines.Add);
        await Task.Delay(50);
        release.SetResult();
        var results = await Task.WhenAll(first, second, third);
        Assert.Equal(1, started);
        Assert.All(results, result => Assert.Equal(("0.9.104", true), result));
        Assert.Equal(2, lines.Count(line => line.Contains("yeni kurulum başlatılmadı")));
        // Kurulum bitince yeni istek yeniden kurar.
        await lane.InstallAsync("tv", Install);
        Assert.Equal(2, started);
    }

    [Fact]
    public async Task WaitingRequestGetsTheRunningInstallsError()
    {
        var lane = new TvLane();
        var release = new TaskCompletionSource();
        var first = lane.InstallAsync<int>("tv", async () => { await release.Task; throw new IOException("koptu"); });
        var second = lane.InstallAsync<int>("tv", () => Task.FromResult(5));
        release.SetResult();
        await Assert.ThrowsAsync<IOException>(() => first);
        await Assert.ThrowsAsync<IOException>(() => second);
    }

    [Fact]
    public async Task NestedCallOnTheSameTvDoesNotWait()
    {
        var lane = new TvLane(TimeSpan.FromSeconds(30));
        var result = await lane.InstallAsync("tv", () => lane.RunAsync("tv", "açma", () => Task.FromResult(7)))
            .WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(7, result);
    }

    [Fact]
    public async Task StuckOperationDoesNotBlockTheTvForever()
    {
        var lane = new TvLane(TimeSpan.FromMilliseconds(100));
        var lines = new List<string>();
        var never = new TaskCompletionSource();
        _ = lane.RunAsync("tv", "kurulum", async () => { await never.Task; return 0; });
        var value = await lane.RunAsync("tv", "açma", () => Task.FromResult(3), lines.Add).WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(3, value);
        Assert.Contains(lines, line => line.Contains("beklemeden başlıyor"));
        never.SetResult();
    }

    /// <summary>Samsung bekçisinin sdb açması, aynı TV'de kurulum sürerken TV'ye bağlanmaz; kurulum bitince sırası gelir.</summary>
    [Fact]
    public async Task SamsungOpenWaitsForTheInstallOnTheSameTv()
    {
        var lane = new TvLane();
        var release = new TaskCompletionSource();
        var install = lane.InstallAsync("127.0.0.1", async () => { await release.Task; return ("0.9.104", true); });
        var installer = new SamsungTvInstaller("127.0.0.1", Directory.CreateTempSubdirectory().FullName,
            new SamsungCertificates(new HttpClient())) { Lane = lane };
        var open = installer.OpenAsync();
        await Task.Delay(150);
        Assert.False(open.IsCompleted);
        release.SetResult();
        await install;
        // Sahte TV'de sdb yok: açma bağlanamaz ve Failed döner; önemli olan kurulum bitmeden denenmemesi.
        Assert.Equal(SamsungAppLaunch.Failed, await open.WaitAsync(TimeSpan.FromSeconds(30)));
    }

    /// <summary>Samsung kurulumu sürerken ikinci "güncelle" yeni sdb kurulumu başlatmaz, sürenin sonucunu alır.</summary>
    [Fact]
    public async Task SamsungSecondUpdateJoinsTheRunningInstall()
    {
        var lane = new TvLane();
        var release = new TaskCompletionSource();
        var first = lane.InstallAsync("127.0.0.1", async () => { await release.Task; return ("0.9.104", true); });
        var log = Path.Combine(Directory.CreateTempSubdirectory().FullName, "tvinstall.log");
        var installer = new SamsungTvInstaller("127.0.0.1", Directory.CreateTempSubdirectory().FullName,
            new SamsungCertificates(new HttpClient())) { Lane = lane, Log = new InstallLog(log) };
        var second = installer.EnsureInstalledAsync("yok.wgt", "0.9.104");
        release.SetResult();
        Assert.Equal(("0.9.104", true), await second.WaitAsync(TimeSpan.FromSeconds(5)));
        await first;
        var text = await File.ReadAllTextAsync(log);
        Assert.Contains("yeni kurulum başlatılmadı", text);
        Assert.DoesNotContain("Samsung kurulumu başlıyor", text);
    }
}
