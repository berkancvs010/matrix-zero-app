# ZeroLog — Kapsamlı Kaynak Denetimi ve Düzeltme Raporu

**Denetim tarihi:** 5 Ekim 2026  
**İncelenen girdi:** `ZeroLog_2_Tur_Derin_Tarama_FINAL_2026-10-05.zip`  
**Düzeltilmiş sürüm:** 1.0.11+35  
**Kapsam:** Retro Oyun Salonu, gizlilik PIN/biometri girişi ve özel mesaj teslim işareti. Önceki rapordaki doğrulanabilir iddialar da kaynak paket üzerinde yeniden kontrol edildi.

## Yönetici özeti

Önceki rapor, beş oyunu “oynanabilir” diye anlatmasına karşın bu kullanıcının kalite beklentisini karşılamamış; ana ayarlar menüsünde ise hâlâ “9 özgün offline oyun” yazıyordu. Ayrıca kaynak raporundaki “düzeltildi” ifadeleri gerçek cihazda APK sınaması anlamına gelmiyordu. Bu turda Retro alanı sıfırdan yenilendi, kullanıcının daha önce bildirdiği PIN/biometri sonrası siyah/boş sayfa riski ve arka plan mesaj teslim makbuzu yolları yeniden incelenip ek korumalar yazıldı. Önceki raporun kapsamı/tarihi ve burada gerçekten neyin doğrulandığı aşağıda açıkça ayrılıyor.

| Alan | Kaynakta bulunan / önceki rapor durumu | Bu sürümdeki işlem | Doğrulama |
|---|---|---|---|
| Retro | Beş farklı, fakat küçük/deneysel oyun; menü metni 9 oyun diyordu | 10 farklı tür; yeniden çizilmiş salon, filtreler, gerçek oyun döngüleri ve gamepad/dokunmatik kontroller | Analyzer PASS; tüm test sonucu aşağıdaki doğrulama kaydında |
| Gizlilik | Shared authentication Future ve lock-remove revision bildirimi zaten vardı; eski rapor bunları önceki çalışma olarak yazmıştı. Kullanıcının siyah ekran hatası bu rapordan giderilmiş sayılamazdı. | Android biyometri sistem penceresinin Activity duraklamasını ikinci global kilit gibi yorumlamama; ayar açma girişini rota açık kaldığı süre boyunca seri tutma; hata Snackbar’ı | Analyzer PASS, kaynak regresyon testi. Gerçek cihazda PIN ve biyometri akışı ayrıca denenmeli |
| Teslim işareti | Native FCM HTTP makbuzuna ek olarak headless socket ACK yolu bulunuyordu. Ancak `pendingPrivateMessages` toplu olayı UI dışında karşılanmadığından arka plan/soğuk başlangıçta teslim ACK’i eksik kalabiliyordu. | Bekleyen batch içindeki her mesaj için token’lı `messageDelivered` ACK; canlı mesaj, sohbet listesi ve sohbet ACK’lerinde sunucu token’ını iletme | Analyzer PASS, statik protokol regresyon testleri. İki cihazla arka plan/force-stop sınaması ayrıca gerekir |
| Önceki audit | Önceki raporun tarih/scope metni eskiydi ve mevcut durumla karıştırılabilirdi | Bu rapor, önceki rapor iddialarını önceki çalışmanın beyanı olarak ayırıyor; eski işlerin kullanıcı cihazında doğrulandığını ileri sürmüyor | Girdi ZIP’inde mevcut rapor okundu ve düzeltildi |

## Retro Oyun Salonu — yeniden tasarım

Önceki 5 oyunluk katalog (`Neon Runner`, `Stack Tower`, `Pixel Hunt`, `Color Reflex`, `Neon Defender`) ile menüdeki “9 oyun” açıklaması birbiriyle uyumsuzdu. Ayrıca önceki notlar kalite beklentisinin karşılandığı anlamına gelecek kadar iddialıydı. Eski oyun kodu/önceki kısa deneysel menü bu turda kaldırıldı ve tek salonda 10 farklı oyun sunuldu:

