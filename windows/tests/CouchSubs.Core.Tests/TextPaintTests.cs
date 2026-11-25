// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Yerinde birebir çizim: göndericinin kareden ölçtükleri (<see cref="TextPainter"/>: örtü kutusu, zemin/degrade/desen,
/// boş alan, grup) ve çizicilerin ortak yerleşimi (<see cref="ScreenFit.Exact"/>). Ortak deneme dosyası
/// core/Tests/CouchSubsCoreTests/Fixtures/text-paint.json (Mac TextPaintTests.swift, Android TextPaintTest.kt ve TV
/// scripts/tv-exact-fit.test.js aynı vakalar).
/// </summary>
public class TextPaintTests
{
    private static JsonDocument Fixture() => JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("text-paint.json")));

    private static double[] Numbers(JsonElement array) => [.. array.EnumerateArray().Select(value => value.GetDouble())];

    /// <summary>Yapay karenin noktası: zemin, üstüne sırayla çizilen dikdörtgenler.</summary>
    private static (int R, int G, int B) Pixel(JsonElement frame, int x, int y)
    {
        foreach (var rect in frame.GetProperty("rects").EnumerateArray().Reverse())
        {
            var box = Numbers(rect.GetProperty("box"));
            if (x >= box[0] && x < box[2] && y >= box[1] && y < box[3]) return TextPainter.Rgb(rect.GetProperty("color").GetString()!);
        }
        var background = frame.GetProperty("background");
        var from = TextPainter.Rgb(background.GetProperty("from").GetString()!);
        var to = background.TryGetProperty("to", out var end) && end.ValueKind == JsonValueKind.String ? TextPainter.Rgb(end.GetString()!) : from;
        int width = frame.GetProperty("width").GetInt32(), height = frame.GetProperty("height").GetInt32();
        static int Mix(int a, int b, double f) => (int)Math.Round(a + ((b - a) * f), MidpointRounding.AwayFromZero);
        (int, int, int) At(double f) => (Mix(from.R, to.R, f), Mix(from.G, to.G, f), Mix(from.B, to.B, f));
        switch (background.GetProperty("kind").GetString())
        {
            case "h": return At((double)x / (width - 1));
            case "v": return At((double)y / (height - 1));
            case "checker":
                var cell = background.TryGetProperty("cell", out var size) && size.ValueKind == JsonValueKind.Number ? size.GetInt32() : 6;
                return ((x / cell) + (y / cell)) % 2 == 0 ? from : to;
            default: return from;
        }
    }

    /// <summary>Renkler kanal başına en çok 4 farklı.</summary>
    private static bool Near(string a, string b) => TextPainter.Distance(TextPainter.Rgb(a), TextPainter.Rgb(b)) <= 4;

    private static void Close(double expected, double actual, double tolerance, string name) =>
        Assert.True(Math.Abs(expected - actual) <= tolerance, $"{name}: {actual} ≠ {expected} (±{tolerance})");

    [Fact]
    public void SharedPaintVectors()
    {
        using var fixture = Fixture();
        var frames = fixture.RootElement.GetProperty("paint").EnumerateArray().ToList();
        Assert.NotEmpty(frames);
        foreach (var frame in frames)
        {
            var id = frame.GetProperty("id").GetString()!;
            int width = frame.GetProperty("width").GetInt32(), height = frame.GetProperty("height").GetInt32();
            double w = width, h = height;
            var targets = frame.GetProperty("targets").EnumerateArray().Select(t =>
            {
                var box = Numbers(t.GetProperty("box"));
                return new TextPainter.Target(new TextBox(box[0] / w, box[1] / h, box[2] / w, box[3] / h),
                    t.GetProperty("line").GetDouble() / h, t.GetProperty("rows").GetInt32(), t.GetProperty("bg").GetString()!,
                    t.GetProperty("fg").GetString()!, t.GetProperty("upper").GetBoolean(), t.GetProperty("align").GetString()!,
                    t.TryGetProperty("words", out var words) ? words.GetInt32() : 0);
            }).ToList();
            var paints = TextPainter.Paints(targets, width, height, (x, y) => Pixel(frame, x, y));
            var expects = frame.GetProperty("expect").EnumerateArray().ToList();
            Assert.True(paints.Count == expects.Count, id);
            for (var k = 0; k < expects.Count; k++)
            {
                var expect = expects[k];
                var paint = paints[k];
                var name = $"{id}#{k}";
                if (expect.TryGetProperty("cover", out var cover) && cover.ValueKind == JsonValueKind.Array)
                {
                    double[] got = [paint.Cover.Left * w, paint.Cover.Top * h, paint.Cover.Right * w, paint.Cover.Bottom * h];
                    var want = Numbers(cover);
                    for (var i = 0; i < 4; i++) Close(want[i], got[i], 1.01, $"{name} örtü [{string.Join(", ", got)}]");
                }
                if (expect.TryGetProperty("bg", out var bg) && bg.ValueKind == JsonValueKind.String)
                    Assert.True(Near(paint.Background, bg.GetString()!), $"{name} zemin {paint.Background} ≠ {bg.GetString()}");
                if (expect.TryGetProperty("bg2", out var bg2))
                {
                    if (bg2.ValueKind == JsonValueKind.Null) Assert.True(paint.Background2 is null, $"{name} bg2 {paint.Background2}");
                    else Assert.True(paint.Background2 is { } second && Near(second, bg2.GetString()!), $"{name} bg2 {paint.Background2}");
                }
                if (expect.TryGetProperty("bgDir", out var direction) && direction.ValueKind == JsonValueKind.String)
                    Assert.True(paint.Direction == direction.GetString(), $"{name} yön {paint.Direction}");
                if (expect.TryGetProperty("patterned", out var patterned) && patterned.ValueKind is JsonValueKind.True or JsonValueKind.False)
                    Assert.True(paint.Patterned == patterned.GetBoolean(), $"{name} desen {paint.Patterned}");
                if (expect.TryGetProperty("grow", out var grow))
                {
                    if (grow.ValueKind == JsonValueKind.Null) Assert.True(paint.Grow is null, $"{name} uzamamalı: {paint.Grow}");
                    else
                    {
                        Assert.True(paint.Grow is not null, $"{name} uzamalı");
                        var want = Numbers(grow);
                        Close(want[0], paint.Grow!.Value.Left * w, 1.01, $"{name} uzama solu");
                        Close(want[1], paint.Grow!.Value.Right * w, 1.01, $"{name} uzama sağı");
                    }
                }
                if (expect.TryGetProperty("group", out var group))
                {
                    int? want = group.ValueKind == JsonValueKind.Null ? null : group.GetInt32();
                    Assert.True(paint.Group == want, $"{name} grup {paint.Group} ≠ {want}");
                }
                if (expect.TryGetProperty("pitch", out var pitch) && pitch.ValueKind == JsonValueKind.Number)
                    Close(pitch.GetDouble(), paint.Pitch * h, 0.5, $"{name} satır aralığı");
                if (expect.TryGetProperty("side", out var side))
                {
                    var want = side.ValueKind == JsonValueKind.Null ? null : side.GetString();
                    Assert.True(paint.IconSide == want, $"{name} simge yanı {paint.IconSide} ≠ {want}");
                }
            }
        }
    }

    private static List<ScreenFit.ExactInput> ExactInputs(JsonElement vector) =>
        [.. vector.GetProperty("items").EnumerateArray().Select(item =>
        {
            var box = Numbers(item.GetProperty("box"));
            var grow = item.TryGetProperty("grow", out var g) && g.ValueKind == JsonValueKind.Array ? Numbers(g) : null;
            double? pitch = item.TryGetProperty("pitch", out var p) && p.ValueKind == JsonValueKind.Number ? p.GetDouble() : null;
            var rows = item.TryGetProperty("rows", out var r) && r.ValueKind == JsonValueKind.Number ? r.GetInt32() : 1;
            int? group = item.TryGetProperty("group", out var gr) && gr.ValueKind == JsonValueKind.Number ? gr.GetInt32() : null;
            return new ScreenFit.ExactInput(item.GetProperty("text").GetString()!, box[0], box[1], box[2], box[3], grow?[0], grow?[1],
                item.GetProperty("line").GetDouble(), pitch, rows, item.GetProperty("align").GetString()!, group);
        })];

    private static IReadOnlyList<ScreenFit.ExactPlacement> Place(JsonElement vector, List<ScreenFit.ExactInput> inputs)
    {
        var charWidth = vector.GetProperty("charWidth").GetDouble();
        return ScreenFit.Exact(inputs, (text, size) => new System.Globalization.StringInfo(text).LengthInTextElements * charWidth * size);
    }

    [Fact]
    public void SharedExactVectors()
    {
        using var fixture = Fixture();
        var vectors = fixture.RootElement.GetProperty("exact").EnumerateArray().ToList();
        Assert.NotEmpty(vectors);
        foreach (var vector in vectors)
        {
            var id = vector.GetProperty("id").GetString()!;
            var placed = Place(vector, ExactInputs(vector));
            if (!vector.TryGetProperty("expect", out var expect) || expect.ValueKind != JsonValueKind.Array) continue;
            var expected = expect.EnumerateArray().ToList();
            Assert.True(placed.Count == expected.Count, id);
            for (var i = 0; i < expected.Count; i++)
            {
                var p = placed[i];
                var e = expected[i];
                var lines = e.GetProperty("lines").EnumerateArray().Select(line => line.GetString()!).ToList();
                var name = $"{id} [{string.Join(" | ", lines)}]";
                Assert.True(lines.SequenceEqual(p.Lines), $"{name}: satırlar [{string.Join(" | ", p.Lines)}]");
                Close(e.GetProperty("left").GetDouble(), p.Left, 0.05, $"{name} sol");
                Close(e.GetProperty("top").GetDouble(), p.Top, 0.05, $"{name} üst");
                Close(e.GetProperty("width").GetDouble(), p.Width, 0.05, $"{name} genişlik");
                Close(e.GetProperty("height").GetDouble(), p.Height, 0.05, $"{name} yükseklik");
                Close(e.GetProperty("fontSize").GetDouble(), p.FontSize, 0.05, $"{name} yazı boyu");
                Close(e.GetProperty("lineHeight").GetDouble(), p.LineHeight, 0.05, $"{name} satır aralığı");
                Close(e.GetProperty("rowHeight").GetDouble(), p.RowHeight, 0.05, $"{name} satır yüksekliği");
            }
        }
    }

    private static JsonElement Vector(JsonDocument fixture, string id) =>
        fixture.RootElement.GetProperty("exact").EnumerateArray().First(vector => vector.GetProperty("id").GetString() == id);

    /// <summary>
    /// Kurallar ortak dosyadan bağımsız da: grup içinde yazı boyu eşit, uzun çeviri boş alana uzar, kutu simgeye/ekran
    /// kenarına taşmaz, yazı kesilmez.
    /// </summary>
    [Fact]
    public void GrubunYaziBoyuTekVeUzunCeviriBosAlanaUzar()
    {
        using var fixture = Fixture();
        var vector = Vector(fixture, "grup-esit-boy-bos-alana-uzar");
        var inputs = ExactInputs(vector);
        var placed = Place(vector, inputs);
        Assert.Single(placed.Select(p => Math.Round(p.FontSize * 100)).Distinct());
        for (var i = 0; i < inputs.Count; i++)
        {
            var (input, p) = (inputs[i], placed[i]);
            Assert.Equal(input.Text, string.Join(' ', p.Lines));
            Assert.Equal(input.Right, p.Left + p.Width, 2);
            Assert.True(p.Left >= input.GrowLeft - 0.01, "boş alanın dışına taşmaz");
            Assert.Single(p.Lines);
        }
        // "HEDEF BELİRLE" kendi kutusundan uzun: boş sol tarafa uzar, yazı boyu küçülmez.
        Assert.True(placed[3].Left < inputs[3].Left);
        Assert.Equal(ScreenFit.ExactFont * 20, placed[3].FontSize, 2);
    }

    [Fact]
    public void BosAlanYoksaGrupBirlikteKuculur()
    {
        using var fixture = Fixture();
        var vector = Vector(fixture, "bos-alan-yok-grup-birlikte-kuculur");
        var inputs = ExactInputs(vector);
        var placed = Place(vector, inputs);
        Assert.Single(placed.Select(p => Math.Round(p.FontSize * 100)).Distinct());
        Assert.True(placed[0].FontSize < ScreenFit.ExactFont * 20);
        for (var i = 0; i < inputs.Count; i++)
        {
            var (input, p) = (inputs[i], placed[i]);
            Assert.True(p.Left >= input.GrowLeft - 0.01);
            Assert.True(p.Left + p.Width <= input.GrowRight + 0.01);
            Assert.Equal(input.Text, string.Join(' ', p.Lines));
        }
    }

    /// <summary>Ölçü alanın karesinde alınır, karedeki yere taşınır: örtü, boş alan ve satır aralığı alanla ölçeklenir.</summary>
    [Fact]
    public void OlculerAlandanKareyeTasinir()
    {
        var paint = new TextPaint("#000000", 0.1, new TextBox(0.2, 0.2, 0.4, 0.3)) { Grow = new TextBox(0.1, 0.2, 0.4, 0.3) };
        var placed = paint.PlacedIn(new TextBox(0.5, 0.5, 1, 1));
        Assert.Equal(0.6, placed.Cover.Left, 6);
        Assert.Equal(0.6, placed.Cover.Top, 6);
        Assert.Equal(0.7, placed.Cover.Right, 6);
        Assert.Equal(0.65, placed.Cover.Bottom, 6);
        Assert.Equal(0.55, placed.Grow!.Value.Left, 6);
        Assert.Equal(0.05, placed.Pitch, 6);
    }

    /// <summary>
    /// #1268, #1270: harfi/rakamı olmayan parça (yön tuşu simgesinin "-" okunuşu, renkli nokta "•") sözcük sayılmaz; simge
    /// kutunun ucunda bulunur, kutu simgenin üstüne çizilmez (Mac ile aynı).
    /// </summary>
    [Fact]
    public void HarfsizParcaSozcukSayilmaz()
    {
        Assert.Equal(3, TextPainter.WordCount("- SMASH 'N' GRABS"));
        Assert.Equal(1, TextPainter.WordCount("• Objective"));
        Assert.Equal(1, TextPainter.WordCount("+ CLUBS"));
        Assert.Equal(3, TextPainter.WordCount("Buck's Jewelry & Pawn"));
        Assert.Equal(1, TextPainter.WordCount("I Map"));
        Assert.Equal(2, TextPainter.WordCount("2D VIEW"));
        Assert.Equal(2, TextPainter.WordCount("$1,000 - $10,000"));
        (int L, int R)[] spans = [(0, 20), (28, 90), (98, 112), (120, 180)];
        var found = TextPainter.IconSpans(0, 180, 20.0, TextPainter.WordCount("- SMASH 'N' GRABS"), "left",
            x => spans.Any(s => x >= s.L && x < s.R));
        Assert.NotNull(found.Left);
        Assert.Equal(28, found.TextLeft);
    }

    /// <summary>
    /// #1255: kare dışına taşan kutu (sol, sağ, üst, alt) boş alan taramasını sonsuz döngüye sokmaz; ölçüm biter ve kutular
    /// kareye kırpılır. Nokta okuması kenara sabitlenir; sayaç bütçeyi aşarsa (eski kodda sonsuz döngü) farklı renk döner ki
    /// deneme takılmasın, sonra bütçe aşımı hata sayılır.
    /// </summary>
    [Theory]
    [InlineData(-0.08, 0.4, 0.3, 0.6)]
    [InlineData(0.7, 0.4, 1.08, 0.6)]
    [InlineData(0.3, -0.1, 0.6, 0.15)]
    [InlineData(0.3, 0.85, 0.6, 1.1)]
    [InlineData(-0.2, -0.2, 1.2, 1.2)]
    public void PaintsEndsWhenBoxOverflowsFrame(double left, double top, double right, double bottom)
    {
        const int width = 200, height = 100, budget = 2_000_000;
        var box = new TextBox(left, top, right, bottom);
        var calls = 0;
        var target = new TextPainter.Target(box, 0.1, 1, "#202020", "#F0F0F0", false, "center");
        var paints = TextPainter.Paints([target], width, height, (x, y) =>
        {
            calls++;
            if (calls > budget) return (255, 0, 0);
            int cx = Math.Min(width - 1, Math.Max(0, x)), cy = Math.Min(height - 1, Math.Max(0, y));
            double fx = (double)cx / width, fy = (double)cy / height;
            var ink = fx > Math.Max(0, left) + 0.02 && fx < Math.Min(1, right) - 0.02 && cy % 4 == 0 && fy > Math.Max(0, top)
                      && fy < Math.Min(1, bottom);
            return ink ? (240, 240, 240) : (32, 32, 32);
        });
        Assert.True(calls <= budget, $"sonsuz döngü: {box}");
        var paint = Assert.Single(paints);
        foreach (var b in paint.Grow is { } grow ? new[] { paint.Cover, grow } : new[] { paint.Cover })
        {
            Assert.True(b.Left >= 0 && b.Top >= 0 && b.Right <= 1 && b.Bottom <= 1, $"{box}: {b}");
            Assert.True(b.Left <= b.Right && b.Top <= b.Bottom, $"{box}: {b}");
        }
    }
}
