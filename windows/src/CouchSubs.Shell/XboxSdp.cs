// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Shell;

/// <summary>
/// SDP'deki görüntü kodekleri (#1252): teklif edilenler ve Xbox'ın yanıtta seçtiği günlüğe yazılır, tanı satırının
/// "kodek" alanı ilk kare gelmeden de dolar (getStats kodeği ilk kareye kadar boştur). Android'deki XboxSdp
/// (XboxCodecs.kt) ve iPhone/Mac'teki XboxSdp (CouchSubsCore) ile aynı biçim.
/// </summary>
public static class XboxSdp
{
    private static readonly HashSet<string> Skipped = new(StringComparer.OrdinalIgnoreCase) { "rtx", "red", "ulpfec", "flexfec-03" };

    /// <summary><c>m=video</c> bölümündeki kodekler m= satırındaki sırayla: "H264 640c1f", "VP8". Bölüm yoksa ya da reddedildiyse boş.</summary>
    public static IReadOnlyList<string> VideoCodecs(string? sdp)
    {
        if (string.IsNullOrEmpty(sdp)) return [];
        var lines = sdp.Split('\n').Select(l => l.TrimEnd('\r')).ToList();
        var start = lines.FindIndex(l => l.StartsWith("m=video ", StringComparison.Ordinal));
        if (start < 0) return [];
        var media = lines[start].Split(' ');
        if (media.Length > 1 && media[1] == "0") return [];
        var names = new Dictionary<string, string>();
        var formats = new Dictionary<string, string>();
        foreach (var line in lines.Skip(start + 1).TakeWhile(l => !l.StartsWith("m=", StringComparison.Ordinal)))
        {
            if (line.StartsWith("a=rtpmap:", StringComparison.Ordinal))
            {
                var parts = line["a=rtpmap:".Length..].Split(' ', 2);
                if (parts.Length == 2) names[parts[0]] = parts[1].Split('/')[0];
            }
            else if (line.StartsWith("a=fmtp:", StringComparison.Ordinal))
            {
                var parts = line["a=fmtp:".Length..].Split(' ', 2);
                formats[parts[0]] = parts.Length == 2 ? parts[1] : "";
            }
        }
        var result = new List<string>();
        foreach (var type in media.Skip(3))
        {
            if (!names.TryGetValue(type, out var name) || Skipped.Contains(name)) continue;
            var profile = formats.TryGetValue(type, out var fmtp)
                ? fmtp.Split(';').Select(p => p.Trim()).FirstOrDefault(p => p.StartsWith("profile-level-id=", StringComparison.OrdinalIgnoreCase))
                : null;
            var entry = name.Equals("H264", StringComparison.OrdinalIgnoreCase) && profile is not null
                ? $"{name} {profile["profile-level-id=".Length..].ToLowerInvariant()}"
                : name;
            if (!result.Contains(entry)) result.Add(entry);
        }
        return result;
    }

    /// <summary>Xbox'ın yanıtta seçtiği görüntü kodeği (ilk kodek); yoksa null.</summary>
    public static string? Negotiated(string? answer) => VideoCodecs(answer).FirstOrDefault();

    /// <summary>"SDP görüntü kodekleri: teklif H264 640c1f, H264 42e01f, VP8; Xbox yanıtı H264 640c1f"</summary>
    public static string Summary(string? offer, string? answer)
    {
        var offered = VideoCodecs(offer);
        var chosen = VideoCodecs(answer);
        return $"SDP görüntü kodekleri: teklif {(offered.Count == 0 ? "yok" : string.Join(", ", offered))}; " +
            $"Xbox yanıtı {(chosen.Count == 0 ? "görüntü yok" : string.Join(", ", chosen))}";
    }
}