| Oyun | Tür | Uygulanan temel mekanik |
|---|---|---|
| Piksel Macerası | Arcade/platform | Yürüme, zıplama, zemin/platform çarpışması, altın toplama, düşman, can ve bitiş koşulu |
| Tank Arenası | Arcade | Hücre tabanlı hareket, engeller, oyuncu ve düşman mermileri, can, kazanma/kaybetme |
| Uzay Savunması | Arcade | Dalgalar, gemi hareketi, ateş, skor ve can |
| Yılan | Arcade | Yön kilidi, çarpışma, yem, büyüme ve oyun sonu |
| Tuğla Kırıcı | Arcade | Top/yastık çarpışması, tuğlalar, can ve seviye |
| Raket Düellosu | Arcade | Rakip paddle, sayı takibi ve 7 puanlık maç |
| Blok Düşürme | Puzzle/arcade | Parça hareketi, döndürme, düşürme, sıra temizleme ve çarpışma |
| Reversi | Puzzle/strateji | Yasal hamle ve taş çevirme, geçiş/sonuç, köşe/kenar tercihli yerel CPU rakibi |
| Mayın Tarlası | Puzzle | İlk tıklama güvenli, bayrak, komşu sayısı, boş alanı açma ve kazanma |
| Sayı Birleştirme | Puzzle | Dört yönde kaydırma, doğru sağ/aşağı ters çevrimi, birleştirme, 2048 ve hamlesiz son |

Oyunlar orijinal Dart çizimleri ve mekanikleriyle çevrimdışı çalışır. Bu değişiklikte ROM, Nintendo/Sega oyun dosyası, üçüncü taraf karakter/görsel/müzik, reklam SDK’sı veya oyun sunucusu eklenmedi. Tür filtreleri, oyun kartları, gamepadı gizle/göster ve sıfırlama denetimleri de yenilendi. Başlangıç menüsünün alt yazısı artık 10 oyunu doğru sayıyor.

Ayrıca test incelemesinde bulunan iki oynanış kusuru düzeltildi: sayı birleştirme oyununda sağ/aşağı hareket ters yönde işleniyordu; tank düşmanları oyuncuyla aynı hücreye girebiliyordu. Pong’da puandan sonra servis yönü doğru skorlayana döndürüldü. Her süreli oyun kapatılırken periyodik timer’ını iptal ediyor.

## Gizlilik PIN’i ve biyometri

Eski raporda `ZeroLogPrivacyLock.authenticate` çağrılarının ortak Future ile serileştirildiği, PIN kaldırmanın secure-storage anahtarlarını silip `configurationRevision` bildirdiği ve app-wide gate’in bu revizyonu dinlediği yazılıydı. Bunlar önceki kaynak paketinde zaten mevcuttu; bu turdaki yeni düzeltmeler gibi sunulmamalıdır. Kullanıcının siyah ekranda kalma bildirimini de önceki rapor kanıtlamıyordu.

Bu turda, Android biyometrik sistem penceresinin uygulama `paused`/`resumed` olayına sebep olabileceği ve auth Future tamamlanırken global app-lock gate’in ikinci bir kilit ekranı bindirebileceği yolu korumaya alındı. Global gate, Activity duraklaması anında gizlilik kimlik doğrulamasının sürüp sürmediğini kaydediyor ve bu biyometri kaynaklı dönüşte yeniden auth istemiyor. Gizlilik ayar sayfasına art arda giriş rota açık kaldığı süre boyunca engelleniyor; doğrulama veya açma sırasında istisna oluşursa kullanıcıya hata Snackbar’ı veriliyor. PIN kaldırma davranışı, biyometri anahtarı temizliği ve lock gate revision bildirimi regresyon testiyle korunuyor.

Bu, siyah ekranın gerçek telefonda tamamen kaybolduğunun kanıtı değildir. Yeni APK’nin normal giriş, PIN ile giriş, biyometri başarı, biyometri iptal → PIN, PIN/biyometri kapatma ve uygulama arka plana alınarak geri dönme senaryoları fiziksel Android cihazda sınanmalıdır.

## Mesaj teslim ve okundu tikleri

