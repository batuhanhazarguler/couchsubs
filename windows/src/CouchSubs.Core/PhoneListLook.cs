// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Telefon listesi kartlarının (<see cref="ScreenPhoneCard.ListRow"/>) oyundan kesilen görüntüleri: avatar (bileşende simge),
/// sağdaki rozet ve seçili satırın çerçevesi. Sinan Bey (beta.100, 3399): kart telefondaki satırın Türkçe kopyası olsun;
/// avatar, okunmamış kırmızı nokta (avatarın köşesinde, kesilen resmin içinde kalır), rozet ve seçim çerçevesi de.
///
/// Kararlılık (#1279): aynı satırın resmi bir kez kesilir ve saklanır (anahtar: kişi adının özgün yazısı); her okumada
/// yeniden kesilen resim, sıkıştırma gürültüsüyle her gönderiyi farklı gösterip TV'de titretirdi. Rozet ve seçim ancak art
/// arda <see cref="Turns"/> okumada aynı yeni değeri gösterirse değişir. Resimler küçük PNG'dir (en çok
/// <see cref="AvatarMax"/> piksel). Mac/iPhone (PhoneListLook.swift) ve Android (PhoneListLook.kt) aynı kural, aynı eşikler.
/// </summary>
public sealed class PhoneListLook
{
    /// <summary>Avatarın ve rozetin en uzun kenarı (piksel).</summary>
    public const int AvatarMax = 48, BadgeMax = 32;
    /// <summary>Rozet ve seçim bu kadar art arda okumada aynı yeni değeri gösterirse değişir.</summary>
    internal const int Turns = 2;
    /// <summary>En çok bu kadar satır saklanır (dolunca hepsi unutulur).</summary>
    internal const int Capacity = 64;

    private sealed class Entry
    {
        public string? Avatar, Badge, Selected;
        public bool HasPendingBadge, HasPendingSelected;
        public string? PendingBadge, PendingSelected;
        public int BadgeVotes, SelectedVotes;
    }

    private readonly Dictionary<string, Entry> entries = new(StringComparer.Ordinal);
    private readonly object gate = new();

    public void Clear()
    {
        lock (gate) entries.Clear();
    }

    /// <summary>Kare (BGRA noktalar) üzerinden.</summary>
    public IReadOnlyList<ScreenTranslation.Item> Apply(IReadOnlyList<ScreenTranslation.Item> items, Frame frame)
    {
        if (!items.Any(item => item.ListRow is not null) || !frame.IsConsistent) return items;
        return Apply(items, frame.Width, frame.Height, (x, y) =>
        {
            var p = (y * frame.Stride) + (x * 4);
            return (frame.Pixels[p + 2], frame.Pixels[p + 1], frame.Pixels[p]);
        });
    }

    /// <summary>Liste kartlarına resimleri koyar. <paramref name="color"/>: karenin (x, y) pikseli.</summary>
    public IReadOnlyList<ScreenTranslation.Item> Apply(IReadOnlyList<ScreenTranslation.Item> items, int width, int height,
                                                       Func<int, int, (int R, int G, int B)> color)
    {
        if (width <= 0 || height <= 0) return items;
        lock (gate)
        {
            if (entries.Count > Capacity) entries.Clear();
            return [.. items.Select(item =>
            {
                if (item.ListRow is not { } row) return item;
                var key = (row.Widget ? "w|" : "r|") + item.Source.Split('\n')[0];
                var first = !entries.TryGetValue(key, out var entry);
                entry ??= new Entry();
                if (entry.Avatar is null && row.PortraitSpot is { } portrait)
                    entry.Avatar = TextPainter.PortraitImage(portrait, width, height, color, AvatarMax);
                if (row.BadgeSpot is { } badgeSpot)
                {
                    var fresh = HasBadge(badgeSpot, width, height, color)
                        ? TextPainter.PortraitImage(badgeSpot, width, height, color, BadgeMax) : null;
                    Vote(fresh, ref entry.Badge, ref entry.HasPendingBadge, ref entry.PendingBadge, ref entry.BadgeVotes, first);
                }
                if (row.FrameSpot is { } frameSpot)
                {
                    var fresh = FrameColor(frameSpot, width, height, color);
                    Vote(fresh, ref entry.Selected, ref entry.HasPendingSelected, ref entry.PendingSelected, ref entry.SelectedVotes, first);
                }
                entries[key] = entry;
                return item with { ListRow = row with { Avatar = entry.Avatar, Badge = entry.Badge, Selected = entry.Selected } };
            })];
        }
    }

