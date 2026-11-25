// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// "Ekranı çevir" öğelerinin yerleşimi: çeviri özgün yazının birebir yerinde çizilsin, simgeleri hiç örtmesin
/// (Mac: CouchSubsCore/ScreenFit.swift, Android: ScreenFit.kt; aynı kurallar). TV ve öbür çiziciler bunlara göre çizer:
/// <list type="bullet">
/// <item>Çeviri yatayda özgün yazının kutusundan hiç taşmaz: önce en çok %10 yatay sıkıştırma, sonra yazı küçülür, sonra satır
/// kırılır ve kutu aşağı uzar (<see cref="Layout"/>). Önceden kutu simgeye kadar yana genişliyor, tuş simgesinin üstüne
/// biniyordu (#1203).</item>
/// <item><see cref="ScreenTranslation.Item.Room"/>: kenar payının gidebileceği yatay alan. Özgün yazının iki yanında en çok
/// <see cref="EdgeLines"/> satır yüksekliği; zeminden belirgin ayrılan ilk noktadan (kumanda simgesi, menü simgesi, fotoğraf,
/// başka yazı) satır yüksekliğinin çeyreği önce biter; aynı satırdaki komşu öğeyle arası ortadan bölünür. Zemin rengi
/// bilinmiyorsa kutunun kendisidir.</item>
/// <item>Kutu yalnız yazının noktalarını kapsar: yazı tanıma kutusunun ucundaki simge (<see cref="IconEdges"/>) kutunun
/// dışında kalır.</item>
/// <item>Hiza: alt alta dizilmiş kısa etiketlerin sağ kenarları aynıysa hepsi sağa yaslı, sol kenarları aynıysa sola; aynı
/// satırda en az üç etiket varsa (menü şeridinin sekmeleri) ortalı.</item>
/// <item>Eş öğeler (aynı satırdaki sekmeler, alt alta menü satırları) aynı yazı boyunda (#859).</item>
/// </list>
/// </summary>
public static class ScreenFit
{
    public const double GapLines = 0.25;
    /// <summary>Kenar payı kutunun her yanında en çok bu kadar satır yüksekliği; yazının kendisi kutunun dışına çıkmaz.</summary>
    public const double EdgeLines = 0.3;
    public const double SameLine = 0.15;
    /// <summary>Düşük: kumanda düğmesinin koyu halkası zemine yakındır; yanlış bulunan nokta yalnız kenar payını daraltır.</summary>
    public const int InkDistance = 32;
    public const double IconGapLines = 0.1;
    public const double IconTaller = 1.1;
    public const double IconTallerAlone = 1.5;
    public const int IconInk = 30;

    /// <summary>Öğeler yerleşim bilgileriyle; kare yoksa olduğu gibi.</summary>
    public static IReadOnlyList<ScreenTranslation.Item> Fitted(IReadOnlyList<ScreenTranslation.Item> items, Frame? frame)
    {
        if (frame is null || frame.Width <= 0 || frame.Height <= 0 || !frame.IsConsistent) return items;
        var aspect = (double)frame.Width / frame.Height;
        int Luma(int x, int y)
        {
            var p = (y * frame.Stride) + (x * 4);
            return ((299 * frame.Pixels[p + 2]) + (587 * frame.Pixels[p + 1]) + (114 * frame.Pixels[p])) / 1000;
        }
        var tight = Tightened(items, frame, aspect, (box, lineX, words) => IconEdges(box, lineX, words, frame.Width, frame.Height, Luma));
        var laid = Uniform(Aligned(tight, aspect), aspect);
        (int R, int G, int B) Color(int x, int y)
        {
            var p = (y * frame.Stride) + (x * 4);
            return (frame.Pixels[p + 2], frame.Pixels[p + 1], frame.Pixels[p]);
        }
        var roomy = WithRoom(laid, aspect, Color, frame.Width, frame.Height);
        return Painted(roomy, frame.Width, frame.Height, Color);
    }

    /// <summary>
    /// Yerinde birebir çizim ölçüleri (<see cref="TextPainter"/>): özgün stilli her öğeye <see cref="ScreenTranslation.Item.Paint"/>
    /// (yalnız yazı değişince; çağıran okuma turudur, her kare değil).
    /// </summary>
    internal static List<ScreenTranslation.Item> Painted(IReadOnlyList<ScreenTranslation.Item> items, int width, int height,
        Func<int, int, (int R, int G, int B)> color)
    {
        var indices = Enumerable.Range(0, items.Count).Where(i => TakesPart(items[i]) && items[i].Style is not null && items[i].Look is not null).ToList();
        var result = items.ToList();
        if (indices.Count == 0) return result;
        var paints = TextPainter.Paints([.. indices.Select(i => Target(items[i]))], width, height, color);
        for (var k = 0; k < indices.Count && k < paints.Count; k++)
        {
            var item = result[indices[k]] with { Paint = paints[k] };
            // Kutunun ucunda simge varsa yazı simgeye yaslanır (#1266, #1267).
            if (paints[k].IconSide is { } side && item.Look is { } look) item = item with { Look = look with { Align = side } };
            result[indices[k]] = item;
        }
        return result;
    }

