// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;
using Xunit;

namespace CouchSubs.Core.Tests;

/// <summary>
/// Çeviri kutusu tuş simgesinin (△ ○ ✕ □, R2, L1) üstüne binmez (#1203; Mac IconGuardTests.swift, Android IconGuardTest.kt).
/// Okunmuş simge ("A Turn Off", "[] Map") ipucu sayılır; uzun çeviri yana genişlemez, kenar payı alanın dışına çıkmaz.
/// </summary>
public class IconGuardTests
{
    [Theory]
    [InlineData("A Turn Off", true)]
    [InlineData("[] Map", true)]
    [InlineData("() Back", true)]
    [InlineData("Δ Pick Up", true)]
    [InlineData("Turn Off △", true)]
    [InlineData("A little help here", false)]
    [InlineData("A Turn Off.", false)]
    [InlineData("A man walks into a bar", false)]
    [InlineData("A", false)]
    [InlineData("A LIBERTY CITY MEMOIR", false)]
    public void ReadIconAtTheStartIsAPrompt(string line, bool prompt) => Assert.Equal(prompt, ButtonPrompts.IsPrompt(line));

    [Theory]
    [InlineData("YÜKLEME DONANIMI", 1)]
    [InlineData("NİŞAN AL / ETKİLEŞİME GEÇ", 1)]
    [InlineData("Sahil güvenlik gelmeden marinada buluş", 2)]
    public void LongTranslationNeverWidens(string text, int rows)
    {
        static double Measure(string s) => s.Length * 10.0;
        var fit = ScreenFit.Layout(text, 70, rows, Measure);
        Assert.True(fit.Rows.Max(Measure) * fit.Scale * fit.Squeeze <= 70.01, text);
        Assert.True(fit.Scale >= ScreenFit.LastScale, text);
    }

    [Fact]
    public void PadsStayInsideTheRoom()
    {
        var pads = ScreenFit.Pads(100, 70, (100, 172), 6);
        Assert.Equal(0, pads.Left);
        Assert.Equal(2, pads.Right, 6);
    }
}
