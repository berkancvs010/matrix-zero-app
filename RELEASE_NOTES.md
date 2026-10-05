# ZeroLog 1.0.11+35

## Retro Oyun Salonu yenilendi
- Önceki beş kısa/deneysel oyunun menüsü kaldırıldı; on oynanabilir oyun sunuluyor: Piksel Macerası, Tank Arenası, Uzay Savunması, Yılan, Tuğla Kırıcı, Raket Düellosu, Blok Düşürme, Reversi, Mayın Tarlası ve Sayı Birleştirme.
- Platform oyununa hareket, zıplama, çarpışma, toplanabilirler, düşman, can ve bitiş koşulu; tank oyununa grid hareketi, engel, düşman ateşi ve kazanma/kaybetme koşulları eklendi.
- Reversi artık yasal hamle üretimi ve köşe/kenar tercihli basit bilgisayar rakibiyle oynanabiliyor.
- Ana oyun salonu, tür filtreleri, özgün çizimler ve sanal gamepad akışları yeniden tasarlandı.
- ROM, üçüncü taraf oyun görseli/sesi, reklam veya ağ bağımlılığı kullanılmıyor.

## Mesaj teslim bilgisi
- Arka plan/soğuk başlangıç WebSocket oturumlarında sunucunun `pendingPrivateMessages` toplu olayı artık mesaj başına ACK üretiyor.
- Sohbet listesi ve sohbet ekranından gönderilen teslim ACK’leri sunucu tarafından verilmiş `deliveryToken` değerini iletiyor.
- FCM/HTTP teslim makbuzu yedeği korunuyor; sunucu FCM gönderiminin kabul edilmesini tek başına teslim saymıyor.

## Gizlilik erişimi
- Android biyometrik sistem penceresinin Activity’yi geçici duraklatması, uygulamaya geri dönüldüğünde ikinci global kilit ekranı açılmasına neden olmamalı.
- Gizlilik sayfası girişini seri hâle getiren koruma ve doğrulama/depolama hatalarında kullanıcıya geri bildirim eklendi.
- PIN kaldırma sırasında biyometri ayarı da temizleniyor ve app-wide gate’e yapılandırma değişikliği bildiriliyor.

## Sürüm / doğrulama
- Uygulama sürümü: `1.0.11+35`.
- Bu kaynak paketinde APK/AAB oluşturulmadı. Flutter SDK ve Android araçları kullanılabiliyorsa analiz, regresyon testleri ve debug APK build’i ayrıca doğrulanacaktır.
