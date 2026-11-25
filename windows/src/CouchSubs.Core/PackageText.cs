// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Oyun dünyasındaki ürün, ambalaj ve etiket yazısı (bira kutusu, süt kartonu, şişe etiketi) yerinde dursa da ekran yazısı
/// ya da altyazı değildir. Sinan Bey (beta.101, GTA 6, buzdolabı): ambalajların yazıları ekran yazısı sayılıp ürünlerin
/// üstüne üst üste çiziliyordu. Kamerayla kayan tabela <see cref="SceneMotion"/> ile, alt alta kısa tabela
/// <see cref="SceneText"/> ile yakalanıyor; hareketsiz ambalaj hiçbirine takılmıyordu.
/// Satır ancak bunların HEPSİ tutarsa ambalaj yazısıdır (muhafazakâr): marka biçimi (<see cref="IsBrandShape"/>), sahnede
/// (<see cref="InScene"/>: HUD şeritleri dışında, büyük başlık boyunda değil), yazı arayüz mürekkebi değil (en parlak
/// noktalar açık ve renksiz değil) ve zemin desenli ya da taban çizgisi eğik. Görüntü yoksa hiçbir satır atılmaz.
/// Mac/iPhone (PackageText.swift) ve Android (PackageText.kt) aynı kuralları ve eşikleri uygular; ortak deneme dosyası
/// core/Tests/CouchSubsCoreTests/Fixtures/package-text.json.
/// </summary>
public static class PackageText
{
    public const string Reason = "ambalaj/etiket yazısı (sahnede, desenli zeminde)";
    public const int MaxWords = 3;
    public const int MaxLength = 20;
    public const double SceneLeft = 0.08;
    public const double SceneRight = 0.92;
    public const double SceneTop = 0.10;
    public const double SceneBottom = 0.80;
    public const double MaxHeight = 0.045;
    public const double TextureStep = 10.0;
    public const int UiLuma = 185;
    public const int UiChroma = 30;
    public const double RingShare = 0.5;
    public const double RingGap = 0.15;
    public const double TiltShift = 0.35;

    private const int SamplesX = 32;
    private const int SamplesY = 8;
    private const int RingSamples = 2;
    private const int MinPairs = 16;

    /// <summary>Satırın görüntüden ölçülen görünüşü.</summary>
    public readonly record struct Look(bool Textured, bool UiInk);

    /// <summary>Satır ambalaj yazısı mı. <paramref name="box"/> karede (0–1); görünüş yoksa atılmaz.</summary>
    public static bool IsPackage(TextLine line, TextBox box, Look? look)
    {
        if (look is not { } seen || seen.UiInk || (line.Icons?.Count ?? 0) > 0 || !IsBrandShape(line.Text) || !InScene(box))
            return false;
        return seen.Textured || IsTilted(line.Words);
    }

    /// <summary>Marka/etiket biçimi: bir-üç sözcük, her biri büyük harfle başlar; cümle noktalaması, tuş, konuşan adı yok.</summary>
    public static bool IsBrandShape(string text)
    {
        var plain = text.Trim(' ');
        if (plain.Length == 0 || plain.Length > MaxLength || plain.Contains(ButtonIcons.Marker)
            || plain.Any(c => ".,;:\"“”()[]/".Contains(c)) || "-–—".Contains(plain[0])
            || SpeakerPrefix.Parse(plain) is not null || ButtonPrompts.IsPrompt(plain)
            || UiCommands.TranslateLabelLoosely(plain) is not null) return false;
        var body = "!?".Contains(plain[^1]) ? plain[..^1] : plain;
        if (body.Any(c => c == '!' || c == '?')) return false;
        var words = body.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Where(w => w.Any(char.IsLetter)).ToList();
        if (words.Count < 1 || words.Count > MaxWords || (body.Length < plain.Length && words.Count < 2)) return false;
        return words.All(word => char.IsUpper(word.First(char.IsLetter)));
    }

    /// <summary>Satırın ortası sahnede (HUD şeritleri dışında) ve satır büyük başlık boyunda değil.</summary>
    public static bool InScene(TextBox box)
    {
        double x = (box.Left + box.Right) / 2, y = (box.Top + box.Bottom) / 2;
        return x >= SceneLeft && x <= SceneRight && y >= SceneTop && y <= SceneBottom && box.Bottom - box.Top <= MaxHeight;
    }

    internal static bool IsTilted(IReadOnlyList<TextWord>? words)
    {
        if (words is null || words.Count < 2) return false;
        var heights = words.Select(w => w.Box.Bottom - w.Box.Top).OrderBy(h => h).ToList();
        var median = heights[heights.Count / 2];
        if (median <= 0) return false;
        var middles = words.OrderBy(w => w.Box.Left).Select(w => (w.Box.Top + w.Box.Bottom) / 2).ToList();
        var shift = middles[^1] - middles[0];
        if (Math.Abs(shift) <= TiltShift * median) return false;
        var direction = shift > 0 ? 1.0 : -1.0;
        return middles.Zip(middles.Skip(1)).All(pair => (pair.Second - pair.First) * direction >= -0.15 * median);
    }

