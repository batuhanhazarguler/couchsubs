// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>
/// Bir ekran yazısının yerinde, arayüz Türkçe yapılmış gibi çizilmesi için göndericinin kareden ölçtükleri (TV pikselleri
/// okuyamaz). Yalnız yazı değişince ölçülür (Mac: CouchSubsCore/TextPaint.swift, Android: TextPaint.kt; aynı kurallar ve
/// eşikler). TV'ye öğenin <c>bg</c>, <c>bg2</c>, <c>bgDir</c>, <c>bgPat</c>, <c>fg</c>, <c>weight</c>, <c>upper</c>,
/// <c>align</c>, <c>lineH</c>, <c>cover</c>, <c>grow</c>, <c>group</c> alanlarıyla gider; eski TV bunları yok sayıp eski
/// çizimi sürdürür.
/// </summary>
/// <param name="Background">Kutunun zemini (degradede başlangıç ucu: sol ya da üst). Opak çizilir.</param>
/// <param name="Pitch">Satır aralığı (bir satırın üstünden ötekinin üstüne), kareye oranla; tek satırda satır yüksekliği.</param>
/// <param name="Cover">
/// Özgün yazıyı tam örten kutu: yazı tanıma kutusu ve dışına taşan harf noktaları, en çok <see cref="TextPainter.MarginMax"/>
/// piksel payla. Simgeye doğru taşmaz.
/// </param>
public sealed record TextPaint(string Background, double Pitch, TextBox Cover)
{
    /// <summary>Yatay degrade (soldan sağa).</summary>
    public const string Horizontal = "h";
    /// <summary>Dikey degrade (üstten alta).</summary>
    public const string Vertical = "v";

    /// <summary>Degradenin öbür ucu (sağ ya da alt); düz zeminde null.</summary>
    public string? Background2 { get; init; }
    /// <summary>Degradenin yönü: <see cref="Horizontal"/> ya da <see cref="Vertical"/>; düz zeminde null.</summary>
    public string? Direction { get; init; }
    /// <summary>Zemin desenli (harita, dünya): <see cref="Background"/> ortalama renktir.</summary>
    public bool Patterned { get; init; }
    /// <summary>
    /// Kutunun yana uzayabileceği alan (yalnız tek satırlık etikette, hizanın açık tarafında): o yönde başka yazı, simge ya da
    /// kutu yok, yalnız oyunun zemini var. Simgeyle ya da komşuyla arada <see cref="ScreenFit.GapLines"/> kadar boşluk kalır.
    /// null: uzayamaz.
    /// </summary>
    public TextBox? Grow { get; init; }
    /// <summary>
    /// Aynı listede alt alta (ya da aynı satırda) duran, özgün hâlinde aynı boydaki etiketlerin ortak numarası; grubun hepsi
    /// aynı yazı boyunda çizilir. null: tek başına.
    /// </summary>
    public int? Group { get; init; }
    /// <summary>
    /// Yazı tanıma kutusunun ucundaki simge (menü simgesi, tuş simgesi) yazının hangi yanında ("left", "right"): örtü ve uzama
    /// o simgeye girmez, yazı o yana yaslanır (TV'ye <c>align</c> olarak gider). null: simge yok.
    /// </summary>
    public string? IconSide { get; init; }

    /// <summary>
    /// Çizim kipi (<see cref="TextPainter.Target.Kind"/> verilince seçilir; yalnız otomatik ekran yazısında):
    /// <see cref="PaintMode.Cover"/>, <see cref="PaintMode.Beside"/> ya da <see cref="PaintMode.Twin"/> (Sinan Bey: oyun dünyasının üstünde opak yama
    /// görünmesin). TV'ye <c>mode</c> olarak gider; eski TV yok sayıp örter.
    /// </summary>
    public string Mode { get; init; } = PaintMode.Cover;
    /// <summary>
    /// beside/twin: Türkçenin yazıldığı kutu (yanına yazmada özgün yazının yanındaki boş alan, örtü boyunda; ikizde özgün
    /// yazının ikiz paneldeki yeri). TV'ye <c>spot</c>.
    /// </summary>
    public TextBox? Spot { get; init; }
    /// <summary><see cref="Spot"/>'un yana uzayabileceği alan (yalnız sol ve sağ kenarı anlamlı). TV'ye <c>spotRoom</c>.</summary>
    public TextBox? SpotRoom { get; init; }
    /// <summary>twin: ikiz panelin kutusu (özgün panelin <see cref="Scale"/> katı, sol kenarı hizalı). TV'ye <c>twinBox</c>.</summary>
    public TextBox? Twin { get; init; }
    /// <summary>twin: panelin köşe yarıçapı (ikizde), kare yüksekliğine oranla. TV'ye <c>radius</c>.</summary>
    public double Radius { get; init; }
    /// <summary>twin: ikizin özgüne oranı (<see cref="TextPainter.TwinScale"/>): yazı boyu ve satır aralığı bu katta. TV'ye <c>scale</c>.</summary>
    public double Scale { get; init; } = 1;
    /// <summary>twin: konuşma balonunun kuyruğu hangi alt köşede ("left"/"right"); null: kuyruk yok. TV'ye <c>tail</c>.</summary>
    public string? Tail { get; init; }
    /// <summary>twin: panelin solundaki kare resim (kişi resmi): karedeki yeri (kesmek için).</summary>
    public TextBox? Portrait { get; init; }
    /// <summary>twin: kişi resminin ikiz paneldeki yeri.</summary>
    public TextBox? PortraitTwin { get; init; }
    /// <summary>
    /// Kesilmiş resim (PNG, data: adresi; en çok <see cref="TextPainter.PortraitMax"/> piksel); çağıran keser
    /// (<see cref="TextPainter.PortraitImage(TextBox, Frame)"/>). TV'ye <c>icon</c> ({src, box}).
    /// </summary>
    public string? PortraitImage { get; init; }

    /// <summary>Bu ölçüler <paramref name="area"/> içindeki oranlarsa, aynı yerin <paramref name="area"/>'yı içeren çerçevedeki oranları.</summary>
    public TextPaint PlacedIn(TextBox area) => this with
    {
        Cover = Cover.PlacedIn(area),
        Grow = Grow?.PlacedIn(area),
        Pitch = Pitch * (area.Bottom - area.Top),
        Spot = Spot?.PlacedIn(area),
        SpotRoom = SpotRoom?.PlacedIn(area),
        Twin = Twin?.PlacedIn(area),
        Radius = Radius * (area.Bottom - area.Top),
        Portrait = Portrait?.PlacedIn(area),
        PortraitTwin = PortraitTwin?.PlacedIn(area),
    };
}