    internal static TextPainter.Target Target(ScreenTranslation.Item item) =>
        new(item.Box, item.LineHeight, item.Paragraphs ? Math.Max(2, item.Rows) : item.Rows, item.Style!.Background,
            item.Style.Foreground, item.Look!.Upper, item.Look.Align, TextPainter.WordCount(item.Source));

    /// <summary>
    /// Konuşma satırı (#1224, #1255, #1259): konuşan adıyla başlar ("Lucia: Evet.") ya da küçük harf taşıyan tek satır olup
    /// cümle sonu noktalamasıyla biter ("Ne?", "Yoldan çık."). Oyunun altyazısı ekran yazısı olarak da okunabiliyor; kısa
    /// replik etiket sayılıp özgün yazının dar ailesiyle çiziliyor, TV'de "dar ve basık" görünüyordu. Konuşma satırı hiçbir
    /// zaman dar aile almaz (<see cref="ScreenStyleLock.Steady"/>). Mac/iPhone: ScreenFit.isDialogue, Android:
    /// ScreenFit.isDialogue, TV: app.js isDialogue.
    /// </summary>
    public static bool IsDialogue(string text, int rows = 1)
    {
        var line = text.Trim();
        if (line.Length == 0) return false;
        if (SpeakerPrefix.Parse(line) is not null) return true;
        if (rows > 1 || line.Contains('\n') || !line.Any(char.IsLower)) return false;
        var end = line.TrimEnd('"', '\'', '”', '’', '»', ')', ']');
        return end.Length > 0 && ".!?…".Contains(end[^1]);
    }

    internal static bool IsDialogue(ScreenTranslation.Item item) =>
        IsDialogue(item.Translation, item.Paragraphs ? Math.Max(2, item.Rows) : item.Rows);

    internal static bool TakesPart(ScreenTranslation.Item item) =>
        item.Look is not null && !ScreenTranslation.IsCardPart(item) && !item.Bubble;

    private static double Height(TextBox box) => box.Bottom - box.Top;

