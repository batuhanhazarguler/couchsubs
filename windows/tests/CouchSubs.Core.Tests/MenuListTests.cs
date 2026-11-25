// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Duraklatma menüsünün konuşma/yardım geçmişi listesi (Sinan Bey beta.100, 3380-3383). Ortak deneme dosyası
/// core/Tests/CouchSubsCoreTests/Fixtures/menu-list.json (Mac MenuListTests.swift ve Android MenuListTest.kt aynı dosyayı okur).
/// </summary>
public class MenuListTests
{
    private static JsonElement Vectors(string name)
    {
        using var fixture = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("menu-list.json")));
        return fixture.RootElement.GetProperty(name).Clone();
    }

    private static TextBox Box(JsonElement element)
    {
        var v = element.EnumerateArray().Select(item => item.GetDouble()).ToArray();
        return new TextBox(v[0], v[1], v[2], v[3]);
    }

    private static List<TextLine> Lines(JsonElement vector, string key = "lines") =>
        [.. vector.GetProperty(key).EnumerateArray().Select(line => new TextLine(line.GetProperty("text").GetString()!, Box(line.GetProperty("box"))))];

    /// <summary>Liste satırları altyazı seçilmez: alt kutuda "Staff Member: …" gösterilmiyor, gerçek altyazı seçilmeye devam ediyor.</summary>
    [Fact]
    public void HistoryListIsNeverASubtitle()
    {
        var area = new TextBox(0.14, 0.62, 0.86, 0.97);
        foreach (var item in Vectors("lists").EnumerateArray())
        {
            var name = item.GetProperty("name").GetString()!;
            var list = item.GetProperty("list").GetBoolean();
            var read = new Reading(Lines(item));
            Assert.True(read.IsHistoryList == list, name);
            var reasons = new List<string>();
            var block = read.SubtitleBlock(area, dropped: (_, reason) => reasons.Add(reason));
            if (list)
            {
                Assert.True(block.Lines.Count == 0, name);
                Assert.True(reasons.SequenceEqual([Reading.ListReason]), name);
            }
            else
            {
                Assert.False(reasons.Contains(Reading.ListReason), name);
            }
        }
    }

    [Fact]
    public void PiecesOfOneRowAreJoined()
    {
        foreach (var item in Vectors("pieces").EnumerateArray())
        {
            var joined = RegionWatcher.JoinedPieces(Lines(item), item.GetProperty("aspect").GetDouble());
            var expected = item.GetProperty("expected").EnumerateArray().Select(text => text.GetString()!).ToList();
            Assert.True(expected.SequenceEqual(joined.Select(line => line.Text)),
                $"{item.GetProperty("name").GetString()}: {string.Join(" | ", joined.Select(line => line.Text))}");
        }
    }

    [Fact]
    public void RowCutAtTheAreaEdgeIsSkipped()
    {
        foreach (var item in Vectors("cuts").EnumerateArray())
        {
            var r = item.GetProperty("region").EnumerateArray().Select(value => value.GetDouble()).ToArray();
            var region = new CropRegion(r[1], r[3], r[0], r[2]);
            var cut = RegionWatcher.CutAtAreaEdge(new TextLine("Clerk: Need a hand", Box(item.GetProperty("box"))), region);
            Assert.True(cut == item.GetProperty("cut").GetBoolean(), item.GetProperty("name").GetString());
        }
    }

    /// <summary>Konuşan adı ve özel ad çeviriye gitmez ("JASON &amp; LUCIA MAP" → yalnız "MAP" çevrilir).</summary>
    [Fact]
    public void SpeakerAndNameHeadsStayUntranslated()
    {
        foreach (var item in Vectors("labels").EnumerateArray())
        {
            var text = item.GetProperty("text").GetString()!;
            var parts = RegionWatcher.SplitLabel(text);
            Assert.Single(parts);
            Assert.Equal(item.GetProperty("prefix").GetString(), parts[0].Prefix);
            Assert.Equal(item.GetProperty("core").GetString(), parts[0].Core);
        }
    }

    /// <summary>Liste kayınca eski kutular kalkar (gösterilen satır başka yerde ya da yerinde başka satır).</summary>
    [Fact]
    public void ScrollingListDropsOldBoxes()
    {
        foreach (var item in Vectors("scrolls").EnumerateArray())
        {
            var rendered = item.GetProperty("rendered").EnumerateArray().Select(shown =>
            {
                var box = Box(shown.GetProperty("box"));
                return new ScreenTranslation.Item(shown.GetProperty("source").GetString()!, "çeviri", box, box.Bottom - box.Top);
            }).ToList();
            var current = item.GetProperty("current").EnumerateArray()
                .Select(block => (Box(block.GetProperty("box")), block.GetProperty("text").GetString()!)).ToList();
            Assert.True(RegionWatcher.ListMoved(rendered, current) == item.GetProperty("moved").GetBoolean(),
                item.GetProperty("name").GetString());
        }
    }

    private static Frame Menu()
    {
        var frame = Frame.Blank(640, 360);
        Array.Fill(frame.Pixels, (byte)70);
        foreach (var (column, row, width) in new[] { (8, 4, 1), (16, 2, 1), (24, 4, 1), (27, 9, 1), (13, 8, 6) })
            for (var y = row * 20 + 3; y < row * 20 + 17; y++)
                for (var x = column * 20; x < (column + width) * 20; x++)
                {
                    var value = (byte)((y - row * 20) % 6 is 2 or 3 && x % 5 < 2 ? 240 : 24);
                    var p = y * frame.Stride + x * 4;
                    frame.Pixels[p] = frame.Pixels[p + 1] = frame.Pixels[p + 2] = value;
                }
        return frame;
    }

    /// <summary>
    /// Liste okunurken menü durumu bitmez: konuşan adlı satır (kaydırırken tek satır okunabilir) menüyü kapatmaz, menü
    /// süresi (MenuLifeMs) de dolmaz. Liste ekrandan kalkınca konuşma satırı yine menüyü bitirir (#1240).
    /// </summary>
    [Fact]
    public void ListKeepsTheMenuAndDialogueEndsItOnlyAfterwards()
    {
        var detector = new ScreenTextDetector();
        var frame = Menu();
        for (long time = 0; time <= 400; time += ScreenTextDetector.SampleIntervalMs) detector.Sample(frame, time, []);
        Assert.True(detector.InMenu);
        for (long time = 500; time <= 8000; time += ScreenTextDetector.SampleIntervalMs)
        {
            if (time % 500 == 0) detector.NoteList(time);
            if (time % 700 == 0) detector.NoteDialogue(time);
            detector.Sample(frame, time, []);
            Assert.True(detector.InMenu, $"{time} ms");
        }
        detector.NoteDialogue(9700);
        detector.Sample(frame, 9700, []);
        Assert.False(detector.InMenu);
    }

    /// <summary>
    /// Uçtan uca: altyazı alanında geçmiş listesi 15 sn okunur; hiçbir satır altyazı olarak gönderilmez (bekçi de
    /// göndermez), konuşan adı menüyü bitirmez (DialogueRead çağrılmaz), liste bildirilir (ListRead).
    /// </summary>
    [Fact]
    public async Task PipelineSendsNothingFromTheList()
    {
        var list = Vectors("lists").EnumerateArray().First(item => item.GetProperty("list").GetBoolean()
                                                                   && item.GetProperty("lines").GetArrayLength() >= 4);
        long clock = 1_000_000;
        var sender = new FakeSender();
        int dialogue = 0, listed = 0;
        var pipeline = new SubtitlePipeline(new LinesReader(new Reading(Lines(list))), new FakeTranslator(), sender, clock: () => clock)
        {
            DialogueRead = () => dialogue++,
            ListRead = () => listed++,
        };
        var image = Frame.Blank(64, 64);
        for (var i = 0; i < 150; i++)
        {
            await pipeline.ProcessAsync(image, new CropRegion());
            await pipeline.WaitForTranslationsAsync();
            clock += 100;
        }
        Assert.Empty(sender.Sent);
        Assert.Equal(0, dialogue);
        Assert.True(listed > 0);
    }
}