/// <summary>Çizim kipleri (<see cref="TextPaint.Mode"/>; Mac TextPaint.Mode, Android aynı adlar).</summary>
public static class PaintMode
{
    /// <summary>Örtme: düz/opak panel zemininde (menü, görev kartı, ayar listesi) özgün yazıyı örten kutu (eski davranış).</summary>
    public const string Cover = "cover";
    /// <summary>
    /// Yanına yazma: desenli zeminde ya da oyun dünyası üstündeki tek satırlık istemde örtü yok; özgün yazı yerinde kalır,
    /// Türkçe yanındaki boş alana özgün stille, okunurluk için konturla yazılır.
    /// </summary>
    public const string Beside = "beside";
    /// <summary>
    /// İkiz: yuvarlak köşeli düz panel (bildirim, ipucu kutusu) örtülmez; Türkçesi aynı zemin, köşe ve yazı rengiyle,
    /// <see cref="TextPainter.TwinScale"/> katı boyda hemen üstüne (yer yoksa altına) ayrı panel olarak çizilir.
    /// </summary>
    public const string Twin = "twin";
}

/// <summary>
/// <see cref="TextPaint"/> ölçümü. Piksel erişimi soyuttur (<c>color(x, y)</c>): ortak deneme dosyası (core
/// Fixtures/text-paint.json) üç platformda aynı yapay kareyi kurar.
/// </summary>
public static class TextPainter
{
    /// <summary>
    /// Ölçülecek yazı: kareye oranla kutusu ve satır yüksekliği, özgün satır sayısı, sampler'ın bulduğu zemin/yazı rengi ve
    /// hizası ("left", "right", "center").
    /// </summary>
    /// <remarks>
    /// <c>Words</c>: okunan yazının sözcük sayısı (simge sanılan karakterler sayılmaz, <see cref="WordCount"/>); 0:
    /// bilinmiyor, kutunun ucundaki simge aranmaz. <c>Kind</c>: yazının türü; verilirse çizim kipi seçilir
    /// (<see cref="TextPaint.Mode"/>), null: hep örtme ("Ekranı çevir"). <c>Prompt</c>: yazı bir tuş istemi/eylemi ("Hold L2
    /// to aim"): düz zeminde de yanına yazılabilir.
    /// </remarks>
    public sealed record Target(TextBox Box, double LineHeight, int Rows, string Background, string Foreground, bool Upper,
                                string Align, int Words = 0, ScreenTextKind? Kind = null, bool Prompt = false);

    /// <summary>
    /// Kutunun ucundaki simgeyi yazıdan ayıran en dar boşluk, satır yüksekliğinin katı (harf arası bundan dardır; GTA 6
    /// menüsünde simgeyle yazı arası ~0,4 satır).
    /// </summary>
    public const double IconGapLines = 0.3;
    /// <summary>Simge parçasının genişliği satır yüksekliğinin bu katları arasında ("I" harfi gibi ince parça simge sayılmaz).</summary>
    public const double IconMinWide = 0.45;
    public const double IconMaxWide = 1.6;
    /// <summary>Simge sanılıp yazı olarak okunan karakterler (GTA 6 menü simgesi "I", "II"; tuş simgeleri).</summary>
    private const string IconGlyphs = "I|l![]()©®@○◯●□■△▲✕✖×◎⊗⊙";

    /// <summary>
    /// Okunan yazının sözcük sayısı: simge sanılan bir iki karakterlik parçalar ve harfi/rakamı olmayan parçalar sayılmaz
    /// ("I Map" → 1, "SELECT ⊗" → 1, "- SMASH 'N' GRABS" → 3, "• Objective" → 1). Menü simgesi (yön tuşu, renkli nokta)
    /// "-", "•", "+" diye okununca sözcük sayılıyor, simge bulunmuyordu: kutu simgenin üstüne çiziliyordu (#1268, #1270;
    /// Mac ile aynı).
    /// </summary>
    public static int WordCount(string text) =>
        IconText.Plain(text).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Count(token => !(token.Length <= 2 && token.All(c => IconGlyphs.Contains(c))) && token.Any(char.IsLetterOrDigit));

    /// <summary>
    /// Kutunun ([l, r), piksel) ucundaki simge: harf sütunları (<paramref name="ink"/>) <see cref="IconGapLines"/> satırdan
    /// geniş boşluklarla parçalara bölünür; parça sayısı sözcük sayısından çoksa uçtaki simge genişliğindeki
    /// (<see cref="IconMinWide"/>-<see cref="IconMaxWide"/> satır) parça simgedir. İki uç da uyarsa hizanın yanı (sola yaslıda
    /// sol, öbürlerinde sağ) önce; ikincisi ancak iki fazla parça varsa. Simgeler çıkınca kalan parça sözcüklerden çoksa simge
    /// yoktur. Dönen: simgeler ve onlar çıkınca yazının sol/sağ kenarı.
    /// </summary>
    internal static ((int L, int R)? Left, (int L, int R)? Right, int TextLeft, int TextRight) IconSpans(
        int l, int r, double line, int words, string align, Func<int, bool> ink)
    {
        if (words <= 0 || r - l < 2) return (null, null, l, r);
        var gap = Math.Max(2, RoundHalfUp(IconGapLines * line));
        var spans = new List<(int L, int R)>();
        int? start = null;
        int last = l, blank = 0;
        for (var x = l; x < r; x++)
        {
            if (ink(x))
            {
                start ??= x;
                last = x;
                blank = 0;
            }
            else if (start is { } s)
            {
                blank++;
                if (blank >= gap) { spans.Add((s, last + 1)); start = null; blank = 0; }
            }
        }
        if (start is { } open) spans.Add((open, last + 1));
        if (spans.Count < 2 || spans.Count <= words) return (null, null, l, r);
        bool IsIcon((int L, int R) span)
        {
            double wide = span.R - span.L;
            return wide >= IconMinWide * line && wide <= IconMaxWide * line;
        }
        var extra = spans.Count - words;
        var first = spans[0];
        var final = spans[^1];
        (int L, int R)? left = null, right = null;
        if (align == "left")
        {
            if (IsIcon(first)) left = first;
            if (IsIcon(final) && (left == null || extra >= 2)) right = final;
        }
        else
        {
            if (IsIcon(final)) right = final;
            if (IsIcon(first) && (right == null || extra >= 2)) left = first;
        }
        // Simgeler çıkınca kalan parçalar sözcüklerden çok olamaz: harfleri aralıklı tek sözcük simge sanılmaz.
        if (spans.Count - (left == null ? 0 : 1) - (right == null ? 0 : 1) > words) return (null, null, l, r);
        return (left, right, left != null ? spans[1].L : l, right != null ? spans[^2].R : r);
    }

