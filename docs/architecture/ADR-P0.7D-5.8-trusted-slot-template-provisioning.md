# ADR P0.7D-5.8 — Trusted Canonical Slot Template Provisioning

## Karar

Canonical slot template'leri Flutter istemcileri tarafından oluşturulmaz,
değiştirilmez veya silinmez. İlk kurulum ve sonraki kontrollü katalog
değişiklikleri, repository içindeki versioned Admin SDK provisioning aracıyla
yapılır. Araç varsayılan olarak dry-run'dır; gerçek yazım için açık `--apply`
ve operatör kimliği gerekir.

Bu karar booking approval için bir server-side runtime bağımlılığı oluşturmaz.
Provisioning aracı, release/operasyon sırasında seyrek kullanılan trusted
admin işlemidir. Template'ler bir kez oluşturulduktan sonra Coach'un
client-side Firestore transaction'ı Spark üzerinde approval yapmaya devam
eder.

## Canonical template seti

```text
0800 0900 1000 1100 1200 1300 1400
1500 1600 1700 1800 1900 2000
```

Her ID Europe/Istanbul yerel saatinde saat başı başlayan bir saatlik
reservation koordinatıdır. Gerçek ders uygulama süresi 50 dakikadır; bu
bilgi template Rules güvenliği veya overlap otoritesi değildir.

## En sade production şeması

```text
schedule_slot_templates/{slotId}
  slotId: string       // document ID ile aynı, ör. "0900"
  sequence: int        // 0..12, yalnız görüntüleme sırası
  active: bool         // yalnız yeni booking request seçimine etki eder
  schemaVersion: int   // immutable katalog şekli sürümü
```

`reservationMinutes: 60` ve `serviceDurationMinutes: 50` kalıcı template
alanları **önerilmez**. İkisi de Rules güvenliği için gerekli değildir ve
dondurulmuş global hizmet sözleşmesini ikinci kez saklayarak drift riski
oluşturur. Reservation birimi `slotId`, hizmet bilgisiyse shared domain
contract/UI metnidir.

Gelecekte slot başına farklı hizmet veya reservation süreleri gerekirse bu
ayrı bir schema/ürün kararıdır; mevcut `slotId` semantiği mutate edilmez.

## Client Rules politikası

```text
create: deny
update: deny
delete: deny
read: deny (varsayılan)
```

Client read de gerekli değildir: booking formu shared domain contract'taki
canonical slot listesini gösterebilir; Rules kendi `get()` çağrısıyla
template'i doğrular. İleride istemci kataloğu okuması gerekiyorsa yalnız
authenticated `get` ile dar açılış ayrıca değerlendirilir; global list izni
varsayılan değildir.

Rules, request/session/slot path'indeki `slotId` için trusted template
belgesinin varlığını ve `template.slotId == slotId`, `active == true` ve
beklenen schema sürümünü kontrol eder. Böylece bilinmeyen veya sahte slot ID
ile yeni reservation oluşturulamaz.

## Provisioning seçimi

Firebase Console üzerinden tek seferlik manuel oluşturma teknik olarak
mümkündür, ancak versioned manifest, idempotency, dry-run, tam set denetimi ve
audit kolayca tekrar üretilemediği için önerilmez.

`tool/provision_schedule_slot_templates.js` tercih edilen yöntemdir:

- Admin SDK kullanır; production dry-run dahil Firestore okumak için matching
  service account gerekir.
- Service account dosyası repository'ye eklenmez.
- Emulator yalnız loopback host ile kullanılabilir ve production proje ID'sini
  reddeder.
- Eksik template'leri raporlar ve yalnız `--apply` ile oluşturur.
- Var olan belge beklenen canonical içerikle aynıysa no-op yapar.
- Var olan canonical belge farklıysa overwrite etmez; conflict olarak durur.
- Fazla template'leri raporlar, silmez.

Admin SDK'nın kullanılması runtime server-side approval değildir: araç normal
Flutter çalıştırma yolunda çağrılmaz ve Admin SDK Rules'u bypass ettiği için
yalnız kontrollü operatör ortamında çalıştırılır.

## Versioning ve pasifleştirme

Template ID'nin semantiği immutable'dır. `0900` hiçbir zaman başka başlangıç
zamanına veya farklı reservation uzunluğuna dönüştürülmez.

- Yeni request'leri kapatmak için trusted provisioning `active: false` yazar.
- Mevcut Session'lar kendi immutable `dayKey + slotId` snapshot'ını taşır;
  pasifleştirme onları etkilemez.
- Eski template aktifliği geri alınacaksa yine trusted provisioning kullanılır.
- Shape değişikliği `schemaVersion` ile yeni katalog sürümü olarak yapılır;
  mevcut belge semantiği client tarafından değiştirilmez. Uyumsuz köklü
  değişiklikte yeni collection/version ve kontrollü cutover kullanılır.

## Canonical dayKey kararı

`YYYY-MM-DD` sabit formatıdır. Regex, `2026-8-3` gibi eşdeğer ama farklı
temsil biçimlerini reddeder; ancak Rules gerçek takvim geçerliliğini (ör.
31 Şubat) hesaplayamaz.

Bu nedenle `schedule_days/{dayKey}` trusted katalog olarak korunur. Her belge
en az `dayKey`, `working`, `scheduleTimeZone`, `schemaVersion` taşır.
Bu katalog double-booking için gerekli değildir; **gerçek gün, hafta sonu ve
çalışma takvimi politikasını Rules'a doğrulatmak** için gereklidir. Belge
olmaması güvenli biçimde yeni reservation'ı kapatır. Rolling horizon, aynı
trusted provisioning ailesinin ayrı bir operasyon görevidir.
