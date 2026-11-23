# Ekran yazısı: sil ve yeniden çiz (tasarım notu)

Amaç: "Ekranı çevir" ve otomatik ekran yazısında çeviri, özgün yazının birebir yerinde, boyunda ve stilinde görünsün;
simge, fotoğraf ve zemin hiç örtülmesin. Her oyunda aynı genel yöntem çalışır; oyuna özel şablon yazılmaz.

## Bugünkü durum (main)

- Çekirdek (`ScreenFit`, üç platform): kutu yalnız yazıyı kapsar, genişleme alanı simgeye/komşuya kadar (`room`), sütun ve
  şerit hizası, eş öğeler aynı boyda, özgün satır sayısı (`rows`).
- TV (`fitStyled`, TV uygulaması 0.9.85): özgün zemin rengindeki sıkı kutu, yazı boyu sabit, yatay sıkıştırma.
- Önbellekteki/bilinen yazılar çeviri isteğini beklemeden çizilir.

Kutu yaklaşımı düz zeminde iyi görünür ama degrade/doku üstünde kutu belli olur; yazı tipi TV'nin yazı tipidir.

## Ana yol: sil ve yeniden çiz

1. **Yazı maskesi** — yazı kutusunda (ScreenFit'in daralttığı, yalnız yazıyı kapsayan kutu) zemin kestiriminden belirgin
   ayrılan noktalar (en büyük renk bileşeni farkı > 48), harfin yumuşak kenarı ve dış çizgisi için 1-2 nokta
   genişletilir. Zemin kestirimi: her satırda kutunun sol ve sağ şeridinin ortalaması, aralarında doğrusal (yatay
   degrade). Kutu yatayda genişletilmez: hemen yandaki simge ve fotoğraf maskeye hiç girmez (tasarım gereği).
2. **Silme** — maskeli noktalar satır yönünde, iki yanındaki maskesiz noktalar arasında doğrusal doldurulur (düz ve
   degrade UI zemininde temiz). Kutunun üst/alt şeridi kestirime uzaksa (doku > 14) zemin dokuludur (3B dünya, video):
   temiz silinemez, güvenli dönüş özgün stilde sıkı kutudur. Sonraki adım: dokulu zemin için yama tabanlı doldurma
   (Telea benzeri, kendi kodumuz).
3. **Stil çıkarımı** — harfin içi (dört komşusu da harf) yazı rengi, kenarı belirgin farklıysa dış çizgi; boy satır
   yüksekliğinden, kalınlık mürekkep oranından (`TextStyleSampler`), hiza ScreenFit'ten. Sonraki adım: dar/geniş, serif
   ve gölge ölçümüyle küçük bir yazı ailesi setinden en yakınını seçmek; oyun başına öğrenip saklamak.
4. **Yeniden çizim** — Türkçe metin aynı taban çizgisinde, aynı boyda; özgün yazı kaç satırsa o kadar satıra bölünür;
   sığmayan satır yalnız yatayda sıkıştırılır (en çok %30). Küçültme yok; uzunluk bütçesiyle kısa çeviri sonraki adım.
5. **Dağıtım** — çizimi bilgisayar/telefon yapar; TV'ye yalnız değişen bölgelerin hazır yamaları (koordinatlı PNG/WebP)
   gider, TV yalnız yerine koyar: dört platform ve TV birebir aynı görünür. Ölçülecek: yama boyu ve gecikme.
6. **Anlık** — ekran düzeni özeti (kutuların yeri + metin izi) → hazır yama önbelleği: aynı menü tekrar açılınca yamalar
   hesaplanmadan basılır. Çeviri belleği oyunlar arası genel; sunucu havuzunda yalnız İngilizce arayüz metni paylaşılabilir.

## Prototip ölçümü (Mac çekirdeği, `TextErase`, `TextEraseTests`)

Kayıtlı okumalarla, yazı tanıma koşmadan; Release derlemesi, M serisi Mac:

| Küme | Yazı | Temiz silinen (düz/degrade zemin) | Kalan harf noktası (ortanca) |
|---|---|---|---|
| GTA 6 menü/görev ("Ekranı çevir" öğeleri) | 32 | 28 | 0,000 (en çok 0,151) |
| GTA 6 altyazı satırları | 124 | 63 | 0,000 |
| Red Dead Redemption 2 altyazı | 10 | 9 | 0,000 |
| Elden Ring altyazı | 4 | 4 | 0,000 |
| Assassin's Creed Shadows altyazı | 10 | 7 | 0,000 |
| Ghost of Yōtei altyazı | 3 | 0 | 0,000 |

- Simge ve fotoğraf alanları (frames.json → screen.clear): silme ve çizimden sonra değişen nokta **0**.
- Silme süresi: yazı başına ~4 ms (1080p kare).
- "Kalan harf noktası", silmeden sonra kutuda zemin kestiriminden hâlâ ayrılan noktaların silmeden öncekilere oranıdır;
  dokulu zeminde (temiz değil) kutuya dönülür.

Açık kalanlar: dış çizgili yazının (GTA 6 harita tuş etiketleri) dolgu/çizgi rengi ayrımı yanlış olabiliyor; dokulu zemin
için yama tabanlı doldurma; yazı ailesi seçimi; yamaların TV'ye gönderilmesi ve Windows/Android'e taşınması; GTA 6 dışındaki
oyunların menü/görev karelerinin kayıtlı okuması (şimdilik yalnız altyazı satırlarıyla ölçüldü).