    /// <summary>Nokta zeminden bu kadar (en büyük renk bileşeni farkı) uzak ve yazı rengine zeminden yakınsa harf noktasıdır.</summary>
    public const int InkDistance = 40;
    /// <summary>Bir satır/sütunun en az bu kadarı harf noktasıysa orada yazı sürer.</summary>
    public const double InkShare = 0.03;
    /// <summary>Kutu yazı tanıma kutusunun dışına en çok bu kadar satır yüksekliği uzar (taşan harf ucu).</summary>
    public const double ReachLines = 0.5;
    /// <summary>Kenar payı: satır yüksekliğinin bu kadarı, en az 1, en çok <see cref="MarginMax"/> piksel.</summary>
    public const double MarginLines = 0.08;
    public const int MarginMax = 3;
    /// <summary>İki uç arasındaki fark (en büyük renk bileşeni) en az bu kadarsa zemin degradedir.</summary>
    public const int GradientStep = 10;
    /// <summary>Zeminin kendi içindeki sapması bundan büyükse zemin desenlidir.</summary>
    public const double PatternDeviation = TextStyleSampler.FlatDeviation;
    /// <summary>Kenar şeridinin ortalaması sampler'ın zemininden bu kadar uzaksa (seçili satırın kendi kutusu dar) sampler'ınki kalır.</summary>
    public const int TrustDistance = 48;
    /// <summary>Boş alan en çok bu kadar satır yüksekliği taranır.</summary>
    public const double GrowLines = 12.0;
    /// <summary>Aynı grup: satır yükseklikleri en çok bu oranda farklı (<see cref="ScreenFit.SameLine"/>).</summary>
    public const double SameLine = ScreenFit.SameLine;

    private static int RoundHalfUp(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    // Kip seçimi sabitleri (Mac TextPaint.swift, Android TextPaint.kt aynı).

    /// <summary>Panel taramasında nokta zeminden en çok bu kadar uzaksa (en büyük renk bileşeni farkı) panelin zeminidir.</summary>
    public const int PanelTolerance = 24;
    /// <summary>Bir satır/sütunun en az bu kadarı zemin (ya da yazı) ise panel o yöne sürer.</summary>
    public const double PanelShare = 0.7;
    /// <summary>Panel karenin en çok bu kadarı genişlikte/yükseklikte; daha büyüğü (gökyüzü, menünün kendisi) panel sayılmaz.</summary>
    public const double PanelMaxWidth = 0.45;
    public const double PanelMaxHeight = 0.35;
    /// <summary>Panel yazının her yanında en az bu kadar satır yüksekliği (en az 2 piksel) taşmalı; taşmıyorsa düz kutudur (örtülür).</summary>
    public const double PanelPadLines = 0.2;
    /// <summary>Köşe yuvarlak: panelin köşesinden köşegen boyunca en az bu kadar nokta zemin değil (aynı kenardaki iki köşede).</summary>
    public const int CornerMin = 2;
    /// <summary>Yanına yazmada bir sütunda/satırda yazı rengine (<see cref="BesideInk"/> kadar yakın) noktaların payı bundan azsa alan boştur.</summary>
    public const int BesideInk = 48;
    public const double BesideShare = 0.1;
    /// <summary>Türkçenin özgün yazıdan uzaklığı, satır yüksekliğinin katı.</summary>
    public const double BesideGapLines = 0.5;
    /// <summary>Yanına yazma alanı en çok özgün yazının bu katı (+ bir satır yüksekliği) genişlikte taranır.</summary>
    public const double BesideMax = 1.6;
    /// <summary>İkiz panel özgün panelin bu katı boyda (yazı, resim, köşe ve iç boşluk aynı oranda; Sinan Bey, #1296).</summary>
    public const double TwinScale = 0.58;
    /// <summary>İkizin yazısı en az karenin bu kadarı (TV app.js DIALOGUE_MIN_SHARE ile aynı).</summary>
    public const double TwinMinShare = 0.022;
    /// <summary>Kişi resmi (ikiz panelde gösterilir) en çok bu kadar piksel kenarlı kesilir.</summary>
    public const int PortraitMax = 40;

    /// <summary>
    /// Yazının (örtü kutusu [l, r) x [t, b)) çevresindeki düz alan: kutu, satır/sütunlarının en az <see cref="PanelShare"/>'i
    /// zemin (<paramref name="like"/>: zemin, yazının kendi örtü kutusu ya da başka hedef; harf noktası sayılmaz, koyu oyun
    /// dünyası koyu yazıya benzer) olduğu sürece dört yana büyür. Karenin kenarına değen ya da
    /// <see cref="PanelMaxWidth"/>/<see cref="PanelMaxHeight"/>'tan büyük alan açık zemindir (gökyüzü, menünün kendisi): null.
    /// </summary>
    internal static (int L, int T, int R, int B)? FindPanel(int l, int t, int r, int b, int width, int height,
                                                           Func<int, int, bool> like)
    {
        bool Row(int y, int x0, int x1)
        {
            var step = Math.Max(1, (x1 - x0) / 64);
            int n = 0, ok = 0;
            for (var x = x0; x < x1; x += step) { n++; if (like(x, y)) ok++; }
            return n > 0 && ok >= PanelShare * n;
        }
        bool Column(int x, int y0, int y1)
        {
            var step = Math.Max(1, (y1 - y0) / 64);
            int n = 0, ok = 0;
            for (var y = y0; y < y1; y += step) { n++; if (like(x, y)) ok++; }
            return n > 0 && ok >= PanelShare * n;
        }
        if (r <= l || b <= t) return null;
        int maxW = (int)(PanelMaxWidth * width), maxH = (int)(PanelMaxHeight * height);
        int pl = Math.Max(0, l), pt = Math.Max(0, t), pr = Math.Min(width, r), pb = Math.Min(height, b);
        var grew = true;
        while (grew)
        {
            grew = false;
            while (pl > 0 && Column(pl - 1, pt, pb)) { pl--; grew = true; if (pr - pl > maxW) return null; }
            while (pr < width && Column(pr, pt, pb)) { pr++; grew = true; if (pr - pl > maxW) return null; }
            while (pt > 0 && Row(pt - 1, pl, pr)) { pt--; grew = true; if (pb - pt > maxH) return null; }
            while (pb < height && Row(pb, pl, pr)) { pb++; grew = true; if (pb - pt > maxH) return null; }
        }
        if (pl == 0 || pt == 0 || pr == width || pb == height) return null;
        return (pl, pt, pr, pb);
    }

    /// <summary>
    /// Panelin ([l, r) x [t, b)) köşe yarıçapı (piksel) ve konuşma balonunun kuyruğu: köşeler (<paramref name="ground"/>:
    /// yalnız zemin) köşegen boyunca taranır; üst ya da alt kenarın iki köşesinde en az <see cref="CornerMin"/> nokta zemin
    /// değilse panel yuvarlaktır, yarıçap köşegendeki mesafeden (k / (1 − 1/√2)). Üst köşeler yuvarlakken alt köşelerden
    /// yalnız biri köşeliyse o köşede balonun kuyruğu vardır ("left"/"right"). null: köşeli kutu.
    /// </summary>
    internal static (double Radius, string? Tail)? CornerRadius(int l, int t, int r, int b, Func<int, int, bool> ground)
    {
        var limit = Math.Max(1, Math.Min(r - l, b - t) / 4);
        int Corner(int x, int y, int dx, int dy)
        {
            var k = 0;
            while (k <= limit && !ground(x + (dx * k), y + (dy * k))) k++;
            return k;
        }
        int tl = Corner(l, t, 1, 1), tr = Corner(r - 1, t, -1, 1);
        int bl = Corner(l, b - 1, 1, -1), br = Corner(r - 1, b - 1, -1, -1);
        bool Round(int k) => k >= CornerMin && k <= limit;
        bool top = Round(tl) && Round(tr), bottom = Round(bl) && Round(br);
        if (!top && !bottom) return null;
        var ks = new List<int>();
        if (top) { ks.Add(tl); ks.Add(tr); }
        if (bottom) { ks.Add(bl); ks.Add(br); }
        var radius = (double)ks.Sum() / ks.Count / (1 - (1 / Math.Sqrt(2.0)));
        string? tail = !top || bottom ? null : !Round(bl) && Round(br) ? "left" : Round(bl) && !Round(br) ? "right" : null;
        return (radius, tail);
    }

    /// <summary>
    /// Panelin solundaki kare resim (kişi resmi): panelin solu ile yazının arası, yazının satırı çevresinde (bir satır
    /// yüksekliği yukarı/aşağı); <paramref name="off"/> (zeminden belirgin ayrılan, başka yazı olmayan) noktaların sınırı. En
    /// az 0,8 satır yüksekliği (en az 6 piksel), en çok 4 satır yüksekliği, kareye yakın (0,75–1,33) ve yazıdan ayrıksa resimdir.
    /// </summary>
    internal static (int L, int T, int R, int B)? Portrait(int panelLeft, int panelTop, int panelBottom, int l, int t, int b,
                                                          double line, Func<int, int, bool> off)
    {
        int x0 = panelLeft + 2, x1 = l;
        int y0 = Math.Max(panelTop + 2, t - RoundHalfUp(line)), y1 = Math.Min(panelBottom - 2, b + RoundHalfUp(line));
        if (x1 <= x0 || y1 <= y0) return null;
        int minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1;
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++)
            {
                if (!off(x, y)) continue;
                minX = Math.Min(minX, x);
                maxX = Math.Max(maxX, x);
                minY = Math.Min(minY, y);
                maxY = Math.Max(maxY, y);
            }
        if (maxX < 0) return null;
        int w = maxX - minX + 1, h = maxY - minY + 1;
        var least = Math.Max(6, RoundHalfUp(0.8 * line));
        if (w < least || h < least || w > 4 * line || h > 4 * line || w < 0.75 * h || w > 1.33 * h
            || maxX + 1 + Math.Max(2, RoundHalfUp(ScreenFit.GapLines * line)) > l) return null;
        return (minX, minY, maxX + 1, maxY + 1);
    }