    /// <summary>
    /// Yeni değer (var/yok olarak aynı sayılmayan) art arda <see cref="Turns"/> okumada gelirse geçer; ilk görülen satırda
    /// hemen geçer.
    /// </summary>
    private static void Vote(string? fresh, ref string? current, ref bool hasPending, ref string? pending, ref int votes, bool first)
    {
        static bool Same(string? a, string? b) => (a is null) == (b is null);
        if (first)
        {
            current = fresh;
            return;
        }
        if (Same(fresh, current))
        {
            votes = 0;
            hasPending = false;
            pending = null;
            return;
        }
        if (hasPending && Same(pending, fresh))
        {
            votes++;
        }
        else
        {
            hasPending = true;
            pending = fresh;
            votes = 1;
        }
        if (votes >= Turns)
        {
            current = fresh;
            votes = 0;
            hasPending = false;
            pending = null;
        }
    }

    /// <summary>Örnek ızgarası (kutunun içinde <paramref name="columns"/>×<paramref name="rows"/> nokta).</summary>
    private static (int R, int G, int B)[][] Samples(TextBox box, int width, int height, int columns, int rows,
                                                    Func<int, int, (int R, int G, int B)> color) =>
        [.. Enumerable.Range(0, rows).Select(j =>
        {
            var y = Math.Min(height - 1, Math.Max(0, (int)((box.Top + ((j + 0.5) / rows * (box.Bottom - box.Top))) * height)));
            return Enumerable.Range(0, columns).Select(i =>
            {
                var x = Math.Min(width - 1, Math.Max(0, (int)((box.Left + ((i + 0.5) / columns * (box.Right - box.Left))) * width)));
                return color(x, y);
            }).ToArray();
        })];

    /// <summary>Belirgin mavi (seçim çerçevesi, gönder rozeti).</summary>
    private static bool IsBlue((int R, int G, int B) c) => c.B >= 140 && c.B - ((c.R + c.G) / 2) >= 45;

    /// <summary>
    /// Satırın üstünde seçim çerçevesi var mı: kutunun bir yatay sırasındaki noktaların en az <see cref="FrameShare"/>'i
    /// mavi. Varsa çerçevenin rengi (mavi noktaların ortalaması).
    /// </summary>
    internal const double FrameShare = 0.6;
    internal static string? FrameColor(TextBox box, int width, int height, Func<int, int, (int R, int G, int B)> color)
    {
        foreach (var line in Samples(box, width, height, 24, 12, color))
        {
            var blue = line.Where(IsBlue).ToList();
            if (blue.Count > 0 && blue.Count >= line.Length * FrameShare)
            {
                int r = blue.Sum(c => c.R) / blue.Count, g = blue.Sum(c => c.G) / blue.Count, b = blue.Sum(c => c.B) / blue.Count;
                return $"#{r:X2}{g:X2}{b:X2}";
            }
        }
        return null;
    }

    /// <summary>
    /// Rozetin yerinde düz kart zemini değil bir simge var mı: noktaların en az <see cref="BadgeShare"/>'i zeminden (kutunun
    /// köşelerinin ortancası) belirgin farklı ve renkli/koyu.
    /// </summary>
    internal const double BadgeShare = 0.12;
    internal static bool HasBadge(TextBox box, int width, int height, Func<int, int, (int R, int G, int B)> color)
    {
        var grid = Samples(box, width, height, 10, 10, color);
        static int Tone((int R, int G, int B) c) => (c.R + (2 * c.G) + c.B) / 4;
        var @base = new[] { grid[0][0], grid[0][9], grid[9][0], grid[9][9] }.Select(Tone).OrderBy(t => t).ElementAt(1);
        var marked = grid.SelectMany(line => line).Count(c =>
        {
            var chroma = Math.Max(c.R, Math.Max(c.G, c.B)) - Math.Min(c.R, Math.Min(c.G, c.B));
            return chroma >= 60 && Math.Abs(Tone(c) - @base) >= 25;
        });
        return marked >= 100 * BadgeShare;
    }
}