    /// <summary>
    /// Satırın görünüşü. Kutular görüntüye oranla; <paramref name="rgb"/> noktanın rengi (0xRRGGBB). Kutu çok küçükse null.
    /// </summary>
    public static Look? Measure(TextBox box, IReadOnlyList<TextBox> others, int width, int height, Func<int, int, int> rgb)
    {
        if (width <= 0 || height <= 0) return null;
        double w = width, h = height;
        double left = Math.Max(0, box.Left) * w, right = Math.Min(1, box.Right) * w;
        double top = Math.Max(0, box.Top) * h, bottom = Math.Min(1, box.Bottom) * h;
        if (right - left < 4 || bottom - top < 3) return null;
        var inside = new List<(int Luma, int Chroma)>(SamplesX * SamplesY);
        for (var sy = 0; sy < SamplesY; sy++)
        {
            var y = Math.Min(height - 1, (int)(top + ((sy + 0.5) * (bottom - top) / SamplesY)));
            for (var sx = 0; sx < SamplesX; sx++)
            {
                var x = Math.Min(width - 1, (int)(left + ((sx + 0.5) * (right - left) / SamplesX)));
                inside.Add(Split(rgb(x, y)));
            }
        }
        var bright = inside.OrderByDescending(p => p.Luma).Take(inside.Count / 4).ToList();
        var luma = bright.Sum(p => p.Luma) / bright.Count;
        var chroma = bright.Sum(p => p.Chroma) / bright.Count;
        var uiInk = luma >= UiLuma && chroma <= UiChroma;
        double line = bottom - top, gap = line * RingGap, thick = line * RingShare;
        var blocked = others.Select(o =>
        {
            var pad = (o.Bottom - o.Top) * h * RingGap;
            return (L: (o.Left * w) - pad, T: (o.Top * h) - pad, R: (o.Right * w) + pad, B: (o.Bottom * h) + pad);
        }).ToList();
        double sum = 0;
        var pairs = 0;
        foreach (var (stripTop, stripBottom) in new[] { (top - gap - thick, top - gap), (bottom + gap, bottom + gap + thick) })
        {
            if (stripTop < 0 || stripBottom > h) continue;
            for (var row = 0; row < RingSamples; row++)
            {
                var yf = stripTop + ((row + 0.5) * (stripBottom - stripTop) / RingSamples);
                var y = Math.Min(height - 1, (int)yf);
                int? previous = null;
                for (var sx = 0; sx < SamplesX; sx++)
                {
                    var xf = left + ((sx + 0.5) * (right - left) / SamplesX);
                    if (blocked.Any(b => xf >= b.L && xf <= b.R && yf >= b.T && yf <= b.B))
                    {
                        previous = null;
                        continue;
                    }
                    var value = Split(rgb(Math.Min(width - 1, (int)xf), y)).Luma;
                    if (previous is { } before)
                    {
                        sum += Math.Abs(value - before);
                        pairs++;
                    }
                    previous = value;
                }
            }
        }
        return new Look(pairs >= MinPairs && sum / pairs >= TextureStep, uiInk);
    }

    private static (int Luma, int Chroma) Split(int rgb)
    {
        int r = (rgb >> 16) & 0xff, g = (rgb >> 8) & 0xff, b = rgb & 0xff;
        return (((299 * r) + (587 * g) + (114 * b)) / 1000, Math.Max(r, Math.Max(g, b)) - Math.Min(r, Math.Min(g, b)));
    }

    /// <summary>
    /// Okumadan ambalaj yazısı satırlarını çıkarır. Satır kutuları okunan alana oranlı; <paramref name="area"/> alanın
    /// karedeki yeri; <paramref name="look"/> (kutu, öbür kutular) okunan alanın görüntüsünden ölçer.
    /// </summary>
    public static (Reading Kept, IReadOnlyList<TextLine> Removed) Filter(Reading reading, TextBox area,
                                                                         Func<TextBox, IReadOnlyList<TextBox>, Look?>? look)
    {
        if (look is null || reading.Lines.Count == 0) return (reading, []);
        var kept = new List<TextLine>();
        var removed = new List<TextLine>();
        for (var i = 0; i < reading.Lines.Count; i++)
        {
            var line = reading.Lines[i];
            if (line.Box is not { } box || !IsBrandShape(line.Text) || (line.Icons?.Count ?? 0) > 0 || !InScene(box.PlacedIn(area)))
            {
                kept.Add(line);
                continue;
            }
            var others = reading.Lines.Where((other, j) => j != i && other.Box is not null).Select(other => other.Box!.Value).ToList();
            if (IsPackage(line, box.PlacedIn(area), look(box, others))) removed.Add(line); else kept.Add(line);
        }
        return removed.Count == 0 ? (reading, []) : (new Reading(kept), removed);
    }

    /// <summary>Okunan alanın görüntüsü (BGRA) için ölçücü.</summary>
    public static Func<TextBox, IReadOnlyList<TextBox>, Look?>? Sampler(Frame? frame) =>
        frame is null || !frame.IsConsistent ? null : (box, others) => Measure(box, others, frame.Width, frame.Height, (x, y) =>
        {
            var p = (y * frame.Stride) + (x * 4);
            return (frame.Pixels[p + 2] << 16) | (frame.Pixels[p + 1] << 8) | frame.Pixels[p];
        });
}
