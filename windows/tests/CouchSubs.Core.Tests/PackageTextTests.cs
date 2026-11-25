// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Ürün/ambalaj/etiket yazısı (bira kutusu, süt kartonu) ekran yazısı ve altyazı sayılmaz; menü, istem, görev, bildirim ve
/// telefon yazısı kalır (Sinan Bey beta.101). Ortak deneme dosyası core/Tests/CouchSubsCoreTests/Fixtures/package-text.json
/// (Mac PackageTextTests.swift ve Android PackageTextTest.kt aynı dosyayı okur).
/// </summary>
public class PackageTextTests
{
    private static TextBox Box(JsonElement e) => new(e[0].GetDouble(), e[1].GetDouble(), e[2].GetDouble(), e[3].GetDouble());

    private static JsonElement Root() =>
        JsonDocument.Parse(File.ReadAllText(PackFixtures.Path("package-text.json"))).RootElement;

    private static PackageText.Look? Look(JsonElement e) =>
        e.ValueKind == JsonValueKind.Null ? null
            : new PackageText.Look(e.GetProperty("textured").GetBoolean(), e.GetProperty("uiInk").GetBoolean());

    [Fact]
    public void BrandShape()
    {
        foreach (var shape in Root().GetProperty("shapes").EnumerateArray())
        {
            var text = shape.GetProperty("text").GetString()!;
            Assert.True(PackageText.IsBrandShape(text) == shape.GetProperty("brand").GetBoolean(), text);
        }
    }

    [Fact]
    public void ProductNamesAreKept()
    {
        foreach (var product in Root().GetProperty("products").EnumerateArray())
        {
            var text = product.GetProperty("text").GetString()!;
            Assert.True(ScreenTranslation.KeepsNames(text) == product.GetProperty("keep").GetBoolean(), text);
        }
    }

    [Fact]
    public void SharedCases()
    {
        foreach (var vector in Root().GetProperty("cases").EnumerateArray())
        {
            var name = vector.GetProperty("name").GetString();
            var lines = vector.GetProperty("lines").EnumerateArray().Select(line => new TextLine(
                line.GetProperty("text").GetString()!, Box(line.GetProperty("box")),
                Words: line.TryGetProperty("words", out var words)
                    ? words.EnumerateArray().Select(w => new TextWord(w.GetProperty("text").GetString()!, Box(w.GetProperty("box")))).ToList()
                    : null)).ToList();
            var look = Look(vector.GetProperty("look"));
            var expected = vector.GetProperty("kept").EnumerateArray().Select(t => t.GetString()!).ToList();
            var (kept, removed) = PackageText.Filter(new Reading(lines), Box(vector.GetProperty("area")), (_, _) => look);
            Assert.True(expected.SequenceEqual(kept.Lines.Select(l => l.Text)), $"{name}: {kept.Text}");
            Assert.Equal(lines.Count - expected.Count, removed.Count);
        }
    }

    [Fact]
    public void LookFromPixels()
    {
        foreach (var vector in Root().GetProperty("pixels").EnumerateArray())
        {
            var name = vector.GetProperty("name").GetString();
            int w = vector.GetProperty("size")[0].GetInt32(), h = vector.GetProperty("size")[1].GetInt32();
            var box = Box(vector.GetProperty("box"));
            var others = vector.GetProperty("others").EnumerateArray().Select(Box).ToList();
            var boxes = new[] { box }.Concat(others).ToList();
            var ground = vector.GetProperty("ground");
            var kind = ground.GetProperty("kind").GetString();
            int[] a = ground.GetProperty("a").EnumerateArray().Select(v => v.GetInt32()).ToArray();
            int[] b = ground.GetProperty("b").EnumerateArray().Select(v => v.GetInt32()).ToArray();
            var period = ground.GetProperty("period").GetInt32();
            int[] ink = vector.GetProperty("ink").EnumerateArray().Select(v => v.GetInt32()).ToArray();
            static int Pack(int[] c) => (c[0] << 16) | (c[1] << 8) | c[2];
            int Rgb(int x, int y)
            {
                foreach (var k in boxes)
                {
                    double top = k.Top * h, height = (k.Bottom - k.Top) * h;
                    if (x >= (int)Math.Floor(k.Left * w) && x < (int)Math.Ceiling(k.Right * w)
                        && y >= (int)Math.Floor(top) && y < (int)Math.Ceiling(k.Bottom * h)
                        && y >= top + (0.15 * height) && y < top + (0.85 * height) && (x / 2) % 2 == 0)
                        return Pack(ink);
                }
                return kind switch
                {
                    "checker" => Pack(((x / period) + (y / period)) % 2 == 0 ? a : b),
                    "gradient" => Pack([.. Enumerable.Range(0, 3).Select(i => a[i] + ((b[i] - a[i]) * x / (w - 1)))]),
                    _ => Pack(a),
                };
            }
            var look = PackageText.Measure(box, others, w, h, Rgb);
            Assert.True(look == Look(vector.GetProperty("look")), $"{name}: {look}");
        }
    }
}
