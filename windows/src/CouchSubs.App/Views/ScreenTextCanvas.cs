// SPDX-License-Identifier: AGPL-3.0-only

using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CouchSubs.Core;

namespace CouchSubs.App.Views;

/// <summary>
/// Ekran yazısı blokları oyun karesindeki kendi yerlerinde (yayın penceresi 16:9 karenin kendisidir), TV ve Mac ile aynı
/// yerleşimle (<see cref="ScreenFit.Layout"/>; Mac StreamWindow ScreenTextBlocks): yazı boyu satır yüksekliğinin 0,95'i; kutu
/// özgün yazının genişliğinde kalır, yana hiç genişlemez. Türkçe uzunsa önce yatayda biraz sıkışır, sonra küçülür, sonra satır
/// kırılıp kutu aşağı uzar; kenar payı yalnız bilgisayarın verdiği alanda (<c>Room</c>), yandaki tuş simgesine binmez. Altyazıyla çakışan kutu yalnız gerektiği
/// kadar yukarı ya da aşağı kayar. Önceden Windows'ta bu çeviriler pencerenin üstünde alt alta, hizalı bir liste olarak
/// çiziliyordu.
/// <para>
/// Kareden ölçülmüş öğe (<see cref="ScreenTranslation.Item.Paint"/>) yerinde birebir çizilir (<see cref="ScreenFit.Exact"/>;
/// TV fitExact ve Mac ScreenTextBlocks ile aynı yerleşim): opak, köşesiz, gölgesiz kutu tam örtü sınırında, ölçülen zeminle
/// (düz ya da yatay/dikey degrade), yazı özgün renk, kalınlık ve hizayla; her satır özgün satır aralığında. Ölçüsü olmayan
/// öğe eski yoldan çizilir.
/// </para>
/// </summary>
internal sealed class ScreenTextCanvas : Canvas
{
    private static readonly FontFamily Condensed = new("Arial Narrow, Segoe UI");
    private static readonly FontFamily Normal = new("Segoe UI");
    private static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    private IReadOnlyList<ScreenTranslation.Item> items = [];
    private Rect? avoiding;

    public ScreenTextCanvas()
    {
        IsHitTestVisible = false;
        ClipToBounds = true;
        SizeChanged += (_, _) => Layout();
    }

    /// <summary>Kendi yerinde çizilecek öğe: özgün stilli, telefon kartının/panelinin parçası değil.</summary>
    public static bool Draws(ScreenTranslation.Item item) =>
        item.Look is not null && item.Panel is null && !ScreenPhoneCard.IsBackdrop(item) && item.Translation.Length > 0;

    /// <param name="subtitles">Altyazı satırlarının yeri (bu katmanın koordinatında); kutu onunla çakışmaz.</param>
    public void Show(IReadOnlyList<ScreenTranslation.Item> blocks, Rect? subtitles)
    {
        items = blocks;
        avoiding = subtitles;
        Layout();
    }

    /// <summary>Kutunun üst kenarı (Mac ScreenTextBlocks.top ile aynı kural, en az %0,6 ekran yüksekliği boşluk).</summary>
    internal static double Top(Rect rect, Rect? avoiding, double height)
    {
        var gap = height * 0.006;
        if (avoiding is not { } other) return rect.Top;
        var grown = new Rect(other.X, other.Y - gap, other.Width, other.Height + (2 * gap));
        if (!rect.IntersectsWith(grown)) return rect.Top;
        var up = other.Top - gap - rect.Height;
        var down = other.Bottom + gap;
        bool upFits = up >= 0, downFits = down + rect.Height <= height;
        if (upFits && (!downFits || rect.Top - up <= down - rect.Top)) return up;
        if (downFits) return down;
        return Math.Max(0, up);
    }