    /// <summary>Kişi resmini kareden keser: en çok <see cref="PortraitMax"/> piksel kenarlı (en yakın nokta örneklemesi), opak PNG data: adresi.</summary>
    public static string? PortraitImage(TextBox box, int width, int height, Func<int, int, (int R, int G, int B)> color)
    {
        int l = Math.Max(0, RoundHalfUp(box.Left * width)), t = Math.Max(0, RoundHalfUp(box.Top * height));
        int r = Math.Min(width, RoundHalfUp(box.Right * width)), b = Math.Min(height, RoundHalfUp(box.Bottom * height));
        if (r - l < 2 || b - t < 2) return null;
        var side = Math.Max(r - l, b - t);
        int ow = Math.Max(1, Math.Min(r - l, (r - l) * PortraitMax / side)), oh = Math.Max(1, Math.Min(b - t, (b - t) * PortraitMax / side));
        var pixels = new byte[ow * oh * 4];
        for (var j = 0; j < oh; j++)
            for (var i = 0; i < ow; i++)
            {
                var c = color(l + (i * (r - l) / ow), t + (j * (b - t) / oh));
                var p = ((j * ow) + i) * 4;
                // Kare BGRA (ButtonIcons.Png RGBA'ya çevirir).
                pixels[p] = (byte)Math.Clamp(c.B, 0, 255);
                pixels[p + 1] = (byte)Math.Clamp(c.G, 0, 255);
                pixels[p + 2] = (byte)Math.Clamp(c.R, 0, 255);
                pixels[p + 3] = 255;
            }
        return "data:image/png;base64," + Convert.ToBase64String(ButtonIcons.Png(new Frame(pixels, ow, oh, ow * 4)));
    }

    /// <summary>Kare üzerinden kişi resmi (BGRA noktalar).</summary>
    public static string? PortraitImage(TextBox box, Frame frame)
    {
        if (!frame.IsConsistent || frame.Width <= 0 || frame.Height <= 0) return null;
        return PortraitImage(box, frame.Width, frame.Height, (x, y) =>
        {
            var p = (y * frame.Stride) + (x * 4);
            return (frame.Pixels[p + 2], frame.Pixels[p + 1], frame.Pixels[p]);
        });
    }

    /// <summary>
    /// Yanına yazma alanı (Sinan Bey: "SELAMLA  GREET"): önce sol, sonra sağ, sonra üst (simgenin olduğu yana değil).
    /// <paramref name="free"/>: null başka hedef ya da simge (alan orada biter), true yazı rengine yakın nokta, false boş zemin.
    /// Bir sütun/satır, yazı rengindeki noktaları <see cref="BesideShare"/>'den azsa boştur. Türkçe özgün yazıdan
    /// <see cref="BesideGapLines"/>, öbür uçta <see cref="ScreenFit.GapLines"/> uzak; alan en az örtü kutusu genişliğinde
    /// olmalı (sol/sağ), üstte örtü kutusu kadar yükseklik boş olmalı. Dönen: örtü boyundaki yazı kutusu (piksel) ve
    /// uzayabileceği sol/sağ sınır.
    /// </summary>
    internal static (int L, int T, int R, int B, int RoomL, int RoomR)? BesideSpot(int l, int t, int r, int b, double line,
        int width, int height, bool iconLeft, bool iconRight, Func<int, int, bool?> free)
    {
        int w = r - l, h = b - t;
        if (w <= 0 || h <= 0 || t < 0 || b > height) return null;
        var near = Math.Max(2, RoundHalfUp(BesideGapLines * line));
        var far = Math.Max(1, (int)Math.Ceiling(ScreenFit.GapLines * line));
        var most = RoundHalfUp((BesideMax * w) + line);
        bool Open(IEnumerable<bool?> cells)
        {
            int n = 0, ink = 0;
            foreach (var cell in cells)
            {
                if (cell == null) return false;
                n++;
                if (cell == true) ink++;
            }
            return n > 0 && ink < BesideShare * n;
        }
        IEnumerable<bool?> ColumnCells(int x, int y0, int y1) { for (var y = y0; y < y1; y++) yield return free(x, y); }
        IEnumerable<bool?> RowCells(int y, int x0, int x1) { for (var x = x0; x < x1; x++) yield return free(x, y); }
        bool Column(int x, int y0, int y1) =>
            x >= 0 && x < width && y0 >= 0 && y1 <= height && y1 > y0 && Open(ColumnCells(x, y0, y1));
        bool Row(int y, int x0, int x1) =>
            y >= 0 && y < height && x0 >= 0 && x1 <= width && x1 > x0 && Open(RowCells(y, x0, x1));
        // x'ten step yönünde art arda boş sütun sayısı (en çok cap).
        int Run(int x, int step, int y0, int y1, int cap)
        {
            var n = 0;
            while (n < cap && Column(x + (step * n), y0, y1)) n++;
            return n;
        }
        var cap = near + most + far;
        // n boş sütundan yazıya kalan: yakın boşluk ve (alan engelle bittiyse) uzak boşluk çıkar.
        int Usable(int n) => Math.Min(most, n - near - (n < cap ? far : 0));
        if (!iconLeft)
        {
            var room = Usable(Run(l - 1, -1, t, b, cap));
            if (room >= w) return (l - near - w, t, l - near, b, l - near - room, l - near);
        }
        if (!iconRight)
        {
            var room = Usable(Run(r, 1, t, b, cap));
            if (room >= w) return (r + near, t, r + near + w, b, r + near, r + near + room);
        }
        var top = t - near - h;
        if (top >= 0)
        {
            var clear = true;
            for (var y = top; y < t - near && clear; y++) clear = Row(y, l, r);
            if (clear)
            {
                var side = w / 2;
                var nl = Run(l - 1, -1, top, t - near, side + far);
                var nr = Run(r, 1, top, t - near, side + far);
                var roomL = l - Math.Max(0, Math.Min(side, nl - (nl < side + far ? far : 0)));
                var roomR = r + Math.Max(0, Math.Min(side, nr - (nr < side + far ? far : 0)));
                return (l, top, r, t - near, roomL, roomR);
            }
        }
        return null;
    }

