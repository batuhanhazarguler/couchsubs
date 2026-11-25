// SPDX-License-Identifier: AGPL-3.0-only

using System.Windows;
using System.Windows.Controls;
using CouchSubs.App.Theme;

namespace CouchSubs.App.Controls;

/// <summary>
/// İki sütunlu sayfa ızgarası (sütunlar <c>*</c>, <c>{t:Sp l}</c>, <c>*</c>) dar alanda tek sütuna iner: genişliği
/// <c>StackBelow</c>'un altına düşünce sağ sütundaki öğeler sol sütunun altına, araya <c>unitGap</c> (24) konarak taşınır;
/// genişleyince yerlerine döner. Böylece pencere daraltılınca kartlar sağdan kesilmez, sayfa dikey kayar.
/// </summary>
public static class Responsive
{
    /// <summary>İki sütunun sığdığı en küçük genişlik: iki 360'lık sütun ve aradaki 24.</summary>
    public const double TwoColumnMin = 744;

    public static readonly DependencyProperty StackBelowProperty = DependencyProperty.RegisterAttached("StackBelow", typeof(double), typeof(Responsive),
        new PropertyMetadata(0.0, OnStackBelow));

    private static readonly DependencyProperty StackedProperty = DependencyProperty.RegisterAttached("Stacked", typeof(bool), typeof(Responsive),
        new PropertyMetadata(false));

    public static double GetStackBelow(DependencyObject element) => (double)element.GetValue(StackBelowProperty);
    public static void SetStackBelow(DependencyObject element, double value) => element.SetValue(StackBelowProperty, value);

    /// <summary>Izgara şu an tek sütun mu (testler ve yeniden yerleştirme için).</summary>
    public static bool IsStacked(Grid grid) => (bool)grid.GetValue(StackedProperty);

    private static void OnStackBelow(DependencyObject element, DependencyPropertyChangedEventArgs e)
    {
        if (element is not Grid grid) return;
        grid.SizeChanged -= OnSize;
        grid.SizeChanged += OnSize;
    }

    private static void OnSize(object sender, SizeChangedEventArgs e)
    {
        if (sender is Grid grid && e.WidthChanged) Apply(grid, grid.ActualWidth);
    }

    /// <summary>Genişliğe göre iki sütun ya da tek sütun düzenini uygular.</summary>
    public static void Apply(Grid grid, double width)
    {
        if (grid.ColumnDefinitions.Count != 3) return;
        var stack = width > 0 && width < GetStackBelow(grid);
        if (stack == IsStacked(grid)) return;
        grid.SetValue(StackedProperty, stack);
        grid.RowDefinitions.Clear();
        if (stack)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(Sp.V("unitGap")) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.ColumnDefinitions[1].Width = new GridLength(0);
            grid.ColumnDefinitions[2].Width = new GridLength(0);
        }
        else
        {
            grid.ColumnDefinitions[1].Width = new GridLength(Sp.V("l"));
            grid.ColumnDefinitions[2].Width = new GridLength(1, GridUnitType.Star);
        }
        foreach (UIElement child in grid.Children)
        {
            if (stack && Grid.GetColumn(child) == 2)
            {
                Grid.SetColumn(child, 0);
                Grid.SetRow(child, 2);
            }
            else if (!stack && Grid.GetRow(child) == 2)
            {
                Grid.SetRow(child, 0);
                Grid.SetColumn(child, 2);
            }
        }
    }
}