    private void Layout()
    {
        Children.Clear();
        double width = ActualWidth, height = ActualHeight;
        if (width <= 0 || height <= 0) return;
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var drawn = items.Where(Draws).ToList();
        LayoutExact([.. drawn.Where(item => item.Paint is not null)], width, height, dpi);
        foreach (var item in drawn.Where(item => item.Paint is null))
        {
            var look = item.Look!;
            var surface = item.Style ?? TextStyleSampler.Neutral;
            var line = Math.Max(1, item.LineHeight * height);
            var baseSize = line * 0.95;
            var pad = line * 0.15;
            var boxHeight = Math.Max(0, item.Box.Bottom - item.Box.Top) * height;
            var family = look.Condensed ? Condensed : Normal;
            var weight = look.Bold ? FontWeights.Bold : FontWeights.SemiBold;
            var typeface = new Typeface(family, FontStyles.Normal, weight, FontStretches.Normal);
            var translation = look.Upper ? item.Translation.ToUpper(Turkish) : item.Translation;
            double Measure(string text) =>
                new FormattedText(text, Turkish, FlowDirection.LeftToRight, typeface, baseSize, Brushes.White, dpi).WidthIncludingTrailingWhitespace;
            double left = item.Box.Left * width, boxWidth = Math.Max(1, item.Box.Right - item.Box.Left) * width;
            var fit = ScreenFit.Layout(translation, boxWidth, item.Rows, Measure, ScreenFit.Floor(baseSize, height));
            var fontSize = baseSize * fit.Scale;
            // Kenar payı yalnız bilgisayarın verdiği alanda: yandaki tuş simgesinin üstüne binmez (#1203).
            var side = ScreenFit.Pads(left, boxWidth, item.Room is { } room ? (room.Left * width, room.Right * width) : null, pad);
            var pitch = Math.Max(boxHeight / Math.Max(1, fit.Rows.Count), fontSize * 1.05);
            var alignment = look.Align switch { "center" => HorizontalAlignment.Center, "right" => HorizontalAlignment.Right, _ => HorizontalAlignment.Left };
            var origin = look.Align switch { "center" => 0.5, "right" => 1.0, _ => 0.0 };
            var stack = new StackPanel { Width = boxWidth, MinHeight = boxHeight, VerticalAlignment = VerticalAlignment.Center };
            foreach (var text in fit.Rows)
            {
                stack.Children.Add(new TextBlock
                {
                    Text = text,
                    FontFamily = family,
                    FontWeight = weight,
                    FontSize = fontSize,
                    Foreground = new SolidColorBrush(Parse(surface.Foreground, Colors.White)),
                    TextWrapping = TextWrapping.NoWrap,
                    Height = pitch,
                    HorizontalAlignment = alignment,
                    RenderTransformOrigin = new Point(origin, 0.5),
                    RenderTransform = new ScaleTransform(fit.Squeeze, 1),
                });
            }
            var block = new Border
            {
                Background = new SolidColorBrush(Parse(surface.Background, Colors.Black)),
                CornerRadius = new CornerRadius(look.Flat ? 0 : pad),
                Padding = new Thickness(side.Left, pad, side.Right, pad),
                Child = stack,
            };
            var rect = new Rect(left - side.Left, (item.Box.Top * height) - pad, boxWidth + side.Left + side.Right, boxHeight + (2 * pad));
            SetLeft(block, left - side.Left);
            SetTop(block, Top(rect, avoiding, height));
            Children.Add(block);
        }
    }