Önceki kaynakta canlı gelen özel mesajlarda transport katmanı teslim ACK’i ve Android FCM servisinde HTTP teslim makbuzu yedeği mevcuttu; sunucuya gönderilmiş olmayı tek başına teslim sayma yolu olarak görmedim. Sunucu da kimliği doğrulanmış alıcı ve varsa sunucu token’ı ile ACK doğruluyordu. Sorunlu senaryoda özellikle soğuk başlangıç/arka plan login’inin, tekil `privateMessage` yerine `pendingPrivateMessages` listesi üretmesi önemliydi: ACK mesaj balonuna/aktif sohbete bağlı kalırsa alıcı arayüzü kurulmadığında gönderilemeyebilirdi.

Bu nedenle `WsClient` şimdi pending mesaj listesindeki her gerçek, alıcıya ait mesajı mesaj ID’si ve sunucunun ürettiği `deliveryToken` ile ACK’liyor. `main_screen.dart` içindeki iki liste/tekil ACK yoluna da token eklendi. Sunucunun `/delivery` HTTP makbuzu yedeği olduğu gibi kaldı. Kullanıcının “okundu ve sunucuya ulaştı çalışıyor, iki gri tik çalışmıyor” gözlemiyle örtüşen arka plan yoluna odaklanıldı; `read`/okundu semantiği değiştirilmedi.

## Önceki rapordaki iddiaların sınırı

Girdideki 5 Ekim tarihli eski `FINAL_AUDIT_REPORT.md`, gelen arama/screen wake, yeniden bağlanma bildirimi, PIN auto-submit, WebRTC watchdog, gizlilik ortak Future ve mesaj teslim makbuzu gibi önceki düzeltmelerden bahsediyordu. Bu rapor onların tarihsel notunu içerir; ancak her Android OEM’de veya son kullanıcı cihazında test edildiğini **kanıtlamaz**. Bu turda esasen ilgili kod yolları okundu; eski arama/WebRTC sorunlarının fiziksel cihazda yeniden regresyon testi yapılmadı.

Kullanıcının “nerede ve ne zaman düzelttin?” sorusuna kaynak paketten çıkarılabilen cevap: önceki dosya `FINAL_AUDIT_REPORT.md` 5 Ekim 2026 tarihini veriyor; daha eski uygulama koduna ilişkin kesin commit/timestamp kanıtı ZIP’te yok (girdi paketi git geçmişi taşımıyor). Dolayısıyla önceki işlerin gerçek uygulama anını daha dar bir zamanla belgeleyemiyorum. Bu rapor yalnız bu turdaki dosya değişikliklerini ve çalıştırılan doğrulamaları açıklıyor.

## Test ve paket doğrulama

- `flutter analyze --no-pub`: PASS — **No issues found** (Flutter 3.47.6 / Dart 3.13.5).
- Retro katalog kontrolü: 10 benzersiz oyun ve her oyun için dispatch dalı: PASS.
- Android XML: 11 dosya parse edildi: PASS.
- `node --check server/server.js`: PASS.
- Tam `flutter test --no-pub`: PASS — **88 test geçti**, sıfır başarısız test.
- Android build tools (`android.jar`, SDK Manager/ADB) sandbox’ta kurulu değil; bu yüzden **APK/AAB derlemesi ve cihaz üzerinde APK testi bu teslim için yapılmadı**. Flutter uygulaması test edilebilir; native Android release build doğrulaması için gerçek Android SDK/JDK ek adımları gerekir.
- Üretim release imzası ve Play Store dağıtımı bu görevde yapılmadı.

## Sürüm ve değişiklik noktaları

Sürüm `1.0.11+35` olarak artırıldı. Esas kod: `lib/retro_arcade.dart` (salon ve on oyun), `lib/main_screen.dart` (retro kısayolu, privacy route ve canlı delivery ACK’leri), `lib/app_lock_gate.dart` (biyometri Activity lifecycle), `lib/networking.dart` (pending batch ACK), `lib/privacy_lock.dart` (await/error akışı). Regresyon testleri `test/retro_arcade_regression_test.dart`, `test/retro_arcade_widget_test.dart`, `test/messaging_delivery_regression_test.dart`, `test/privacy_lock_regression_test.dart` dosyalarındadır. Release version testi `test/file_transfer_regression_test.dart` içinde 35’e güncellendi.
