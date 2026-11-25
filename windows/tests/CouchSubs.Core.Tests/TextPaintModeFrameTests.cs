// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Çizim kipinin gerçek karelerde seçimi (<see cref="TextPaint.Mode"/>): yazı tanıma yok, yazıların yeri sabit (karede,
/// kenarlara oranla); stil <see cref="TextStyleSampler"/>'dan, ölçüm <see cref="TextPainter"/>'dan. Ortak vakalar
/// core/Tests/CouchSubsCoreTests/Fixtures/text-paint-modes.json (Mac TextPaintModeFrameTests.swift, Android
/// TextPaintModeFrameTest.kt aynı kareler ve beklentiler); kareler testdata/frames altında (<see cref="Jpeg"/> ile açılır).
/// </summary>
public class TextPaintModeFrameTests
{
    private static string FramePath(string name, [System.Runtime.CompilerServices.CallerFilePath] string source = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(source)!, "..", "..", "..", "testdata", "frames", name));

    private static double[] Numbers(JsonElement array) => [.. array.EnumerateArray().Select(value => value.GetDouble())];

    /// <summary><paramref name="a"/> kutusu <paramref name="b"/>'nin hangi yanında (left/right/below/above); kesişiyorsa null.</summary>
    private static string? Side(TextBox a, TextBox b)
    {
        if (a.Right <= b.Left + 1e-9) return "left";
        if (a.Left >= b.Right - 1e-9) return "right";
        if (a.Top >= b.Bottom - 1e-9) return "below";
        if (a.Bottom <= b.Top + 1e-9) return "above";
        return null;
    }

    [Fact]
    public void RealFrameModes()
    {
        using var vectors = JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("text-paint-modes.json")));
        var images = new Dictionary<string, Frame>();
        foreach (var vector in vectors.RootElement.GetProperty("frames").EnumerateArray())
        {
            var id = vector.GetProperty("id").GetString()!;
            var file = vector.GetProperty("file").GetString()!;
            if (!images.TryGetValue(file, out var image)) images[file] = image = Jpeg.Load(FramePath(file));
            var sources = vector.GetProperty("targets").EnumerateArray().ToList();
            var boxes = sources.Select(t => Numbers(t.GetProperty("box"))).Select(b => new TextBox(b[0], b[1], b[2], b[3])).ToList();
            var targets = sources.Select((t, i) =>
            {
                var text = t.GetProperty("text").GetString()!;
                var box = boxes[i];
                var rows = t.TryGetProperty("rows", out var r) ? r.GetInt32() : 1;
                var (style, look) = TextStyleSampler.Sample(image, box, [new TextLine(text, box)], text);
                ScreenTextKind? kind = t.TryGetProperty("kind", out var k) ? Enum.Parse<ScreenTextKind>(k.GetString()!, ignoreCase: true) : null;
                return new TextPainter.Target(box, (box.Bottom - box.Top) / rows, rows, style.Background, style.Foreground, look.Upper,
                                              look.Align, TextPainter.WordCount(text), kind,
                                              t.TryGetProperty("prompt", out var p) && p.GetBoolean());
            }).ToList();
            var paints = TextPainter.Paints(targets, image);
            var expects = vector.GetProperty("expect").EnumerateArray().ToList();
            Assert.Equal(expects.Count, paints.Count);
            for (var k = 0; k < expects.Count; k++)
            {
                var expect = expects[k];
                var paint = paints[k];
                var name = $"{id}#{k}";
                Assert.True(paint.Mode == expect.GetProperty("mode").GetString(), $"{name}: {paint.Mode}");
                if (expect.TryGetProperty("portrait", out var face))
                    Assert.True((paint.Portrait is not null) == face.GetBoolean(), $"{name} resim");
                // İkiz (Sinan Bey, beta.100): özgün kutu örtülmez; ikiz aynı boyda (küçültme yok), yanında, altında ya da üstünde.
                if (paint.Mode == PaintMode.Twin && paint.Twin is { } twin && paint.Spot is { } spot)
                {
                    Assert.True(Math.Abs(paint.Scale - 1) <= 1e-9, name);
                    Assert.True(Math.Abs(spot.Bottom - spot.Top - (paint.Cover.Bottom - paint.Cover.Top)) <= 1e-6, name);
                    Assert.True(Side(twin, paint.Cover) is not null, $"{name} ikiz özgünü örtüyor");
                    if (expect.TryGetProperty("twinSide", out var want))
                        Assert.True(Side(twin, boxes[k]) == want.GetString(), $"{name} ikiz yanı {Side(twin, boxes[k])}");
                }
                // Yanına yazma: arka plansız, özgünün yanında; Türkçe özgün yazıya binmez.
                if (paint.Mode == PaintMode.Beside && paint.Spot is { } beside && paint.SpotRoom is { } room)
                {
                    if (expect.TryGetProperty("side", out var want))
                        Assert.True(Side(beside, paint.Cover) == want.GetString(), $"{name} yan {Side(beside, paint.Cover)}");
                    Assert.True(Side(room, paint.Cover) is not null, $"{name} özgüne biner");
                }
            }
            // Liste birlikte: sütunda Türkçelerin ortak kenarı (solda sağ kenar, sağda sol kenar), satırda ortak üst çizgi.
            if (!vector.TryGetProperty("same", out var same)) continue;
            foreach (var list in same.EnumerateArray().Select(l => l.EnumerateArray().Select(v => v.GetInt32()).ToList()))
            {
                var spots = list.Select(i => paints[i].Spot).OfType<TextBox>().ToList();
                Assert.True(spots.Count == list.Count, $"{id} liste");
                if (Side(spots[0], paints[list[0]].Cover) is not { } side) continue;
                foreach (var spot in spots)
                {
                    var (got, want) = side switch
                    {
                        "left" => (spot.Right, spots[0].Right),
                        "right" => (spot.Left, spots[0].Left),
                        _ => (spot.Top, spots[0].Top),
                    };
                    Assert.True(Math.Abs(got - want) <= 1e-6, $"{id} {(side is "left" or "right" ? "sütun" : "satır")}");
                }
            }
        }
    }
}