    private static double RowOverlap(TextBox a, TextBox b) =>
        Math.Max(0, Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Top, b.Top)) / Math.Max(1e-9, Math.Min(Height(a), Height(b)));

    internal static List<ScreenTranslation.Item> Tightened(IReadOnlyList<ScreenTranslation.Item> items, Frame frame, double aspect,
        Func<TextBox, double, IReadOnlyList<string>, (double? Left, double? Right)>? icons = null)
    {
        var result = items.ToList();
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (!TakesPart(item) || item.Icons is { Count: > 0 }) continue;
            var box = item.Box;
            var lineX = item.LineHeight / aspect;
            // Kutunun en az yarısı kalmalı; kalmıyorsa o kesim yanlıştır (koyu dokulu zemin), yapılmaz.
            bool Keeps(double l, double r) => r - l >= 0.5 * (box.Right - box.Left);
            double left = box.Left, right = box.Right;
            var spans = ScreenTranslation.InkSpans(frame, box, 0.6 * lineX);
            if (spans.Count >= 2)
            {
                double l = box.Left, r = box.Right;
                if (spans[^1].Right - spans[^1].Left <= 1.5 * lineX) r = spans[^2].Right;
                if (spans[0].Right - spans[0].Left <= 1.5 * lineX && (spans.Count >= 3 || r == box.Right)) l = spans[1].Left;
                if (Keeps(l, r)) { left = l; right = r; }
            }
            if (item.Rows <= 1 && icons is not null)
            {
                var edges = icons(box, lineX, item.Source.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
                double l = Math.Max(left, edges.Left ?? left), r = Math.Min(right, edges.Right ?? right);
                if (Keeps(l, r)) { left = l; right = r; }
            }
            if (left == box.Left && right == box.Right) continue;
            result[i] = item with { Box = new TextBox(left, box.Top, right, box.Bottom) };
        }
        return result;
    }

    /// <summary>
    /// Yazı tanıma kutusunun ucundaki kumanda/menü simgesi (Mac: ScreenFit.iconEdges, aynı örnekleme): kutunun yatay alanı,
    /// üstünden ve altından yarım kutu yüksekliği fazlasıyla taranır; zeminden (ortanca parlaklık) <see cref="IconInk"/>'ten çok
    /// ayrılan noktalar <see cref="IconGapLines"/>'tan geniş boşluklarla parçalara bölünür. Uçtaki parça aşağı yukarı kare
    /// (en/boy 0,6-1,8) ve öbür parçaların en uzunundan uzunsa simgedir: okunan yazı o parçayı açıklamıyorsa
    /// <see cref="IconTaller"/> kat (uçtaki sözcük okunmuş simge ya da küçük harfsiz kısa etikette parça sayısı sözcüklerden
    /// çok), açıklıyorsa <see cref="IconTallerAlone"/> kat ve hem üste hem alta taşarak. Dönen: yazının başladığı/bittiği yer.
    /// </summary>
    public static (double? Left, double? Right) IconEdges(TextBox box, double lineX, IReadOnlyList<string>? words, int frameWidth,
        int frameHeight, Func<int, int, int> luma)
    {
        double fw = frameWidth, fh = frameHeight;
        var half = 0.5 * (box.Bottom - box.Top);
        double top = Math.Max(0, box.Top - half), bottom = Math.Min(1, box.Bottom + half);
        double left = Math.Max(0, box.Left), right = Math.Min(1, box.Right);
        double width = (right - left) * fw, height = (bottom - top) * fh;
        if (width < 8 || height < 6 || frameWidth <= 0 || frameHeight <= 0) return (null, null);
        var columns = Math.Max(8, Math.Min(800, (int)Math.Round(width, MidpointRounding.AwayFromZero)));
        const int rows = 24;
        var cells = new int[columns * rows];
        for (var y = 0; y < rows; y++)
        {
            var py = Math.Min(frameHeight - 1, (int)((top * fh) + ((y + 0.5) * height / rows)));
            for (var x = 0; x < columns; x++)
            {
                var px = Math.Min(frameWidth - 1, (int)((left * fw) + ((x + 0.5) * width / columns)));
                cells[(y * columns) + x] = luma(px, py);
            }
        }
        var median = cells.Order().ElementAt(cells.Length / 2);
        var ink = cells.Select(v => Math.Abs(v - median) > IconInk).ToArray();
        var step = (right - left) / columns;
        var blank = Math.Max(1, (int)Math.Ceiling(IconGapLines * lineX / Math.Max(1e-9, step)));
        // Parça: [ilk sütun, son sütun, en üst satır, en alt satır].
        var spans = new List<int[]>();
        int[]? open = null;
        var run = 0;
        for (var x = 0; x < columns; x++)
        {
            int first = -1, last = -1;
            for (var y = 0; y < rows; y++)
            {
                if (!ink[(y * columns) + x]) continue;
                if (first < 0) first = y;
                last = y;
            }
            if (first >= 0)
            {
                if (open is null) open = [x, x, first, last];
                else { open[1] = x; open[2] = Math.Min(open[2], first); open[3] = Math.Max(open[3], last); }
                run = 0;
            }
            else if (open is not null && ++run > blank)
            {
                spans.Add(open);
                open = null;
                run = 0;
            }
        }
        if (open is not null) spans.Add(open);
        if (spans.Count < 2) return (null, null);
        double cellWidth = width / columns, cellHeight = height / rows;
        var extra = words is not null && spans.Count > words.Count && words.Count <= 5 && !string.Concat(words).Any(char.IsLower);
        bool IsIcon(int[] span, IEnumerable<int[]> others, string? edge)
        {
            var rest = others.ToList();
            var reference = rest.Count == 0 ? 0 : rest.Max(o => o[3] - o[2] + 1);
            int tall = span[3] - span[2] + 1, wide = span[1] - span[0] + 1;
            var shape = wide * cellWidth / (tall * cellHeight);
            if (reference <= 0 || shape < 0.6 || shape > 1.8) return false;
            if (extra || (edge is not null && ButtonIcons.IsIconToken(edge))) return tall >= IconTaller * reference;
            var above = rest.Min(o => o[2]);
            var below = rest.Max(o => o[3]);
            return tall >= IconTallerAlone * reference && span[2] < above && span[3] > below;
        }
        double? start = IsIcon(spans[0], spans.Skip(1), words?.FirstOrDefault()) ? left + (spans[1][0] * step) : null;
        double? end = IsIcon(spans[^1], spans.Take(spans.Count - 1), words?.LastOrDefault()) ? left + ((spans[^2][1] + 1) * step) : null;
        // İki parçalı kutuda ikisi birden simge olamaz.
        if (start is not null && end is not null && spans.Count < 3) return (null, null);
        return (start, end);
    }

    internal static List<ScreenTranslation.Item> Aligned(IReadOnlyList<ScreenTranslation.Item> items, double aspect)
    {
        var labels = Enumerable.Range(0, items.Count).Where(i => TakesPart(items[i]) && items[i].Rows <= 1).ToList();
        var result = items.ToList();
        foreach (var i in labels)
        {
            var box = items[i].Box;
            var tolerance = 0.5 * items[i].LineHeight / aspect;
            var column = labels.Where(j => j != i && RowOverlap(box, items[j].Box) == 0
                && Math.Abs((box.Top + box.Bottom) - (items[j].Box.Top + items[j].Box.Bottom)) / 2 <= 8 * items[i].LineHeight).ToList();
            var rights = column.Count(j => Math.Abs(items[j].Box.Right - box.Right) <= tolerance && Math.Abs(items[j].Box.Left - box.Left) > tolerance);
            var lefts = column.Count(j => Math.Abs(items[j].Box.Left - box.Left) <= tolerance && Math.Abs(items[j].Box.Right - box.Right) > tolerance);
            var row = labels.Count(j => j != i && RowOverlap(box, items[j].Box) >= 0.5);
            var align = rights >= 2 && rights > lefts ? "right" : lefts >= 2 ? "left" : row >= 2 ? "center"
                : column.Count == 0 && row == 0 ? LoneAlign(box, items[i].Rows) : null;
            if (align is not null) result[i] = result[i] with { Look = result[i].Look! with { Align = align } };
        }
        return result;
    }

    /// <summary>Ekranın yatay ortasından en çok bu kadar (kareye oranla) uzaktaki yalnız satır ortalıdır.</summary>
    public const double CenterTolerance = 0.02;

    /// <summary>
    /// Komşusu olmayan tek satırın hizası (#1264): ortası ekranın ortasındaysa (görev yazısı "Go to the motel kitchen with
    /// Lucia", altyazı gibi ortalı) "center". Tek satırın kendi kutusundan hiza çıkmıyor, sola yaslı sayılıyordu; Türkçesi kısa
    /// olunca yazı kutunun soluna kayıyor, sağında boş zemin kalıyordu. Değilse null (hiza değişmez).
    /// </summary>
    public static string? LoneAlign(TextBox box, int rows) =>
        rows <= 1 && Math.Abs((box.Left + box.Right) / 2 - 0.5) <= CenterTolerance ? "center" : null;

    internal static List<ScreenTranslation.Item> Uniform(IReadOnlyList<ScreenTranslation.Item> items, double aspect)
    {
        var labels = Enumerable.Range(0, items.Count).Where(i => TakesPart(items[i]) && items[i].Rows <= 1).ToList();
        var parent = labels.ToDictionary(i => i, i => i);
        int Root(int i) { while (parent[i] != i) i = parent[i]; return i; }
        foreach (var a in labels)
            foreach (var b in labels.Where(b => b > a))
            {
                var x = items[a];
                var y = items[b];
                if (x.Look!.Upper != y.Look!.Upper || x.Look.Bold != y.Look.Bold
                    || Math.Abs(x.LineHeight - y.LineHeight) > SameLine * Math.Max(x.LineHeight, y.LineHeight)) continue;
                var tolerance = 0.5 * Math.Max(x.LineHeight, y.LineHeight) / aspect;
                var sameRow = RowOverlap(x.Box, y.Box) >= 0.5;
                var sameColumn = (Math.Abs(x.Box.Left - y.Box.Left) <= tolerance || Math.Abs(x.Box.Right - y.Box.Right) <= tolerance)
                    && Math.Abs(x.Box.Top - y.Box.Top) <= 3 * Math.Max(x.LineHeight, y.LineHeight);
                if (sameRow || sameColumn) parent[Root(a)] = Root(b);
            }
        var result = items.ToList();
        foreach (var members in labels.GroupBy(Root).Where(g => g.Count() >= 2))
        {
            var lines = members.Select(i => items[i].LineHeight).Order().ToList();
            var median = lines[lines.Count / 2];
            foreach (var i in members) result[i] = result[i] with { LineHeight = median };
        }
        return result;
    }

    /// <summary>Her öğenin kenar payının gidebileceği yatay alan. <paramref name="color"/>: karenin noktası (kırmızı, yeşil, mavi).</summary>
    internal static List<ScreenTranslation.Item> WithRoom(IReadOnlyList<ScreenTranslation.Item> items, double aspect,
        Func<int, int, (int R, int G, int B)> color, int frameWidth, int frameHeight)
    {
        var result = items.ToList();
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];
            if (!TakesPart(item)) continue;
            var box = item.Box;
            var lineX = item.LineHeight / aspect;
            var gap = GapLines * lineX;
            var hasGround = item.Style is { } known && DesignTokens.Rgb(known.Background) is not null;
            // Zemin bilinmiyorsa yandaki simge aranamaz: kenar payı da kutunun içinde kalır.
            var edgeX = hasGround ? EdgeLines * lineX : 0;
            double left = Math.Max(0, box.Left - edgeX), right = Math.Min(1, box.Right + edgeX);
            for (var j = 0; j < items.Count; j++)
            {
                var other = items[j].Box;
                if (j == i || RowOverlap(box, other) < 0.3) continue;
                if (other.Left >= box.Right - 1e-9) right = Math.Min(right, (box.Right + other.Left) / 2);
                if (other.Right <= box.Left + 1e-9) left = Math.Max(left, (other.Right + box.Left) / 2);
            }
            if (item.Style is { } style && DesignTokens.Rgb(style.Background) is { } rgb)
            {
                var background = ((int)(rgb.R * 255), (int)(rgb.G * 255), (int)(rgb.B * 255));
                var y0 = (int)Math.Round((box.Top + (0.2 * Height(box))) * frameHeight, MidpointRounding.AwayFromZero);
                var y1 = (int)Math.Round((box.Bottom - (0.2 * Height(box))) * frameHeight, MidpointRounding.AwayFromZero);
                var rows = new List<int>();
                for (var y = y0; y <= Math.Max(y0, y1); y += Math.Max(1, (y1 - y0) / 6)) rows.Add(Math.Clamp(y, 0, frameHeight - 1));
                double? Scan(double start, double end)
                {
                    int a = (int)Math.Round(start * frameWidth, MidpointRounding.AwayFromZero), b = (int)Math.Round(end * frameWidth, MidpointRounding.AwayFromZero);
                    if (a == b) return null;
                    var step = b > a ? 1 : -1;
                    var ground = background;
                    for (var x = a; x != b; x += step)
                    {
                        if (x < 0 || x >= frameWidth) continue;
                        var far = 0;
                        int r = 0, g = 0, bl = 0;
                        foreach (var y in rows)
                        {
                            var c = color(x, y);
                            far = Math.Max(far, Math.Max(Math.Abs(c.R - ground.Item1), Math.Max(Math.Abs(c.G - ground.Item2), Math.Abs(c.B - ground.Item3))));
                            r += c.R; g += c.G; bl += c.B;
                        }
                        if (far > InkDistance) return (double)x / frameWidth;
                        var n = rows.Count;
                        ground = (((ground.Item1 * 7) + (r / n)) / 8, ((ground.Item2 * 7) + (g / n)) / 8, ((ground.Item3 * 7) + (bl / n)) / 8);
                    }
                    return null;
                }
                var edge = 2.0 / frameWidth;
                // Simgeyle arada gap kalsın diye tarama kenar payından gap kadar öteye gider.
                if (Scan(box.Right + edge, Math.Min(1, right + gap)) is { } inkRight) right = Math.Min(right, inkRight - gap);
                if (Scan(box.Left - edge, Math.Max(0, left - gap)) is { } inkLeft) left = Math.Max(left, inkLeft + gap);
            }
            result[i] = item with { Room = new TextBox(Math.Min(box.Left, left), box.Top, Math.Max(box.Right, right), box.Bottom) };
        }
        return result;
    }

    // --- Yerinde birebir çizim (TV fitExact ile aynı sıra; TextPaint gelen öğeler; Mac/iPhone ve Android ile aynı) ---

    /// <summary>
    /// Birebir çizilecek bir öğe (piksel, çizilen ekranda). <c>Left/Top/Right/Bottom</c>: örtü kutusu; <c>GrowLeft</c>/
    /// <c>GrowRight</c>: kutunun yana uzayabileceği sınırlar (uzayamıyorsa örtünün kenarı); <c>Line</c>: özgün satır
    /// yüksekliği; <c>Pitch</c>: özgün satır aralığı; <c>Align</c>: "left", "right", "center".
    /// </summary>
    public sealed record ExactInput
    {
        public string Text { get; init; }
        public double Left { get; init; }
        public double Top { get; init; }
        public double Right { get; init; }
        public double Bottom { get; init; }
        public double GrowLeft { get; init; }
        public double GrowRight { get; init; }
        public double Line { get; init; }
        public double Pitch { get; init; }
        public int Rows { get; init; }
        public string Align { get; init; }
        public int? Group { get; init; }
        /// <summary>Yazı küçülmez (ikiz kutu, beta.100: "aynı punto, küçültme yok"): sığmazsa satır kırılır, kutu aşağı uzar.</summary>
        public bool KeepSize { get; init; }

        public ExactInput(string text, double left, double top, double right, double bottom, double? growLeft = null,
                          double? growRight = null, double line = 0, double? pitch = null, int rows = 1, string align = "left",
                          int? group = null, bool keepSize = false)
        {
            KeepSize = keepSize;
            Text = text;
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
            GrowLeft = Math.Min(left, growLeft ?? left);
            GrowRight = Math.Max(right, growRight ?? right);
            Line = line;
            Pitch = pitch ?? line;
            Rows = rows;
            Align = align;
            Group = group;
        }

        /// <summary>
        /// Ekrana oranlı öğeden (<see cref="ScreenTranslation.Item.Paint"/> olmalı) <paramref name="width"/> x
        /// <paramref name="height"/> piksellik çizim alanına; Paint yoksa null. Örtmeyen kipte (<see cref="TextPaint.Mode"/>)
        /// yazı <see cref="TextPaint.Spot"/>'a, <see cref="TextPaint.SpotRoom"/> içinde dizilir; ikizde yazı boyu
        /// <see cref="TextPaint.Scale"/> katında. Yanına yazılan Türkçe özgüne yaslanır (solundaysa sağa, sağındaysa sola).
        /// </summary>
        public static ExactInput? From(ScreenTranslation.Item item, double width, double height)
        {
            if (item.Paint is not { } paint) return null;
            var free = paint.Mode != PaintMode.Cover ? paint.Spot : null;
            var box = free ?? paint.Cover;
            var room = free != null ? paint.SpotRoom : paint.Grow;
            var scale = paint.Mode == PaintMode.Twin ? paint.Scale : 1;
            var align = item.Look?.Align ?? "left";
            if (paint.Mode == PaintMode.Beside)
            {
                if (box.Right <= paint.Cover.Left) align = "right";
                else if (box.Left >= paint.Cover.Right) align = "left";
            }
            return new ExactInput(item.Translation, box.Left * width, box.Top * height, box.Right * width,
                box.Bottom * height, room is { } g ? g.Left * width : null, room is { } h ? h.Right * width : null,
                Math.Max(1, item.LineHeight * height * scale), Math.Max(1, paint.Pitch * height * scale),
                item.Paragraphs ? Math.Max(2, item.Rows) : item.Rows, align, paint.Mode == PaintMode.Twin ? null : paint.Group,
                paint.Mode == PaintMode.Twin);
        }
    }

    /// <summary>
    /// Bir öğenin çizimi: kutu (piksel), yazı boyu, satırlar ve satır aralığı. Kutu opak, köşesiz, gölgesiz çizilir; satırlar
    /// <c>LineHeight</c> aralıkla (k. satır <c>Top + k * LineHeight</c>'tan başlar), hizaya göre; her satır <c>RowHeight</c>
    /// yüksekliğin dikey ortasında (özgün satırın yerinde).
    /// </summary>
    public sealed record ExactPlacement(double Left, double Top, double Width, double Height, double FontSize,
                                        IReadOnlyList<string> Lines, double LineHeight, double RowHeight);

    /// <summary>Yazı boyu özgün satır yüksekliğinin bu katı (TV, Mac, Windows, iPhone, Android aynı).</summary>
    public const double ExactFont = 0.95;
    /// <summary>Sığmayan etiket (ve grubu) yazı boyunda en çok bu orana kadar küçülür; sonra satır kırılır.</summary>
    public const double ExactGroupMin = 0.7;
    /// <summary>Çok satırlı yazı en çok bu orana kadar küçülür; sonra kutu aşağı uzar.</summary>
    public const double ExactParagraphMin = 0.8;
    /// <summary>Satır kırılan etiketin satır aralığı, yazı boyunun katı.</summary>
    public const double ExactWrapGap = 1.2;

    private static string[] SplitWords(string text) => text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

    /// <summary>
    /// Birebir yerleşim (Mac: ScreenFit.exact, aynı sıra). Sırasıyla: (1) grubun (aynı listedeki etiketler) yazı boyu
    /// üyelerinin özgün boyunun ortancası; (2) sığmayan etiket hizasının açık tarafındaki boş alana uzar, yazı boyu sabit;
    /// (3) boş alan da yetmezse grubun tamamı birlikte küçülür (en çok <see cref="ExactGroupMin"/>); (4) yine sığmayan
    /// etiketin satırı kırılır, kutu aşağı uzar; tek sözcük yine sığmıyorsa yalnız o küçülür. Çok satırlı yazı özgün genişlik
    /// ve satır aralığında kalır; sığmazsa <see cref="ExactParagraphMin"/>'e kadar küçülür, sonra aşağı uzar. Yazı hiçbir
    /// zaman "…" ile kesilmez. <paramref name="measure"/>(yazı, boy): yazının çizicinin kendi yazı tipiyle genişliği.
    /// </summary>
    public static IReadOnlyList<ExactPlacement> Exact(IReadOnlyList<ExactInput> items, Func<string, double, double> measure)
    {
        var count = items.Count;
        var baseSize = items.Select(item => ExactFont * item.Line).ToArray();
        var members = new Dictionary<int, List<int>>();
        for (var i = 0; i < count; i++)
        {
            if (items[i].Group is not { } g) continue;
            if (!members.TryGetValue(g, out var list)) members[g] = list = [];
            list.Add(i);
        }
        foreach (var list in members.Values.Where(list => list.Count >= 2))
        {
            var sizes = list.Select(i => baseSize[i]).Order().ToList();
            var median = sizes[sizes.Count / 2];
            foreach (var i in list) baseSize[i] = median;
        }
        static bool IsLabel(ExactInput item) => item.Rows <= 1 && !item.Text.Contains('\n');
        var natural = Enumerable.Range(0, count).Select(i => IsLabel(items[i]) ? measure(items[i].Text, baseSize[i]) : 0).ToArray();
        var scale = Enumerable.Range(0, count).Select(i => !IsLabel(items[i]) || natural[i] <= 0 || items[i].KeepSize ? 1
            : Math.Max(ExactGroupMin, Math.Min(1, (items[i].GrowRight - items[i].GrowLeft) / natural[i]))).ToArray();
        foreach (var list in members.Values.Where(list => list.Count >= 2))
        {
            var least = list.Min(i => scale[i]);
            foreach (var i in list) scale[i] = least;
        }
        var result = new List<ExactPlacement>(count);
        for (var i = 0; i < count; i++)
        {
            var item = items[i];
            double coverWidth = item.Right - item.Left, coverHeight = item.Bottom - item.Top;
            if (!IsLabel(item)) { result.Add(ExactParagraph(item, baseSize[i], measure)); continue; }
            var font = baseSize[i] * scale[i];
            var avail = item.GrowRight - item.GrowLeft;
            var width = natural[i] * scale[i];
            IReadOnlyList<string> lines = [item.Text];
            var gap = coverHeight;
            if (width > avail + 0.5)
            {
                var words = SplitWords(item.Text);
                var widestWord = words.Length == 0 ? width : words.Max(word => measure(word, font));
                if (words.Length >= 2)
                {
                    // Satır kırılır; satıra sığmayan sözcük varsa yazı yalnız bu öğede küçülür (yana taşmaz).
                    if (widestWord > avail + 0.5) font *= avail / widestWord;
                    var wrapFont = font;
                    lines = ExactWrap(words, avail, text => measure(text, wrapFont));
                }
                else
                {
                    font *= avail / Math.Max(1e-9, width);
                }
                var lineFont = font;
                width = lines.Count == 0 ? avail : lines.Max(line => measure(line, lineFont));
                if (lines.Count > 1) gap = Math.Max(coverHeight / lines.Count, font * ExactWrapGap);
            }
            var boxWidth = Math.Max(coverWidth, Math.Min(avail, width));
            var left = item.Align switch
            {
                "right" => item.Right - boxWidth,
                "center" => item.Left - ((boxWidth - coverWidth) / 2),
                _ => item.Left,
            };
            left = Math.Min(Math.Max(left, item.GrowLeft), item.GrowRight - boxWidth);
            result.Add(new ExactPlacement(left, item.Top, boxWidth, Math.Max(coverHeight, lines.Count * gap), font, lines, gap, gap));
        }
        return result;
    }

    /// <summary>
    /// Çok satırlı yazı: özgün genişlik ve satır aralığı; sığmazsa <see cref="ExactParagraphMin"/>'e kadar küçülür, sonra
    /// aşağı uzar.
    /// </summary>
    private static ExactPlacement ExactParagraph(ExactInput item, double baseSize, Func<string, double, double> measure)
    {
        double coverWidth = item.Right - item.Left, coverHeight = item.Bottom - item.Top;
        var factor = 1.0;
        // Özgün bir satırın yüksekliği (kenar payıyla): son satır tam aralık değil, bu kadar yer kaplar.
        var row = Math.Max(baseSize * 1.05, coverHeight - ((Math.Max(1, item.Rows) - 1) * item.Pitch));
        (double Font, List<string> Lines, double Gap) Layout()
        {
            var font = baseSize * factor;
            var gap = Math.Max(item.Pitch, baseSize * 1.05) * factor;
            var lines = item.Text.Split('\n').SelectMany(paragraph =>
            {
                var words = SplitWords(paragraph);
                return words.Length == 0 ? [""] : ExactWrap(words, coverWidth, text => measure(text, font));
            }).ToList();
            return (font, lines, gap);
        }
        double Tall((double Font, List<string> Lines, double Gap) laid) => ((laid.Lines.Count - 1) * laid.Gap) + (row * factor);
        var laid = Layout();
        while (!item.KeepSize && Tall(laid) > coverHeight + 1 && factor > ExactParagraphMin + 1e-6)
        {
            factor = Math.Max(ExactParagraphMin, Math.Round((factor - 0.05) * 100, MidpointRounding.AwayFromZero) / 100);
            laid = Layout();
        }
        // Satıra sığmayan tek sözcük: yazı küçülür (yana taşmaz).
        var widest = laid.Lines.Count == 0 ? 0 : laid.Lines.Max(line => measure(line, laid.Font));
        if (widest > coverWidth + 0.5)
        {
            factor *= coverWidth / widest;
            laid = Layout();
        }
        return new ExactPlacement(item.Left, item.Top, coverWidth, Math.Max(coverHeight, Tall(laid)), laid.Font, laid.Lines,
                                  laid.Gap, row * factor);
    }

    /// <summary>Sözcükler satırlara: her satır <paramref name="limit"/>'e kadar dolar.</summary>
    internal static List<string> ExactWrap(IReadOnlyList<string> words, double limit, Func<string, double> measure)
    {
        var lines = new List<string>();
        var current = "";
        foreach (var word in words)
        {
            var next = current.Length == 0 ? word : current + " " + word;
            if (current.Length > 0 && measure(next) > limit + 0.5)
            {
                lines.Add(current);
                current = word;
            }
            else current = next;
        }
        if (current.Length > 0 || lines.Count == 0) lines.Add(current);
        return lines;
    }

    // --- Çizicilerin ortak satır yerleşimi (TV fitStyled ile aynı sıra; Mac/iPhone ve Android ile aynı) ---

    /// <summary>Bir çevirinin çizimi: satırları, yalnız yatay ölçeği ve yazı boyunun ölçeği. Alan her zaman özgün kutudur.</summary>
    public sealed record Lines(IReadOnlyList<string> Rows, double Squeeze, double Scale);

    /// <summary>Yatay sıkıştırma yalnız en çok iki sözcüklük tek satırlık etikette ve en çok %10.</summary>
    public const double FirstSqueeze = 0.9;
    /// <summary>Sığmayan çok satırlı yazı önce bu orana kadar küçülür, sonra satır eklenir.</summary>
    public const double MinScale = 0.6;
    /// <summary>Sığmayan tek satırlık etiket ve tek sözcük en çok bu orana kadar küçülür (etiket sonra satıra iner).</summary>
    public const double LastScale = 0.5;
    /// <summary>Ekran yazısının en küçük boyu, konuşma altyazısının (öntanımlı, 1080 satırlık ekranda) bu kadarı.</summary>
    public const double FloorShare = 0.6;
    public const double SubtitleFont = 46.0;

    /// <summary>Ekran yazısı alt sınırının özgün yazı boyuna oranı (<see cref="Layout"/>'un <c>floor</c>'u).</summary>
    public static double Floor(double fontSize, double screenHeight) =>
        fontSize > 0 ? FloorShare * SubtitleFont * screenHeight / 1080 / fontSize : 0;

    /// <summary>
    /// Çeviriyi özgün yazının alanına (genişliği <paramref name="width"/>, piksel) yerleştirir; alan yana hiç genişlemez
    /// (Mac: ScreenFit.lines, aynı sıra). Sığmazsa: en çok iki sözcüklük etikette en çok %10 yatay sıkıştırma, yazının
    /// küçülmesi (tek satırlık etiket <see cref="LastScale"/>'e, çok satırlı yazı <see cref="MinScale"/>'e kadar, alt sınırın
    /// altına inmeden), satır kırma (kutu aşağı uzar), tek sözcükte <see cref="LastScale"/>'e kadar.
    /// </summary>
    public static Lines Layout(string text, double width, int rows, Func<string, double> measure, double floor = 0)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        IReadOnlyList<string> lines = text.Split('\n');
        var count = Math.Max(rows, lines.Count);
        var squeezable = count <= 1 && words.Length <= 2;
        // Alt sınır yalnız cümlede (en az üç sözcük ya da çok satırlı yazı): kısa etiket simgeye taşmasın diye küçülebilir.
        if (squeezable) floor = 0;
        var limit = squeezable ? width / FirstSqueeze : width;
        if (lines.Count == 1 && count > 1)
            lines = Wrapped(words, Math.Max(limit, measure(text) / count), count, measure);
        var widest = lines.Count == 0 ? 0 : lines.Max(measure);
        var start = Math.Max(1, floor);
        var scale = start;
        if (widest * start > limit)
        {
            var least = Math.Max(floor, count > 1 ? MinScale : LastScale);
            if (widest * least > limit && words.Length >= 2)
            {
                lines = lines.SelectMany(line => Wrapped(line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries),
                    limit / least, int.MaxValue, measure)).ToList();
                widest = lines.Max(measure);
            }
            // Satıra sığmayan tek sözcük alt sınırın da altına küçülür: yana taşmamak önce gelir.
            scale = Math.Max(LastScale, Math.Min(start, limit / Math.Max(1e-9, widest)));
        }
        var squeeze = squeezable && widest > 0 ? Math.Max(FirstSqueeze, Math.Min(1, width / (widest * scale))) : 1;
        return new Lines(lines, squeeze, scale);
    }

    /// <summary>Sözcükler satırlara: her satır <paramref name="limit"/>'e kadar dolar, en çok <paramref name="cap"/> satır.</summary>
    private static List<string> Wrapped(IReadOnlyList<string> words, double limit, int cap, Func<string, double> measure)
    {
        var made = new List<string>();
        var current = "";
        foreach (var word in words)
        {
            var next = current.Length == 0 ? word : current + " " + word;
            if (current.Length > 0 && measure(next) > limit && made.Count < cap - 1) { made.Add(current); current = word; }
            else current = next;
        }
        if (current.Length > 0 || made.Count == 0) made.Add(current);
        return made;
    }

    /// <summary>
    /// Kutunun sol ve sağ kenar payı (piksel): en çok <paramref name="pad"/>, kenar payı alanının dışına çıkmadan. Alan
    /// bilinmiyorsa kenar payı yoktur: yandaki simgenin yeri bilinmez.
    /// </summary>
    public static (double Left, double Right) Pads(double left, double width, (double Left, double Right)? room, double pad) =>
        room is not { } r ? (0, 0) : (Math.Min(pad, Math.Max(0, left - r.Left)), Math.Min(pad, Math.Max(0, r.Right - (left + width))));
}
