# Ekran çapası: telefona yapışık çeviri

Hedef (Sinan Bey): GTA 6'nın oyun içi telefonunda her mesajın çevirisi kendi balonunun yerinde, telefonun ekranının
üstünde; telefon el titremesiyle ya da karakter yürürken kıpırdadıkça çeviri telefona yapışık, titremeden onunla gider.
Aynısı görev kartı, harita kartı ve menü kutuları için.

## Sorun

Telefonun yeri yalnız OCR turunda (`GamePhoneTracker`, 330 ms'de bir) 400×225'lik kaba ızgarada bulunuyordu; balonların
kutuları da OCR'dan geliyordu. Aradaki karelerde telefon kıpırdasa da çeviri yerinde kalıyor, kayma eşiği
(`PhoneSteady.positionShare`, satır yüksekliğinin %25'i) aşılınca birden sıçrıyordu. Yazı boyu ve satır kırılımı her
okumada yeniden hesaplandığı için çeviri ayrıca büyüyüp küçülüyordu (#1154 paneli kilitledi, balonlar açıkta kaldı).

## Yöntem (`ScreenAnchor`, dört platform aynı)

1. **Başvuru**: OCR'ın telefonu (ya da kartı) bulduğu karede dörtgenin görüntüsü şablon olur (izleme karesi 960 piksel
   genişlik; kenardan %3 içeride, ≤2500 nokta/kat, en çok 4 katlı piramit).
2. **Her kare**: şablonun izdüşümsel dönüşümü (öteleme, ölçek, dönme, elde eğilen telefonun perspektifi; 8 değişken)
   ters bileşimli Lucas-Kanade ile bulunur. En kaba katta üç başlangıç denenir: önceki dönüşüm, sabit hızla öngörülen ve
   onun çevresinde ±3 piksellik (izleme karesinde ±24) tam piksel tarama; arabada sarsılan telefon karede 15–20 piksel
   gidebiliyor. Ağırlık sağlamdır: farkı 8 gri düzeye kadar tam, 24'e kadar azalan, ötesi sıfır (ekranda değişen yazı,
   önden geçen el izlemeyi çekmez). Parlaklık/karşıtlık her yinelemede eşitlenir (pozlama değişimi, ekran kararması).
3. **Şablon hiç güncellenmez**: değişen parçayı yeniden örneklemek denendi, eğimli kenarlardaki küçük kayma şablona
   işlenip birikti (yapay vakada 0,16 → 0,38 piksel); güncellemesiz hata 0,14'te sabit kaldı.
4. **Kayıp**: uyumlu nokta oranı %45'in altına inerse ya da dönüşüm akla yatkın değilse (ölçek 0,5–2 dışı, eksen oranı
   0,75–1,33 dışı, köşelerde %15'ten çok perspektif) çapa kaybolur; bir sonraki okumada yeniden kurulur. Telefon
   indirilirken izleyicinin bulanık kareye yapışıp telefonu "uzatması" böyle engellenir.
5. **Kararlılık** (`ScreenAnchor.Smoother`): dörtgenin hiçbir köşesi son gösterilenden 0,15 pikselden fazla oynamadıysa
   son gösterilen kalır (duran telefonda çeviri piksel piksel sabit), oynadıysa ham ölçüm gecikmesiz gösterilir; köşe
   bir karede dörtgen yüksekliğinin %12'sinden fazla sıçrarsa `jumped` (çapa yeniden kurulmalı). İstenen "2–3 karelik
   gecikmesiz kestirim" (son üç ölçümden geçen doğru) ölçüldü ve **alınmadı**: arabada sarsılan telefonda ivme yüzünden
   taşıyor, izleme hatasının en kötüsü 0,42'den 6,3 piksele, kareler arası kaymanın p95'i 0,21'den 3,5 piksele çıkıyordu;
   ham ölçüm zaten piksel altı kararlı.

Maliyet: kare başına 1,2–2 ms (Apple M serisi, tek çekirdek, Swift -O). Ortak deneme dosyası
`core/Tests/CouchSubsCoreTests/Fixtures/screen-anchor.json` (yapay kare: alt piksel öteleme, ölçek+dönme, perspektif,
pozlama değişimi, ekranın bir parçası değişiyor, telefon indirildi; ölü bölge ve sıçrama).

## Ölçüm (gerçek kayıt, GTA 6, 23 Kas, 1920×1072, 60 fps)

Kayıt depoda değildir. İki sahne: **A** fitness uygulaması, telefon elde, oyuncu ağırlık kaldırıyor (t = 2189–2192 sn, 179
kare); **B** mesajlaşma, araba sürerken telefon elde (t = 2535.7–2539.5 sn, 229 kare; telefon hızla sarsılıyor).
İzleyici yarım çözünürlükte (960) çalıştı; doğrulama asıl karede (1920), izleyiciden bağımsız: telefonun içindeki 6–8
belirgin yamanın (yazı, simge) başvuru görüntüsü normalize çapraz ilintiyle (±4 piksel tarama, parabolik alt piksel)
arandı ve izleyicinin öngördüğü yerle karşılaştırıldı. Doğrulamanın kendi gürültüsü de sayılara dahildir.

- **İzleme hatası**: çevirinin olması gereken yer ile gösterildiği yer arası (piksel, 1920 genişlikte).
- **Kareler arası kayma**: bu hatanın bir kareden ötekine değişimi (çevirinin telefona göre titremesi).
- **Önce**: çeviri 330 ms'lik turda, telefon eşikten (6,5 piksel ≈ satır yüksekliğinin %25'i) fazla kaymışsa yerine
  sıçrar, arada durur. OCR kutularının kendi oynaması hiç sayılmadı; yani önceki yöntem için iyimser.

