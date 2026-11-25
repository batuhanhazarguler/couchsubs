// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>
/// #1271: gösterilen ek alanlar TV'de yalnız okuma turu dönerken yenilenir; uygulama donunca TV son çeviriyi kendisi
/// kaldırır (Mac RegionAliveTests, Android RegionAliveTest ile aynı).
/// </summary>
public class RegionAliveTests
{
    private sealed class Reader : ITextReader
    {
        public string Read(Frame image) => "";
        public Reading ReadScreen(Frame image) => new(new List<TextLine>());
        public Reading ReadLines(Frame image, bool deep) => new(new List<TextLine>());
    }

    private sealed class Translator : ITextTranslator
    {
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default) => Task.FromResult(text);
        public Task<IReadOnlyList<string>> TranslateAllAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
            Task.FromResult(texts);
    }

    private sealed class Server : IRegionSender
    {
        public int Alive;
        public void SendRegion(string id, string text, TextBox? box, double? lineHeight = null) { }
        public void ClearRegions() { }
        public void RegionsAlive() => Interlocked.Increment(ref Alive);
    }

    [Fact]
    public async Task HerTurVeHerAlanTuruCanliBildirir()
    {
        var server = new Server();
        var watcher = new RegionWatcher(new Reader(), new Translator(), server);
        var areas = new[] { "a", "b" }.Select(id => new WatchedArea(id, id, new CropRegion(0, 0.5, 0, 0.5))).ToList();
        await watcher.PassAsync(Frame.Blank(64, 36), areas);
        // Tur başı, iki alan ve tur sonu.
        Assert.Equal(4, server.Alive);
        await watcher.PassAsync(Frame.Blank(64, 36), []);
        Assert.Equal(6, server.Alive);
    }

    [Fact]
    public void AlanlarYalnizTurDonerkenYenilenir()
    {
        Assert.True(SubtitleServer.KeepsRegions(-1, 1_000_000));
        Assert.True(SubtitleServer.KeepsRegions(100_000, 100_000 + SubtitleServer.RegionAliveMs));
        Assert.False(SubtitleServer.KeepsRegions(100_000, 100_001 + SubtitleServer.RegionAliveMs));
        Assert.True(SubtitleServer.RegionAliveMs > 8000 + 4 * RegionWatcher.DefaultIntervalMs + 4000);
    }
}
