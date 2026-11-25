// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core.LgTv;

/// <summary>sdb <c>0 was_execute</c> yanıtının anlamı (TvInstall SamsungAppLaunch; Mac/iPhone SamsungSdbOpen, Android SdbOpen).</summary>
public enum SamsungSdbOpen
{
    /// <summary>Açılamadı: geliştirici modu kapalı, Host PC IP başka cihaz, TV "launch failed" dedi ya da yanıt anlaşılmadı.</summary>
    Failed,
    /// <summary>Uygulama kapalıydı, yeni açıldı ("app_id[…] launched").</summary>
    Launched,
    /// <summary>Uygulama zaten çalışıyordu, yalnız öne geldi ("app_id[…] resumed"); sayfa yeniden yüklenmez.</summary>
    Resumed,
}

/// <summary>
/// Bekçinin Samsung'da TV uygulamasını açma yolu: önce geliştirici bağlantısı (sdb, <c>was_execute</c>), olmazsa uzaktan
/// kumanda bağlantısı (8002, ilk bağlantıda TV izin sorar). Samsung önplandaki uygulamayı söylemez; bekçi yalnız açar.
/// <para>
/// #1248 (beta.95, Samsung 2020): bilgisayar altyazı akışını "alındı gelmedi" diye kapattıktan sonra TV uygulaması hâlâ
/// çalışıyordu; <c>was_execute</c> her seferinde "resumed" diyordu (uygulama yalnız öne geliyor, sayfa yeniden yüklenmiyor
/// ve akışa bağlanmıyordu). "resumed" başarısız sayıldığı için bekçi 8002 yoluna düşüyor, TV "Samsung sunucusuna
/// bağlanılamıyor (AS400)" diyordu; düzelmesi için TV'yi fişten çekmek gerekiyordu. Artık "resumed" uygulamanın çalıştığı
/// sayılır, 8002'ye geçilmez: sayfaya kendisi yeniden bağlanması için <see cref="ResumeWait"/> kadar süre tanınır (TV
/// uygulaması 0.9.104'ten beri öne gelince akışı yeniden kurar), bağlanmazsa uygulama sdb ile kapatılıp yeniden açılır
/// (sayfa temiz yüklenir). Mac, iPhone ve Android ile aynı.
/// </para>
/// </summary>
/// <param name="openWithSdb">sdb ile açar; argüman true ise önce kapatır (<c>was_kill</c>).</param>
/// <param name="appConnected">TV uygulaması bilgisayara bağlı mı (altyazı akışı açık).</param>
public sealed class SamsungLauncher(Func<bool, Task<SamsungSdbOpen>> openWithSdb, Func<bool> appConnected,
                                    Func<Task<ITvControl>> connectRemote, TimeSpan? resumeWait = null, TimeSpan? poll = null,
                                    Action<string>? log = null) : ITvControl
{
    /// <summary>"resumed"dan sonra TV uygulamasının kendiliğinden bağlanması için beklenen süre.</summary>
    public static readonly TimeSpan ResumeWait = TimeSpan.FromSeconds(10);

    private readonly TimeSpan wait = resumeWait ?? ResumeWait;
    private readonly TimeSpan every = poll ?? TimeSpan.FromMilliseconds(500);
    private readonly Action<string> write = log ?? SubtitleLog.Write;

    public async Task LaunchAsync(string appId, IReadOnlyDictionary<string, string> parameters, CancellationToken cancellationToken = default)
    {
        switch (await openWithSdb(false))
        {
            case SamsungSdbOpen.Launched:
                return;
            case SamsungSdbOpen.Resumed:
                if (await WaitForConnectionAsync(cancellationToken)) return;
                write($"Samsung: TV uygulaması çalışıyordu (resumed) ama {wait.TotalSeconds:0} sn'de bağlanmadı; kapatılıp yeniden açılıyor");
                var restarted = await openWithSdb(true);
                if (restarted != SamsungSdbOpen.Launched)
                    write($"Samsung: TV uygulaması kapatılıp açılamadı ({restarted.ToString().ToLowerInvariant()}); uzaktan kumanda yolu denenmiyor, bekçi yeniden dener");
                return;
            default:
                using (var remote = await connectRemote())
                    await remote.LaunchAsync(appId, parameters, cancellationToken);
                return;
        }
    }

    /// <summary>TV uygulaması <see cref="ResumeWait"/> içinde bağlandıysa true.</summary>
    private async Task<bool> WaitForConnectionAsync(CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + wait;
        while (DateTime.UtcNow < deadline)
        {
            if (appConnected()) return true;
            await Task.Delay(every, cancellationToken);
        }
        return appConnected();
    }

    public Task<string> ForegroundAppIdAsync(CancellationToken cancellationToken = default) => Task.FromResult("");

    public void Dispose() { }
}
