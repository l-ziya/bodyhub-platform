# ADR P0.7D-5.7 — Saatlik Slot Koordinasyonu ve Süre Sözleşmesi Fizibilitesi

## Durum

**POC altında.** Bu belge V1 akışını, üretim Rules dosyasını veya mevcut
ders süre davranışını değiştirmez.

## Dondurulmuş ayrım

Rezervasyon koordinatı yalnız `dayKey + slotId` ile belirlenir. Canonical
slotlar `0800` ile `2000` arasında saat başında başlar ve her biri tam bir
saatlik, birbirini örtmeyen bir rezervasyon kaynağıdır. Dersin uygulama
süresi 50 dakikadır; scheduling lock, timestamp overlap veya Rules zaman
aritmetiğinin otoritesi değildir. Bir rezervasyon entitlement içinde bir
ders sayılır.

Bu ayrımın sonucu olarak V2 Session takvimde `dayKey` ve `slotId` ile
gösterilir. İstemcinin sağladığı `startAt`/`endAt` varsa yalnız türetilmiş
görüntüleme metadata'sıdır ve Rules açısından zaman otoritesi değildir.

## V1 süre denetimi

| Kategori | Bulgular | Karar |
| --- | --- | --- |
| A — doğru hizmet süresi | Student ve Coach `core/config/lesson_duration.dart`; iki duration unit testi; dashboard kartı; ders görünümü | 50 dakika hizmet bilgisini koru. |
| B — V1 scheduling hesabı | Student `booking_repository.dart`; Coach `coach_booking_repository.dart`, `coach_lesson_repository.dart`, `coach_availability_repository.dart`, `coach_attendance_repository.dart`, `coach_package_repository.dart`; `booking_slot_blocks.dart` | V1 cutover'a kadar aynen koru. Bunlar mevcut booking/lesson/availability slot hesaplarıdır. |
| C — V2 ile çelişen süre hesabı | Shared domain `BusyBlockContract`: 50 dakika + beş adet 10 dakika busy block; D-5.6 günlük grid ADR/POC | D-5.7 saatlik slot POC'sinin otoritesi değildir; V2 scheduling seçilirse deprecated/migrate edilecek. |
| D — test/dokümantasyon | Coach integration testlerinde 50 ve legacy 60 dakikalık fixture'lar; Student Admin busy-lock harness; D-5.6 ADR/POC | V1 fixture'ları değiştirme. D-5.6 belgeleri reddedilmiş yaklaşımın audit kanıtı olarak kalır. |
| E — güvenle kaldırılabilir | Bu denetimde güvenle kaldırılabilecek bir kullanım belirlenmedi. | Değişiklik yok. |
| F — manuel karar | Student availability UI'si 13 adet saat başı başlangıç üretirken `lessonDuration` ile bitişi 50 dakika hesaplıyor; V1 aynı zamanda hafta sonu seçenekleri sunuyor. | V2 saatlik slot UI'sine geçiş ayrı cutover kararıdır; bu POC'de değiştirilmez. |

### 60 dakika bulguları

Üretim Flutter kodunda `Duration(minutes: 60)` bulunmadı. Bulunan 60 dakika
kullanımları yalnız Coach integration fixture'larındadır:

- `integration_test/coach_lesson_repository_test.dart`
- `integration_test/coach_availability_repository_test.dart`

Bunlar legacy Lesson süresini koruma testleridir; V1 davranışının parçası
oldukları için bu pakette dönüştürülmez.

### V2'ye geçerken değişecek/kalan noktalar

- V2 reservation Rules ve çakışma kontrolü 50 dakikayı hesaplamaz; saatlik
  `slotId` kaynaklarını kullanır.
- V1 `booking_slots` ve `lessonDuration` tabanlı reservation temizliği
  V1 boyunca aynen kalır.
- 50 dakika kullanıcı metni, servis metadata'sı ve gerçek uygulama süresi
  olarak korunur.
- V2 UI, "Derslerin uygulama süresi 50 dakikadır." bilgisini gösterebilir;
  bu bilgi slot ownership veya Rules koşulu değildir.

## Seçilen POC veri şekli

```text
schedule_slot_templates/{slotId}
schedule_days/{dayKey}
poc_hourly_coach_slots/{coachId}/days/{dayKey}/slots/{slotId}
poc_hourly_student_slots/{studentId}/days/{dayKey}/slots/{slotId}
poc_hourly_booking_requests/{requestId}
poc_hourly_sessions/{sessionId}
```

`schedule_slot_templates` trusted, immutable katalogtur. Her şablon sabit
`slotId`, 60 dakikalık reservation penceresi ve 50 dakikalık service metadata
taşır. `schedule_days` trusted bir takvim günüdür; yalnız çalışma günü olan
günler bulunur. Böylece Rules tarih/timestamp hesaplamaz; path ve immutable
trusted belge eşitliklerini denetler.

## Approval transaction şekli

1. Pending request, Coach slot ve hedef Student slot okunur.
2. Coach slot `available → reserved` güncellenir.
3. Student slot `create` edilir; mevcut belge overwrite edilemez.
4. Session oluşturulur.
5. Request `pending → approved` olur.

Session Rules'u request, Coach slot, Student slot, day ve template
belgelerinin `getAfter()` durumunu doğrular. Her slot Rules'u ters yönde
Session ve request ilişkisini doğrular. Böylece bağımsız slot değişimi veya
yarım approval reddedilir.

İşlem beş yazımdır. Gerekli entitlement ve roster güncellemeleri eklendiğinde
yedi yazıma çıkar. POC'nin en geniş doğrulama yolu en fazla beş benzersiz
Rules belge erişimi kullanır (request, Session, Coach slot, Student slot,
template/day; cache ile tekrarlar sayılmaz); transaction genel limiti 20,
işlem başına limit 10'dur.

## Beklenen güvenlik garantisi

- Aynı Coach/dayKey/slotId için yalnız bir reserved Coach slot vardır.
- Aynı Student/dayKey/slotId için yalnız bir Student slot vardır.
- Bu iki slot aynı approved request ve Session'a bağlıdır.
- İkinci approval, Coach veya Student slotunun mevcut durumu nedeniyle
  transaction retry/failure ile tamamen reddedilir.
- Farklı Coach ve Student çiftleri aynı saatlik slotta birbirini engellemez.
- Pending request slot tüketmez; duplicate pending request kritik güvenlik
  invariant'ı değildir.

## Bilinen sınırlar

- Bu model 10 dakikada başlayan ders sunmaz; yalnız sabit saat başı slotlar
  sunar.
- Calendar day ve slot template kataloglarının trusted provisioning ile
  sürdürülmesi gerekir. Eksik gün/slot güvenli biçimde rezervasyonu kapatır.
- Spark plan teknik olarak uygundur; günlük ücretsiz kota, aktif kullanıcı
  sayısına göre ayrıca izlenmelidir.