    /// <summary>Ölçümler (hedeflerle aynı sırada). <paramref name="width"/>/<paramref name="height"/>: karenin piksel boyu.</summary>
    public static IReadOnlyList<TextPaint> Paints(IReadOnlyList<Target> targets, int width, int height,
                                                  Func<int, int, (int R, int G, int B)> color)
    {
        if (width <= 0 || height <= 0) return [];
        double fw = width, fh = height;
        // Hedeflerin piksel kutuları (öbür hedefler engeldir); karenin dışına taşan kutu kareye kırpılır (#1255).
        static int Pixel(double v, int size, bool up)
        {
            if (!double.IsFinite(v)) return v > 0 ? size : 0;
            var p = up ? Math.Ceiling(v * size) : Math.Floor(v * size);
            return (int)Math.Min(size, Math.Max(0, p));
        }
        var rects = targets.Select(t => (L: Pixel(t.Box.Left, width, false), T: Pixel(t.Box.Top, height, false),
                                         R: Pixel(t.Box.Right, width, true), B: Pixel(t.Box.Bottom, height, true))).ToArray();
        var result = new List<TextPaint>(targets.Count);
        // Kip seçimi için: örtü kutuları (piksel), satır yükseklikleri, zeminler ve panel adayları.
        var covers = new List<(int L, int T, int R, int B)>();
        var lines = new List<double>();
        var grounds = new List<(int R, int G, int B)>();
        var panels = new SortedDictionary<int, (int L, int T, int R, int B)>();
        // Bir hedefin kutusu (except hariç) bu noktada mı.
        bool RectHit(int x, int y, int? except)
        {
            for (var j = 0; j < rects.Length; j++)
                if (j != except && x >= rects[j].L && x < rects[j].R && y >= rects[j].T && y < rects[j].B) return true;
            return false;
        }
        for (var index = 0; index < targets.Count; index++)
        {
            var target = targets[index];
            var bg = Rgb(target.Background);
            var fg = Rgb(target.Foreground);
            var line = Math.Max(1, target.LineHeight * fh);
            bool IsInk((int R, int G, int B) c)
            {
                var toBg = Distance(c, bg);
                return toBg > InkDistance && Distance(c, fg) < toBg;
            }
            // Kutunun ucundaki kendi simgesi (0. adım): öbür hedefler gibi engeldir; araya ScreenFit.GapLines boşluk kalır.
            var zones = new List<(int L, int R)>();
            bool Others(int x, int y)
            {
                foreach (var zone in zones) if (x >= zone.L && x < zone.R) return true;
                for (var j = 0; j < rects.Length; j++)
                    if (j != index && x >= rects[j].L && x < rects[j].R && y >= rects[j].T && y < rects[j].B) return true;
                return false;
            }
            bool InkRow(int y, int x0, int x1)
            {
                if (y < 0 || y >= height || x1 <= x0) return false;
                var step = Math.Max(1, (x1 - x0) / 200);
                int n = 0, ink = 0;
                for (var x = Math.Max(0, x0); x < Math.Min(width, x1); x += step)
                {
                    if (Others(x, y)) return false;
                    n++;
                    if (IsInk(color(x, y))) ink++;
                }
                return n > 0 && ink >= Math.Max(2, (int)Math.Ceiling(InkShare * n));
            }
            bool InkColumn(int x, int y0, int y1)
            {
                if (x < 0 || x >= width || y1 <= y0) return false;
                int n = 0, ink = 0;
                for (var y = Math.Max(0, y0); y < Math.Min(height, y1); y++)
                {
                    if (Others(x, y)) return false;
                    n++;
                    if (IsInk(color(x, y))) ink++;
                }
                return n > 0 && ink >= Math.Max(1, (int)Math.Ceiling(InkShare * n));
            }
            var (l, t, r, b) = rects[index];
            // 0) Kutunun ucundaki simge (#1266, #1267): yazı tanıma kutusu menü/tuş simgesini de alıyordu; kutu simgenin
            // üstüne çiziliyor, simge kayboluyordu. Simge kutudan çıkar ve engel olur: örtü, kenar payı ve uzama ona girmez.
            bool iconLeft = false, iconRight = false;
            if (target.Rows <= 1)
            {
                int t0 = t, b0 = b;
                var found = IconSpans(l, r, line, target.Words, target.Align, x => InkColumn(x, t0, b0));
                var keep = (int)Math.Ceiling(ScreenFit.GapLines * line);
                if (found.Left is { } li) { zones.Add((li.L - keep, li.R + keep)); iconLeft = true; }
                if (found.Right is { } ri) { zones.Add((ri.L - keep, ri.R + keep)); iconRight = true; }
                l = found.TextLeft;
                r = found.TextRight;
            }
            int textLeft = l, textRight = r;
            // 1) Örtü: yazı tanıma kutusunun dışına taşan harf noktaları (bitişik satır/sütunlar) kutuya katılır.
            var reach = Math.Max(1, RoundHalfUp(ReachLines * line));
            var yy0 = b;
            while (yy0 < Math.Min(height, rects[index].B + reach) && InkRow(yy0, l, r)) yy0++;
            b = yy0;
            yy0 = t - 1;
            while (yy0 >= Math.Max(0, rects[index].T - reach) && InkRow(yy0, l, r)) yy0--;
            t = yy0 + 1;
            var xx0 = r;
            while (xx0 < Math.Min(width, textRight + reach) && InkColumn(xx0, t, b)) xx0++;
            r = xx0;
            xx0 = l - 1;
            while (xx0 >= Math.Max(0, textLeft - reach) && InkColumn(xx0, t, b)) xx0--;
            l = xx0 + 1;
            // Kenar payı: yazının yanındaki boş noktalar; ötesinde başka yazı/simge varsa pay ona değmez.
            var margin = Math.Max(1, Math.Min(MarginMax, RoundHalfUp(MarginLines * line)));
            int Pad(Func<int, bool> blank)
            {
                var k = 0;
                while (k < margin && blank(k + 1)) k++;
                return k;
            }
            bool OthersInColumn(int x)
            {
                for (var y = t; y < b; y++) if (Others(x, y)) return true;
                return false;
            }
            int tt = t, bb = b, ll = l, rr = r;
            var padL = Pad(k => ll - k >= 0 && !InkColumn(ll - k, tt, bb) && !OthersInColumn(ll - k));
            var padR = Pad(k => rr - 1 + k < width && !InkColumn(rr - 1 + k, tt, bb) && !OthersInColumn(rr - 1 + k));
            var padT = Pad(k => tt - k >= 0 && !InkRow(tt - k, ll, rr));
            var padB = Pad(k => bb - 1 + k < height && !InkRow(bb - 1 + k, ll, rr));
            int cl = l - padL, cr = r + padR, ct = t - padT, cb = b + padB;
            var cover = new TextBox(cl / fw, ct / fh, cr / fw, cb / fh);

            // 2) Zemin: kutunun üstündeki ve altındaki şerit (yanlarda simge olabilir); sol/sağ üçte bir ve üst/alt farkı.
            var strip = Math.Max(2, RoundHalfUp(0.25 * line));
            var samples = new List<((int R, int G, int B) C, double Fx, bool Top)>();
            void Collect(int y0, int y1, bool top)
            {
                if (y0 < 0 || y1 > height || y1 <= y0) return;
                var step = Math.Max(1, (cr - cl) / 64);
                var rowStep = Math.Max(1, (y1 - y0) / 4);
                var found = new List<((int R, int G, int B) C, double Fx, bool Top)>();
                for (var y = y0; y < y1; y += rowStep)
                {
                    for (var x = Math.Max(0, cl); x < Math.Min(width, cr); x += step)
                    {
                        if (Others(x, y)) return;
                        var c = color(x, y);
                        if (IsInk(c)) continue;
                        found.Add((c, (double)(x - cl) / Math.Max(1, cr - cl - 1), top));
                    }
                }
                samples.AddRange(found);
            }
            Collect(ct - strip, ct, top: true);
            Collect(cb, cb + strip, top: false);
            var paint = new TextPaint(target.Background, Pitch(target), cover)
            {
                IconSide = iconLeft == iconRight ? null : iconLeft ? "left" : "right",
            };
            if (samples.Count >= 16)
            {
                var all = samples.Select(s => s.C).ToList();
                var average = Mean(all);
                if (Distance(average, bg) <= TrustDistance)
                {
                    var left = samples.Where(s => s.Fx < 1.0 / 3).Select(s => s.C).ToList();
                    var right = samples.Where(s => s.Fx > 2.0 / 3).Select(s => s.C).ToList();
                    var above = samples.Where(s => s.Top).Select(s => s.C).ToList();
                    var below = samples.Where(s => !s.Top).Select(s => s.C).ToList();
                    // Desen: her parçanın kendi içindeki sapması (degrade kendi başına desen sayılmaz).
                    var parts = new[] { true, false }.SelectMany(side => Enumerable.Range(0, 3).Select(third =>
                            samples.Where(s => s.Top == side && Math.Min(2, (int)(s.Fx * 3)) == third).Select(s => s.C).ToList()))
                        .Where(part => part.Count >= 4).ToList();
                    var spread = parts.Count == 0 ? Deviation(all) : parts.Select(Deviation).Sum() / parts.Count;
                    var dh = left.Count >= 4 && right.Count >= 4 ? Distance(Mean(left), Mean(right)) : 0;
                    var dv = above.Count >= 4 && below.Count >= 4 ? Distance(Mean(above), Mean(below)) : 0;
                    if (spread > PatternDeviation)
                    {
                        paint = paint with { Patterned = true, Background = Hex(average) };
                    }
                    else if (dh >= GradientStep && dh >= dv)
                    {
                        // Üçte birlerin ortası 1/6 ve 5/6'da: uçlara doğrusal uzatılır.
                        var a = Mean(left);
                        var z = Mean(right);
                        paint = paint with { Background = Hex(Extend(a, z, 0.25)), Background2 = Hex(Extend(z, a, 0.25)), Direction = TextPaint.Horizontal };
                    }
                    else if (dv >= GradientStep)
                    {
                        var a = Mean(above);
                        var z = Mean(below);
                        // Şeritlerin ortası kutunun yarım şerit dışında: uçlar içeri doğru aradeğerlenir.
                        double span = cb - ct + strip;
                        var inward = span > 0 ? strip / 2.0 / span : 0;
                        paint = paint with { Background = Hex(Extend(a, z, -inward)), Background2 = Hex(Extend(z, a, -inward)), Direction = TextPaint.Vertical };
                    }
                    else
                    {
                        paint = paint with { Background = Hex(average) };
                    }
                }
            }

            // 3) Boş alan: tek satırlık etiket hizasının açık tarafına (sağa yaslıda sola, sola yaslıda sağa, ortalıda iki
            // yana) uzayabilir; başka yazıya, simgeye, kutu kenarına ya da karenin kenarına GapLines kala durur. Kutunun ucunda
            // simge varsa yalnız simgenin öbür yanına uzar (sağdaki tuş simgesinde sola, soldaki menü simgesinde sağa).
            if (target.Rows <= 1)
            {
                var sixth = Math.Max(1, (cb - ct) / 6);
                var band = new List<int>();
                for (var y = ct + sixth; y < Math.Max(ct + 1, cb - sixth); y += sixth) band.Add(Math.Min(height - 1, Math.Max(0, y)));
                var gap = (int)Math.Ceiling(ScreenFit.GapLines * line);
                var limit = RoundHalfUp(GrowLines * line);
                int Scan(int start, int step, (int R, int G, int B) first)
                {
                    var ground = first;
                    var x = start;
                    var end = step < 0 ? Math.Max(-1, start - limit) : Math.Min(width, start + limit);
                    // Sınır karşılaştırması ve adım sınırı: başlangıç karenin dışında kalsa da döngü biter (#1255).
                    var steps = 0;
                    while ((step < 0 ? x > end : x < end) && x >= 0 && x < width && steps <= width)
                    {
                        steps++;
                        var blocked = band.Any(y => Others(x, y));
                        for (var j = 0; j < rects.Length && !blocked; j++)
                            blocked = j != index && x >= rects[j].L && x < rects[j].R && rects[j].B > ct && rects[j].T < cb;
                        if (blocked) return x - (step * gap);
                        int sr = 0, sg = 0, sb = 0;
                        foreach (var y in band)
                        {
                            var c = color(x, y);
                            if (Distance(c, ground) > ScreenFit.InkDistance) return x - (step * gap);
                            sr += c.R; sg += c.G; sb += c.B;
                        }
                        var n = band.Count;
                        // Degrade zeminde zemin yavaşça izlenir (ScreenFit.WithRoom ile aynı).
                        ground = (((ground.R * 7) + (sr / n)) / 8, ((ground.G * 7) + (sg / n)) / 8, ((ground.B * 7) + (sb / n)) / 8);
                        x += step;
                    }
                    return step < 0 ? Math.Max(0, end + 1) : Math.Min(width, end);
                }
                var startColor = Rgb(paint.Background);
                var endColor = Rgb(paint.Background2 ?? paint.Background);
                int gl = cl, gr = cr;
                var toLeft = !iconLeft && (target.Align != "left" || iconRight);
                var toRight = !iconRight && (target.Align != "right" || iconLeft);
                if (band.Count > 0 && toLeft) gl = Math.Min(cl, Math.Max(0, Scan(cl - 1, -1, startColor) + 1));
                if (band.Count > 0 && toRight) gr = Math.Max(cr, Math.Min(width, Scan(cr, 1, endColor)));
                if (gl < cl || gr > cr) paint = paint with { Grow = new TextBox(gl / fw, cover.Top, gr / fw, cover.Bottom) };
            }

            // 5) Kip (yalnız türü verilen yazıda): menü, görev/harita kartı ve telefon hep örtülür. Düz zemini sınırlı bir alansa
            // (panel) karar döngüden sonra panel panel verilir (twin ya da örtme); açık zeminde (desenli zemin, karenin kenarına
            // değen ya da çok büyük düz alan) desenli zeminde ya da tek satırlık istemde Türkçe yanındaki boş alana yazılır; yer
            // bulunamazsa örtülür.
            covers.Add((cl, ct, cr, cb));
            lines.Add(line);
            grounds.Add(Rgb(paint.Background));
            if (target.Kind is { } kind && kind != ScreenTextKind.Menu && kind != ScreenTextKind.Mission && kind != ScreenTextKind.Phone)
            {
                var ground = Rgb(paint.Background);
                var self = index;
                var panel = paint.Patterned || paint.Background2 != null ? null
                    : FindPanel(cl, ct, cr, cb, width, height, (x, y) =>
                        RectHit(x, y, self) || (x >= cl && x < cr && y >= ct && y < cb) || Distance(color(x, y), ground) <= PanelTolerance);
                if (panel is { } found)
                {
                    panels[index] = found;
                }
                else if ((paint.Patterned || (kind == ScreenTextKind.Help && target.Prompt && target.Rows <= 1))
                         && BesideSpot(cl, ct, cr, cb, line, width, height, iconLeft, iconRight,
                                       (x, y) => Others(x, y) ? null : Distance(color(x, y), fg) <= BesideInk) is { } spot)
                {
                    paint = paint with
                    {
                        Mode = PaintMode.Beside,
                        Spot = new TextBox(spot.L / fw, spot.T / fh, spot.R / fw, spot.B / fh),
                        SpotRoom = new TextBox(spot.RoomL / fw, spot.T / fh, spot.RoomR / fw, spot.B / fh),
                    };
                }
            }
            result.Add(paint);
        }
        // İkiz paneller: kesişen paneller tek paneldir (bildirimin başlığı ve gövdesi; birinin taraması paneldeki resimde erken
        // durabilir), kutusu hepsinin birleşimi. Her yazı panelin içinde her yanda PanelPadLines boşlukla durmalı; durmuyorsa ya
        // da köşeler yuvarlak değilse (köşeli kutu) örtülür. İkiz özgünün TwinScale katı boyda, sol kenarı özgünle hizalı; önce
        // hemen üstte, yer yoksa altta (arada GapLines); başka yazıya ve karenin dışına taşmaz. Her yazı ikizde kendi yerinde,
        // özgün panelin genişliğine kadar uzayabilir; paneldeki kişi resmi ikizde de gösterilir.
        var keys = panels.Keys.ToList();
        var parent = keys.ToDictionary(i => i, i => i);
        int Root(int i) { while (parent[i] != i) i = parent[i]; return i; }
        foreach (var a in keys)
            foreach (var b in keys.Where(k => k > a))
            {
                var p = panels[a];
                var q = panels[b];
                if (Math.Min(p.R, q.R) > Math.Max(p.L, q.L) && Math.Min(p.B, q.B) > Math.Max(p.T, q.T)) parent[Root(b)] = Root(a);
            }
        foreach (var members in keys.GroupBy(Root).Select(g => g.Order().ToList()).OrderBy(g => g[0]))
        {
            int l = members.Min(m => panels[m].L), t = members.Min(m => panels[m].T);
            int r = members.Max(m => panels[m].R), b = members.Max(m => panels[m].B);
            var padded = members.All(m =>
            {
                var c = covers[m];
                var pad = Math.Max(2, RoundHalfUp(PanelPadLines * lines[m]));
                return c.L - l >= pad && r - c.R >= pad && c.T - t >= pad && b - c.B >= pad;
            });
            var ground = grounds[members[0]];
            if (!padded || CornerRadius(l, t, r, b, (x, y) => Distance(color(x, y), ground) <= PanelTolerance) is not { } corner) continue;
            // Küçük panelde ikizin yazısı okunabilirlik sınırının altına inmez (TV app.js DIALOGUE_MIN_SHARE); gerekirse ikiz
            // özgün boyda.
            var least = members.Select(m => lines[m]).Min();
            var scale = Math.Min(1, Math.Max(TwinScale, TwinMinShare * height / (ScreenFit.ExactFont * least)));
            var h = RoundHalfUp((b - t) * scale);
            var gap = Math.Max(2, (int)Math.Ceiling(ScreenFit.GapLines * lines[members[0]]));
            bool Clear(int y0, int y1)
            {
                if (y0 < 0 || y1 > height) return false;
                for (var j = 0; j < rects.Length; j++)
                    if (!members.Contains(j) && rects[j].L < r && rects[j].R > l && rects[j].T < y1 && rects[j].B > y0) return false;
                return true;
            }
            int top;
            if (Clear(t - gap - h, t - gap)) top = t - gap - h;
            else if (Clear(b + gap, b + gap + h)) top = b + gap;
            else continue;
            double X(int v) => (l + ((v - l) * scale)) / fw;
            double Y(int v) => (top + ((v - t) * scale)) / fh;
            (int L, int T, int R, int B)? face = null;
            foreach (var m in members)
            {
                if (face != null) break;
                face = Portrait(l, t, b, covers[m].L, covers[m].T, covers[m].B, lines[m],
                                (x, y) => !RectHit(x, y, null) && Distance(color(x, y), ground) > 2 * PanelTolerance);
            }
            var inset = Math.Max(gap, members.Min(m => covers[m].L - l));
            foreach (var m in members)
            {
                var c = covers[m];
                var align = targets[m].Align;
                result[m] = result[m] with
                {
                    Mode = PaintMode.Twin,
                    Scale = scale,
                    Tail = corner.Tail,
                    Twin = new TextBox(X(l), Y(t), X(r), Y(b)),
                    Radius = corner.Radius * scale / fh,
                    Spot = new TextBox(X(c.L), Y(c.T), X(c.R), Y(c.B)),
                    SpotRoom = new TextBox(align == "left" ? X(c.L) : X(l + inset), Y(c.T),
                                           Math.Max(X(c.R), (r - RoundHalfUp(inset * scale)) / fw), Y(c.B)),
                    Portrait = face is { } f ? new TextBox(f.L / fw, f.T / fh, f.R / fw, f.B / fh) : null,
                    PortraitTwin = face is { } g ? new TextBox(X(g.L), Y(g.T), X(g.R), Y(g.B)) : null,
                };
            }
        }
        // Çakışma: yanına yazılan Türkçe başka bir hedefin Türkçesine (önceki yanına yazma alanı ya da ikiz panel) binerse
        // örtmeye döner.
        static bool Overlaps(TextBox a, TextBox b) =>
            Math.Min(a.Right, b.Right) > Math.Max(a.Left, b.Left) && Math.Min(a.Bottom, b.Bottom) > Math.Max(a.Top, b.Top);
        for (var i = 0; i < result.Count; i++)
        {
            if (result[i].Mode != PaintMode.Beside || result[i].SpotRoom is not { } mine) continue;
            var hit = false;
            for (var j = 0; j < result.Count && !hit; j++)
            {
                if (j == i) continue;
                if (result[j].Mode == PaintMode.Twin && result[j].Twin is { } twin) hit = Overlaps(mine, twin);
                else hit = j < i && result[j].Mode == PaintMode.Beside && result[j].SpotRoom is { } other && Overlaps(mine, other);
            }
            if (hit) result[i] = result[i] with { Mode = PaintMode.Cover, Spot = null, SpotRoom = null };
        }
        // 4) Grup: aynı sütunda (ortak sol ya da sağ kenar, düzenli aralık) ya da aynı satırda duran, BÜYÜK HARF'i ve satır
        // yüksekliği aynı tek satırlık etiketler.
        foreach (var (members, id) in Groups(targets))
            foreach (var i in members) result[i] = result[i] with { Group = id };
        return result;
    }