    /// <summary>
    /// Yerinde birebir çizim: bütün ölçülü öğeler birlikte yerleşir (grup aynı yazı boyunda), ölçü bu katmanın kendi yazı
    /// tipiyle alınır.
    /// </summary>
    private void LayoutExact(IReadOnlyList<ScreenTranslation.Item> painted, double width, double height, double dpi)
    {
        if (painted.Count == 0) return;
        var typefaces = painted.Select(item => new Typeface(item.Look!.Condensed ? Condensed : Normal, FontStyles.Normal,
            item.Look.Bold ? FontWeights.Bold : FontWeights.Normal, FontStretches.Normal)).ToList();
        var texts = painted.Select(item => item.Look!.Upper ? item.Translation.ToUpper(Turkish) : item.Translation).ToList();
        var inputs = painted.Select((item, i) => ScreenFit.ExactInput.From(item, width, height)! with { Text = texts[i] }).ToList();
        // Her öğe kendi yazı tipiyle ölçülür. Grup aynı boyda kalsın diye bütün öğeler birlikte yerleşir; her yazı tipi
        // (dar/normal, kalın/normal) için bir kez, o yazı tipindeki öğelerin sonucu alınır.
        var placements = new ScreenFit.ExactPlacement[painted.Count];
        foreach (var kind in Enumerable.Range(0, painted.Count).GroupBy(i => (typefaces[i].FontFamily, typefaces[i].Weight)))
        {
            var typeface = typefaces[kind.First()];
            double Measure(string text, double size) =>
                new FormattedText(text, Turkish, FlowDirection.LeftToRight, typeface, Math.Max(0.1, size), Brushes.White, dpi)
                    .WidthIncludingTrailingWhitespace;
            var laid = ScreenFit.Exact(inputs, Measure);
            foreach (var i in kind) placements[i] = laid[i];
        }
        for (var i = 0; i < painted.Count; i++)
        {
            var item = painted[i];
            var paint = item.Paint!;
            var place = placements[i];
            var look = item.Look!;
            var foreground = new SolidColorBrush(Parse(item.Style?.Foreground, Colors.White));
            var box = new Border
            {
                Width = Math.Max(1, place.Width),
                Height = Math.Max(1, place.Height),
                Background = Ground(paint),
                CornerRadius = new CornerRadius(0),
            };
            SetLeft(box, place.Left);
            SetTop(box, place.Top);
            Children.Add(box);
            var alignment = look.Align switch { "center" => HorizontalAlignment.Center, "right" => HorizontalAlignment.Right, _ => HorizontalAlignment.Left };
            for (var k = 0; k < place.Lines.Count; k++)
            {
                // Satır, özgün satırın yerinde: RowHeight yüksekliğin dikey ortasında, k. satır Top + k * LineHeight'ta.
                var row = new Border
                {
                    Width = Math.Max(1, place.Width),
                    Height = Math.Max(1, place.RowHeight),
                    Child = new TextBlock
                    {
                        Text = place.Lines[k],
                        FontFamily = typefaces[i].FontFamily,
                        FontWeight = typefaces[i].Weight,
                        FontSize = Math.Max(0.1, place.FontSize),
                        Foreground = foreground,
                        TextWrapping = TextWrapping.NoWrap,
                        HorizontalAlignment = alignment,
                        VerticalAlignment = VerticalAlignment.Center,
                    },
                };
                SetLeft(row, place.Left);
                SetTop(row, place.Top + (k * place.LineHeight));
                Children.Add(row);
            }
        }
    }

    /// <summary>Ölçülen zemin: düz renk ya da iki uçlu doğrusal degrade (yatay: soldan sağa, dikey: üstten alta).</summary>
    private static Brush Ground(TextPaint paint)
    {
        var start = Parse(paint.Background, Colors.Black);
        if (paint.Background2 is not { } second || paint.Direction is not { } direction) return new SolidColorBrush(start);
        var end = Parse(second, start);
        return direction == TextPaint.Vertical
            ? new LinearGradientBrush(start, end, new Point(0.5, 0), new Point(0.5, 1))
            : new LinearGradientBrush(start, end, new Point(0, 0.5), new Point(1, 0.5));
    }

    private static Color Parse(string? hex, Color fallback) =>
        hex is { Length: 7 } && hex[0] == '#'
        && int.TryParse(hex.AsSpan(1), NumberStyles.HexNumber, null, out var rgb)
            ? Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb)
            : fallback;
}
