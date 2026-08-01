# ADR P0.7D-5.6 — Daily Schedule Grid Fizibilitesi

## Durum

**Karar bekliyor — üretim mimarisi olarak onaylanmadı.** Bu ADR, Spark
uyumlu günlük schedule-grid yaklaşımının Firestore Rules ile sağlayabildiği
ve sağlayamadığı garantileri ayırır. V1 davranışı ve kapalı V2 koleksiyon
izinleri değişmez.

## Bağlam

Önerilen koordinat `scheduleTimeZone`, `dayKey`, `startSlotIndex` ve
`durationBlocks` alanlarından oluşur. Zaman çizelgesi için otorite bu
koordinatlardır; `startAt` ve `endAt` yalnız görüntüleme ve sorgu
metadata'sıdır. Standart seans Europe/Istanbul takviminde 50 dakika, beş
adet 10 dakikalık bloktur. Çalışma penceresi hafta içi 09:00–20:00'dır:
başlangıç indeksleri 54–115, dolayısıyla beşinci blok hiçbir zaman 119'u
aşmamalıdır.

## Değerlendirilen belge biçimleri

| Seçenek | Rules açısından sonuç |
| --- | --- |
| A — `slots: { "54": sessionId }` map'i | `Map.diff().affectedKeys()` ile tam beş key değişimi ve değerlerin aynı `sessionId` olması denetlenebilir. Ancak Rules, `int startSlotIndex` değerini string map key'e dönüştüremez ve map key'leri üzerinde yineleyemez. |
| B — `s054`, `s055` gibi sabit alanlar | Top-level diff daha görünürdür; fakat seçilen beş alanın sayısal başlangıç indeksiyle bağlanması yine sayıdan alan adına dönüşüm veya 62 olasılıklı statik bir kural tablosu gerektirir. Bu bakım ve hata yüzeyi açısından kabul edilebilir değildir. |
| C — Array | Rules array diff'i değişen indeks kümesini vermediği için tam beş ardışık indeks ve overwrite yasağını map kadar açık denetleyemez. |

**POC tercihi A'dır.** Bu, sağlanabilen kuralları göstermek ve sağlanamayan
invariant'ı kesin olarak görünür kılmak içindir; üretim seçimi değildir.

## POC'nin kanıtladığı kısım

Test kuralları bir Coach onay transaction'ında aşağıdakileri doğrular:

1. request `pending → approved` geçer;
2. Session, Coach günü ve Student günü aynı `coachId`, `studentId`, `dayKey`,
   `durationBlocks == 5` ve `scheduleTimeZone == Europe/Istanbul` değerlerini
   taşır;
3. her gün belgesinde `slots` map'inde tam beş yeni key değişir;
4. bu beş değerin tamamı aynı `sessionId` olur;
5. mevcut slotlar üzerine yazım reddedilir;
6. Session olmadan veya yalnız bir tarafın günlük belgesini değiştirerek yazım
   yapılamaz;
7. Firestore transaction başarısız olduğunda hiçbir kısmi belge kalmaz.

İşlemde dört benzersiz belge erişimi vardır: booking request, session, Coach
schedule ve Student schedule. İki günlük belge + Session + request yazımı
dört yazımdır. İleride entitlement eklenirse beş, roster projeksiyonu da
eklenirse altı yazım olur. Bu POC şekli işlem başına 10 ve transaction başına
20 Rules access-call sınırının altındadır; ancak bu, aşağıdaki eksik invariant'ı
telafi etmez.

## Kanıtlanan engel

Firestore Rules dilinde `int` değeri string'e çevrilerek `"s054"` gibi map
anahtarı üretilemez; map key'leri üzerinde döngü de yoktur. Bu nedenle Rules,
şu zararlı fakat diğer bütün POC doğrulamalarına uyan yazımı genel olarak
ayırt edemez:

```text
session.startSlotIndex = 54
session.slotKeys       = [s060, s061, s062, s063, s064]
schedule.slots'ta değişen key'ler aynı listedir
```

Bu durumda görünen Session 09:00 iken gerçekte 10:00 blokları kapatılır.
Bu yalnız görüntüleme hatası değildir: sonraki çakışma kontrollerinin ve audit
geçmişinin zaman otoritesi tutarsızlaşır. POC bu yazımın Rules tarafından
kabul edildiğini negatif kanıt olarak doğrular.

Tam beş *değişen* map key'i denetlenebilse de, Rules genel yazım kümesini
sayamaz; aynı belge içinde map diff ile görünen beş key dışında başka belge
yazılıp yazılmadığını da bir client Rules ifadesiyle enumerate edemez.

## Sonuç

Bu model, **mevcut dondurulmuş `int startSlotIndex` sözleşmesiyle Rules'ta
canonical scheduling güvenliği sağlamaz**. Bu nedenle D-6'ya geçiş için
yeterli değildir ve production Rules açılmaz.

Kabul edilebilir sonraki seçenekler:

1. Approval'ı güvenilir sunucu tarafı çalıştırmaya taşımak; Spark-only
   kısıtıyla uyum değerlendirmesi ayrı karar gerektirir.
2. Koordinatı Rules'un doğrudan doğrulayabildiği, sınırlı ve statik bir temsil
   ile yeniden tasarlamak. Bu, `startSlotIndex` sözleşmesini değiştireceği
   için yeni mimari onayı gerektirir.
3. Client transaction doğrulamasını tek koruma kabul etmek. Bu seçenek
   kötü niyetli claim sahibi istemciye karşı güvenlik garantisi vermez ve
   güvenlik önceliğiyle uyumlu değildir.

## Paket politikası değerlendirmesi

`student_entitlements` için önerilen counter invariant'ı:

```text
reservedSessions + usedSessions + remainingSessions == totalSessions
```

Rules, aynı belge üzerinde sayısal invariant'ı doğrulayabilir. Ancak aşağıdaki
politika kararları D-8 öncesinde ayrıca dondurulmalıdır:

- `monthly`: yalnız aktivasyon ayının 1–7. günleri arasında açılır; bitişi o
  takvim ayının son günüdür. Ay sonu hesabı istemciden gelen timestamp'e
  dayanmayacak, trusted provisioning veya doğrulanabilir canonical dönem
  alanlarıyla kurulmalıdır. Rules takvimden ayın son gününü hesaplayamaz.
- `tenSession` ve `tenSessionOnline`: `recurringWeekdays` benzersiz,
  sıralı olmayan `int` listesi olmalıdır; `1=Pazartesi ... 7=Pazar`.
  Hafta içi çalışma kuralı korunursa yalnız `1..5` kabul edilir. İki farklı
  gün activation-time hard şartı olarak doğrulanabilir (`size == 2`, her
  eleman aralıkta ve birbirinden farklı); altı haftalık bitiş ise
  trusted/canonical hesaplama gerektirir.
- Haftada en az iki gün, geriye dönük booking engeli değil activation-time
  program taahhüdüdür. Geçmiş haftalara yönelik hard enforcement bu ADR'nin
  dışında tutulur.

Mevcut V1 availability belgeleri hafta içi 09:00–20:00 sözleşmesinin tüm
ürün durumlarıyla eşdeğer olduğunu kanıtlamaz; V2 aktivasyonunda hafta sonu
reddi ancak ürün kuralı ayrıca dondurulduğunda uygulanmalıdır.