    /// <summary>Kare üzerinden ölçüm (BGRA noktalar).</summary>
    public static IReadOnlyList<TextPaint> Paints(IReadOnlyList<Target> targets, Frame frame)
    {
        if (!frame.IsConsistent || frame.Width <= 0 || frame.Height <= 0) return [];
        return Paints(targets, frame.Width, frame.Height, (x, y) =>
        {
            var p = (y * frame.Stride) + (x * 4);
            return (frame.Pixels[p + 2], frame.Pixels[p + 1], frame.Pixels[p]);
        });
    }

    /// <summary>Satır aralığı: çok satırlı yazıda kutudan ((satır sayısı - 1) aralık + bir satır yüksekliği), tek satırda satır yüksekliği.</summary>
    internal static double Pitch(Target target)
    {
        var height = target.Box.Bottom - target.Box.Top;
        if (target.Rows <= 1 || target.LineHeight <= 0) return target.LineHeight > 0 ? target.LineHeight : height;
        return Math.Max(target.LineHeight, (height - target.LineHeight) / (target.Rows - 1));
    }

    /// <summary>Grup üyeleri ve numarası (grubun en küçük sıra numarası); tek üyeli grup yok.</summary>
    internal static List<(List<int> Members, int Id)> Groups(IReadOnlyList<Target> targets)
    {
        var labels = Enumerable.Range(0, targets.Count).Where(i => targets[i].Rows <= 1).ToList();
        var parent = labels.ToDictionary(i => i, i => i);
        int Root(int i) { while (parent[i] != i) i = parent[i]; return i; }
        static double Overlap(TextBox a, TextBox b) =>
            Math.Max(0, Math.Min(a.Bottom, b.Bottom) - Math.Max(a.Top, b.Top)) / Math.Max(1e-9, Math.Min(a.Bottom - a.Top, b.Bottom - b.Top));
        foreach (var a in labels)
            foreach (var b in labels.Where(b => b > a))
            {
                var x = targets[a];
                var y = targets[b];
                var line = Math.Max(x.LineHeight, y.LineHeight);
                if (x.Upper != y.Upper || Math.Abs(x.LineHeight - y.LineHeight) > SameLine * line) continue;
                // Satır yüksekliği kareye oranla; yatay pay aynı piksele denk gelsin diye en-boy oranı bilinmez, yarım satır
                // yüksekliğinin yarısı kadar (16:9'da ~0,28 satır) alınır.
                var tolerance = 0.5 * line * 9 / 16;
                var sameRow = Overlap(x.Box, y.Box) >= 0.5;
                var column = (Math.Abs(x.Box.Left - y.Box.Left) <= tolerance || Math.Abs(x.Box.Right - y.Box.Right) <= tolerance)
                    && Overlap(x.Box, y.Box) == 0 && Math.Abs(x.Box.Top - y.Box.Top) <= 3 * line;
                if (sameRow || column) parent[Root(a)] = Root(b);
            }
        return [.. labels.GroupBy(Root).Where(g => g.Count() >= 2)
            .Select(g => (Members: g.Order().ToList(), Id: g.Min())).OrderBy(g => g.Id)];
    }

