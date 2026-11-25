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
                var (style, look) = TextStyleSampler.Sample(image, box, [new TextLine(text, box)], text);
                ScreenTextKind? kind = t.TryGetProperty("kind", out var k) ? Enum.Parse<ScreenTextKind>(k.GetString()!, ignoreCase: true) : null;
                return new TextPainter.Target(box, box.Bottom - box.Top, 1, style.Background, style.Foreground, look.Upper, look.Align,
                                              TextPainter.WordCount(text), kind, t.TryGetProperty("prompt", out var p) && p.GetBoolean());
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
                if (expect.TryGetProperty("twinAbove", out var above) && paint.Twin is { } twin)
                    Assert.True((twin.Bottom <= boxes[k].Top) == above.GetBoolean(), $"{name} ikiz üstte");
                // İkiz (Sinan Bey, #1296): özgünden belirgin küçük, sol kenarı özgün panelle hizalı, özgün paneli örtmez.
                if (paint.Mode == PaintMode.Twin && paint.Twin is { } box && paint.Spot is { } spot)
                {
                    Assert.True(paint.Scale >= TextPainter.TwinScale - 0.001 && paint.Scale <= 1, name);
                    Assert.True(paint.Scale >= 1 || ScreenFit.ExactFont * (boxes[k].Bottom - boxes[k].Top) * paint.Scale >= TextPainter.TwinMinShare - 0.002, name);
                    Assert.True(Math.Abs(((spot.Bottom - spot.Top) / (paint.Cover.Bottom - paint.Cover.Top)) - paint.Scale) <= 0.05, name);
                    Assert.True(box.Left < paint.Cover.Left, name);
                    Assert.True(box.Bottom <= paint.Cover.Top || box.Top >= paint.Cover.Bottom, name);
                    Assert.True(paint.Radius > 0, name);
                }
                // Yanına yazma (Sinan Bey: "SELAMLA  GREET"): aynı satırda, aynı yükseklikte, özgünün solunda.
                if (paint.Mode == PaintMode.Beside && paint.Spot is { } side && paint.SpotRoom is { } room)
                {
                    Assert.Equal(paint.Cover.Top, side.Top, 9);
                    Assert.Equal(paint.Cover.Bottom, side.Bottom, 9);
                    Assert.True(side.Right <= paint.Cover.Left, name);
                    Assert.False(Math.Min(room.Right, paint.Cover.Right) > Math.Max(room.Left, paint.Cover.Left)
                                 && Math.Min(room.Bottom, paint.Cover.Bottom) > Math.Max(room.Top, paint.Cover.Top), name);
                }
            }
        }
    }
}
