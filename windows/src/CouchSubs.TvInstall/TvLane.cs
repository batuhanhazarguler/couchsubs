// SPDX-License-Identifier: AGPL-3.0-only

using System.Collections.Concurrent;
using System.Collections.Immutable;

namespace CouchSubs.TvInstall;

/// <summary>
/// TV adresi başına tek kanal: aynı TV'ye giden geliştirici bağlantıları (Samsung sdb, Android TV ADB) sırayla çalışır.
/// Mac/iPhone'daki TVLane ve Android telefondaki TvLane ile aynı kural.
/// </summary>
/// <remarks>
/// #1223 (Windows beta.93, Samsung): çeviri başlarken bekçinin açma denemesi (sdb <c>was_execute</c>) ile sürüm denetimi /
/// kurulum aynı saniyede aynı TV'ye ayrı sdb oturumları açıyordu; TV bağlantıyı zorla kapatıyor ("Varolan bir bağlantı
/// uzaktaki bir ana bilgisayar tarafından zorla kapatıldı"), kurulum "TV bu bilgisayarı kabul etmedi" diye bitiyordu.
/// "Güncelle"ye arka arkaya basılınca da aynı TV'ye birden çok kurulum başlıyordu. Artık:
/// <list type="bullet">
/// <item>Aynı TV'deki işlemler sırayla çalışır; kurulum sürerken bekçinin açma denemesi kurulumun bitmesini bekler.
/// Takılan bir işlem kanalı sonsuza dek tutmasın diye en çok <see cref="DefaultMaxWait"/> beklenir, sonra eski davranışla
/// (beklemeden) sürülür ve günlüğe yazılır.</item>
/// <item>Aynı TV için kurulum sürerken gelen ikinci kurulum isteği yeni kurulum başlatmaz; sürenin sonucunu bekler.</item>
/// </list>
/// Aynı akışta iç içe çağrı (kanalı tutan işlemin aynı TV'ye yeniden girmesi) beklemeden çalışır.
/// </remarks>
public sealed class TvLane(TimeSpan? maxWait = null)
{
    /// <summary>Kanalı tutan işlem en çok bu kadar beklenir (kurulumun her adımının ayrıca süre sınırı var, bkz. <see cref="TvStall"/>).</summary>
    public static readonly TimeSpan DefaultMaxWait = TimeSpan.FromMinutes(5);

    /// <summary>Uygulamanın ortak kanalı (Windows uygulaması ve Mac'in yardımcısı).</summary>
    public static TvLane Shared { get; } = new();

    private readonly TimeSpan wait = maxWait ?? DefaultMaxWait;
    private readonly ConcurrentDictionary<string, SemaphoreSlim> gates = new();
    private readonly ConcurrentDictionary<string, Task> installs = new();
    /// <summary>Bu akışın tuttuğu kanallar (iç içe çağrı beklemesin).</summary>
    private readonly AsyncLocal<ImmutableHashSet<string>?> held = new();

    /// <summary>Kanalın anahtarı: adres, boşluksuz ve küçük harfle.</summary>
    public static string Key(string host) => host.Trim().ToLowerInvariant();

    /// <summary>Bu TV'de şu an bir işlem sürüyor mu.</summary>
    public bool IsBusy(string host) => gates.TryGetValue(Key(host), out var gate) && gate.CurrentCount == 0;

    /// <summary>Bu TV'de şu an kurulum sürüyor mu.</summary>
    public bool IsInstalling(string host) => installs.ContainsKey(Key(host));

    /// <summary><paramref name="work"/>'ü bu TV'nin kanalında çalıştırır: aynı TV'deki başka işlem bitene kadar bekler.</summary>
    /// <param name="what">Günlükte işlemin adı ("açma", "kurulum").</param>
    public async Task<T> RunAsync<T>(string host, string what, Func<Task<T>> work, Action<string>? log = null,
        CancellationToken cancellationToken = default)
    {
        var key = Key(host);
        var before = held.Value;
        if (key.Length == 0 || before?.Contains(key) == true) return await work();
        var gate = gates.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
        var entered = gate.Wait(0, CancellationToken.None);
        if (!entered)
        {
            log?.Invoke($"TV {host}: aynı TV'de başka bir işlem sürüyor; {what} sırasını bekliyor (aynı anda iki bağlantıyı TV kapatıyor)");
            entered = await gate.WaitAsync(wait, cancellationToken);
            if (!entered)
                log?.Invoke($"TV {host}: önceki işlem {wait.TotalMinutes:0.#} dk'da bitmedi; {what} beklemeden başlıyor");
        }
        held.Value = (before ?? []).Add(key);
        try
        {
            return await work();
        }
        finally
        {
            held.Value = before;
            if (entered) gate.Release();
        }
    }

    public Task RunAsync(string host, string what, Func<Task> work, Action<string>? log = null,
        CancellationToken cancellationToken = default) =>
        RunAsync<object?>(host, what, async () => { await work(); return null; }, log, cancellationToken);

    /// <summary>
    /// Kurulumu bu TV'nin kanalında çalıştırır. Aynı TV'de kurulum zaten sürüyorsa yenisi başlatılmaz: sürenin sonucu
    /// (ya da hatası) döner.
    /// </summary>
    public async Task<T> InstallAsync<T>(string host, Func<Task<T>> work, Action<string>? log = null,
        CancellationToken cancellationToken = default)
    {
        var key = Key(host);
        if (key.Length == 0 || held.Value?.Contains(key) == true) return await work();
        while (true)
        {
            if (installs.TryGetValue(key, out var running))
            {
                if (running is Task<T> same)
                {
                    log?.Invoke($"TV {host}: kurulum zaten sürüyor; yeni kurulum başlatılmadı, sürenin bitmesi bekleniyor");
                    return await same.WaitAsync(cancellationToken);
                }
                // Başka türden kurulum (olmamalı): kanalda sırasını bekler.
                return await RunAsync(host, "kurulum", work, log, cancellationToken);
            }
            var mine = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            if (!installs.TryAdd(key, mine.Task)) continue;
            try
            {
                var result = await RunAsync(host, "kurulum", work, log, cancellationToken);
                mine.SetResult(result);
                return result;
            }
            catch (OperationCanceledException error)
            {
                mine.SetCanceled(error.CancellationToken);
                throw;
            }
            catch (Exception error)
            {
                mine.SetException(error);
                // Bekleyen yoksa hata gözlenmemiş kalmasın.
                _ = mine.Task.Exception;
                throw;
            }
            finally
            {
                installs.TryRemove(new KeyValuePair<string, Task>(key, mine.Task));
            }
        }
    }
}
