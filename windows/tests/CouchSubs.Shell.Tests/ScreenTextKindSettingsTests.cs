// SPDX-License-Identifier: AGPL-3.0-only

using System.Text.Json;
using CouchSubs.Core;
using CouchSubs.Shell;

namespace CouchSubs.Shell.Tests;

/// <summary>Otomatik ekran yazısı türlerinin ayarları (Mac/iPhone: ScreenTextKindTests.swift).</summary>
public class ScreenTextKindSettingsTests
{
    private static readonly ScreenTextKind[] All = Enum.GetValues<ScreenTextKind>();

    [Fact]
    public void DefaultsAndOldSettingsGetTheDefaults()
    {
        var fresh = new UserSettings();
        Assert.False(fresh.AutoScreenText); // ana anahtar varsayılan kapalı
        Assert.Equal([true, true, true, false, false],
                     [fresh.ScreenTextPhone, fresh.ScreenTextMission, fresh.ScreenTextHelp, fresh.ScreenTextMenus, fresh.ScreenTextOther]);
        // Eski ayar dosyası: türler yok, otomatik ekran yazısı açık.
        var old = JsonSerializer.Deserialize<UserSettings>("""{"AutoScreenText": true}""")!;
        Assert.True(old.AutoScreenText);
        Assert.Equal([true, true, true, false, false], All.Select(old.ScreenTextAllows));
        // Kayıt ve yeniden okuma türleri korur; hesaplanan alan dosyaya yazılmaz.
        var saved = JsonSerializer.Serialize(old with { ScreenTextMenus = true, ScreenTextPhone = false });
        Assert.DoesNotContain("ReadsGamePhone", saved);
        Assert.DoesNotContain("TranslatesGamePhone", saved);
        Assert.Equal([false, true, true, true, false], All.Select(JsonSerializer.Deserialize<UserSettings>(saved)!.ScreenTextAllows));
    }

    [Fact]
    public void KindsApplyOnlyWhileAutoScreenTextIsOn()
    {
        var settings = new UserSettings { ScreenTextHelp = false };
        Assert.All(All, kind => Assert.True(settings.ScreenTextAllows(kind)));
        settings = settings with { AutoScreenText = true };
        Assert.False(settings.ScreenTextAllows(ScreenTextKind.Help));
        Assert.False(settings.ScreenTextAllows(ScreenTextKind.Menu));
    }

    [Fact]
    public void PhoneIsReadWithItsOwnSettingOrThePhoneKind()
    {
        // Telefonun kendi ayarı varsayılan açık (#1202); kapatılınca Telefon türüne bakılır.
        Assert.True(new UserSettings().ReadsGamePhone);
        var settings = new UserSettings { AutoReadGamePhone = false };
        Assert.False(settings.ReadsGamePhone);
        settings = settings with { AutoScreenText = true };
        Assert.True(settings.ReadsGamePhone);
        settings = settings with { ScreenTextPhone = false };
        Assert.False(settings.ReadsGamePhone);
        Assert.True((settings with { AutoReadGamePhone = true }).ReadsGamePhone);
    }

    /// <summary>
    /// Ayarlardaki tek "GTA 6 Telefonunu Çevir" anahtarı iki eski alanı birlikte yazar; eski dosyada farklı kalan iki alan
    /// telefonun gerçekten okunup okunmadığına göre birleşir (Mac/iPhone mergingGamePhoneSwitches, Android aynı kural).
    /// </summary>
    [Fact]
    public void SinglePhoneSwitchMergesTheTwoOldSwitches()
    {
        var off = new UserSettings() with { TranslatesGamePhone = false };
        Assert.Equal([false, false], [off.AutoReadGamePhone, off.ScreenTextPhone]);
        Assert.False((off with { AutoScreenText = true }).ReadsGamePhone);
        var own = GamePhoneSwitchMerge.Apply(new UserSettings { AutoReadGamePhone = true, ScreenTextPhone = false, AutoScreenText = true });
        Assert.Equal([true, true], [own.AutoReadGamePhone, own.ScreenTextPhone]);
        var kind = GamePhoneSwitchMerge.Apply(new UserSettings { AutoReadGamePhone = false, ScreenTextPhone = true, AutoScreenText = true });
        Assert.Equal([true, true], [kind.AutoReadGamePhone, kind.ScreenTextPhone]);
        var closed = GamePhoneSwitchMerge.Apply(new UserSettings { AutoReadGamePhone = false, ScreenTextPhone = true });
        Assert.Equal([false, false], [closed.AutoReadGamePhone, closed.ScreenTextPhone]);
        Assert.False(closed.ReadsGamePhone);
        var same = new UserSettings();
        Assert.Same(same, GamePhoneSwitchMerge.Apply(same));
    }
}