    internal static (int R, int G, int B) Rgb(string hex) =>
        DesignTokens.Rgb(hex) is { } c ? (RoundHalfUp(c.R * 255), RoundHalfUp(c.G * 255), RoundHalfUp(c.B * 255)) : (0, 0, 0);

    internal static string Hex((int R, int G, int B) c) =>
        $"#{Math.Clamp(c.R, 0, 255):X2}{Math.Clamp(c.G, 0, 255):X2}{Math.Clamp(c.B, 0, 255):X2}";

    internal static int Distance((int R, int G, int B) a, (int R, int G, int B) b) =>
        Math.Max(Math.Abs(a.R - b.R), Math.Max(Math.Abs(a.G - b.G), Math.Abs(a.B - b.B)));

    internal static (int R, int G, int B) Mean(IReadOnlyList<(int R, int G, int B)> list)
    {
        var n = Math.Max(1, list.Count);
        return (list.Sum(c => c.R) / n, list.Sum(c => c.G) / n, list.Sum(c => c.B) / n);
    }

    /// <summary><paramref name="a"/>'dan <paramref name="b"/>'nin tersine <paramref name="share"/> kadar (eksiyse <paramref name="b"/>'ye doğru) uzatılmış renk.</summary>
    internal static (int R, int G, int B) Extend((int R, int G, int B) a, (int R, int G, int B) b, double share)
    {
        static int One(int x, int y, double share) => RoundHalfUp(x + ((x - y) * share));
        return (One(a.R, b.R, share), One(a.G, b.G, share), One(a.B, b.B, share));
    }

    internal static double Deviation(IReadOnlyList<(int R, int G, int B)> list)
    {
        if (list.Count == 0) return 0;
        static double Spread(IReadOnlyList<int> values)
        {
            var average = (double)values.Sum() / values.Count;
            return Math.Sqrt(values.Sum(v => (v - average) * (v - average)) / values.Count);
        }
        return (Spread([.. list.Select(c => c.R)]) + Spread([.. list.Select(c => c.G)]) + Spread([.. list.Select(c => c.B)])) / 3;
    }
}