| Sahne | Ölçü | Önce (ortanca / p95 / en kötü) | Sonra (ortanca / p95 / en kötü) | Hedef |
|---|---|---|---|---|
| A | izleme hatası | 1,57 / 8,33 / 10,43 | **0,14 / 0,35 / 0,68** | ≤ 1 |
| A | kareler arası kayma | 0,07 / 0,77 / 10,43 | **0,03 / 0,35 / 0,99** | ≤ 0,5 |
| B | izleme hatası | 4,03 / 55,27 / 83,47 | **0,15 / 0,30 / 0,42** | ≤ 1 |
| B | kareler arası kayma | 0,04 / 8,54 / 47,87 | **0,02 / 0,21 / 0,50** | ≤ 0,5 |

İzleme hatası her karede 1 pikselin altında. Kareler arası kaymanın p95'i 0,35'in altında; A'daki tek en kötü değer
(0,99) doğrulamanın düşük karşıtlıklı bir yamasındaki gürültüdür (aynı karede öteki yamalar 0,3'ün altında).

Yeniden üretmek (`tools/screen-anchor/`):

```sh
ffmpeg -ss 2186 -t 16 -i video.mp4 -vf "scale=960:536,format=gray" -f rawvideo segA.gray
ffmpeg -ss 2186 -t 6 -i video.mp4 -vf format=gray -f rawvideo segAf.gray
swiftc -O -o izle tools/screen-anchor/main.swift core/Sources/CouchSubsCore/ScreenAnchor.swift
swiftc -O -o altin tools/screen-anchor/altin.swift
./izle segA.gray 180 370 110 180 320 | head -179 > a.txt
OUT=1 K=2 ./altin segAf.gray 1920 1072 a.txt 180 370 110 180 320 826 214 1040 384 1006 620 986 764 820 592 770 830 > p.txt
python3 tools/screen-anchor/olc.py p.txt 6.5
# B: -ss 2533 (-t 9 / -t 6.6), başlangıç 160, dörtgen 545 85 212 410,
#    yamalar 1266 256 1462 248 1172 700 1366 784 1300 842 1470 860 1300 450 1160 566
```

Görev kartı, harita kartı ve menü kutuları ekrana sabittir; çapa orada birim dönüşümde kalır (çeviri piksel piksel
sabit), yalnız kart açılıp kapanınca ya da kayınca kaybolur. Oradaki titremenin kaynağı OCR kutusunun oynamasıydı
(ScreenStyleLock #1162 ve ScreenPresence #1166 kapatıyor); yerleşim çapaya kilitlenince o da biter.

## Bağlama (sonraki aşamalar)

1. **Çekirdek** (bu aşama): `ScreenAnchor` (Swift/C#/Kotlin), ortak vakalar, eşitlik denetimi, ölçüm aracı.
2. **Akış**: telefon okunduğunda (`PhoneRegionSession`, Windows/Android eşleri) çapa o karede kurulur; balonların kutuları
   telefonun yerel koordinatına çevrilip ilk güvenilir ölçümde kilitlenir (aynı mesaj yeniden okununca yerel yer ve yazı
   boyu değişmez). Her yakalanan karede izleyici çalışır; sunucu öğelerle birlikte `anchor` (başvuru dörtgeni) ve
   kare başına küçük bir `anchor-move` olayı (8 sayı) gönderir. Çapa kaybolunca balon çevirileri hemen gizlenir.
3. **Çizim**: TV (`tv-webos/app.js`, Tizen ve Android TV aynı sayfa) balon katmanını tek kapta tutar, kabın
   `transform`'u `matrix3d` (perspektifsiz `matrix`); Mac/iPhone `CATransform3D`, Windows `MatrixTransform` (perspektif
   payı küçük, afin yaklaşık), Android `Matrix.setPolyToPoly`. Yazı boyu ve satır kırılımı başvuruda bir kez hesaplanır.
4. **Yerinde çizim**: balonun düz zemini özgün yazının üstüne aynı renkle çizilir (#1142 sil-ve-yeniden-çiz), çeviri
   balonun renginde, sabit boyda.

Not: TV'de çeviri, oyunu TV'ye doğrudan veren konsolun görüntüsünün üstünde durur; çapa, Remote Play/yakalama gecikmesi
(tipik 50–100 ms) kadar geriden gelir. Titreme biter, ama hızlı sarsıntıda gecikme kadar geride kalabilir; bilgisayar ve
telefon ekranındaki yayın penceresinde (aynı kare) gecikme yoktur.

## Varsayılan önerisi

Ölçüme göre "Balonların Üstünde" çapayla titremesiz hâle gelir (izleme hatası < 1 piksel). Bağlama ve yerinde çizim
(aşama 2–4) birleşip gerçek kayıtla TV çiziminde doğrulanınca **"Balonların Üstünde" varsayılan olsun** önerilir;
o güne kadar varsayılan "Yanda Panel" kalmalı.
