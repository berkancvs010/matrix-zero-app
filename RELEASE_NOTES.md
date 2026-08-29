## 1.0.8+12 — DeepFix
- Dosya/fotoğraf WebRTC signaling akışı yeniden güvenilir hale getirildi; bağlı arka plan istemcilerine signaling doğrudan yönlendirilir.
- Otomatik dosya kabul tercihi canlı sohbet ekranına anında uygulanır; uygulama çalışırken sohbet açık olmasa da gelen teklif otomatik kabul edilebilir.
- Mesaj okundu durumu yalnızca uygulama gerçekten foreground/resumed durumundayken gönderilir; arka planda gelen mesajlar okunmuş sayılmaz.
- Profil fotoğrafı güncellemelerinde eski cevapların yeni fotoğrafı ezmesi engellendi ve profil revizyonu eklendi.
- Profil görünürlüğü çevrimiçi durumundan ayrıştırıldı; profil güncellemeleri diğer kullanıcılara güvenilir biçimde yayılır.
- Topluluk odalarında kamera seçeneği açıkça devre dışı bırakıldı.
- Hazır/animasyonlu avatar GIF varlıkları projeden kaldırıldı; profil GIF seçimi de kaldırıldı.

# ZeroLog 1.0.8+11

## Deep reliability / UX fix
- Dosya transfer signaling'i arka planda kuyruklanan event'leri uygulama foreground olduğunda yeniden teslim edecek şekilde güçlendirildi.
- Dosya transferi kabul/ICE/SDP akışında reconnect sonrası beklemede kalma riski azaltıldı.
- Özel mesajlarda teslim edildi ve okundu durumları gerçek uygulama görünürlüğüne göre ayrıştırıldı.
- Sohbet arka plandayken mesajlar otomatik olarak okundu işaretlenmiyor; sohbet yeniden görünür olduğunda okunuyor.
- Topluluk odalarında kullanılmayan kamera seçeneği kaldırıldı; özel sohbet kamera akışı korundu.
- Profil fotoğrafı güncellemesinde eski profil cevabının yeni seçilen fotoğrafı ezmesi engellendi.
- Profil güncelleme başarısı/hatası kullanıcıya açık geri bildirimle gösteriliyor.
- Profil reddi cevapları kullanıcı adı ile ilişkilendirildi.

## 1.0.8+9
- Yeni Varsayılan tema ve ZeroLog görsel tasarım sistemi.
- Ana sekmeler ve sohbet listesi yeniden tasarlandı.
- Özel sohbet başlıkları ve mesaj alanı modernize edildi.
- WebSocket yeniden bağlanma ve mesaj teslim akışı sağlamlaştırıldı.
- Profil fotoğrafı ve arka plan çağrı bildirimleri iyileştirildi.


## Reliability pass
- Profil fotoğrafı senkronizasyonu metadata + güvenli tam profil alma akışına ayrıldı.
- Kamera profil fotoğrafı için Android kamera izni eklendi.
- Sohbet fotoğrafları kalıcı yerel kopyaya alınarak gönderici önizlemesi stabil hale getirildi.
- Alınan fotoğraflar sohbet içinde tam ekran açılabilir hale getirildi.
- Dosya transferinin tamamlanma durumu sunucu geçmişinde korunuyor.
- Foreground/background durumu heartbeat ile doğrulanarak arka plan mesaj bildirimleri güçlendirildi.


## Stability and profile fixes
- Remote profile photos are fetched reliably after connection/reconnect.
- Profile photos persist locally as encoded profile data instead of relying on temporary/cache file paths.
- The own profile avatar/photo now uses one consistent rendering source, including the top-right profile avatar.
- Remote photo rendering has explicit photo-over-avatar priority.
- Profile update events now carry an explicit `profileType`.
- Profile fetch failures identify the requested username so pending requests can be released.
- Contact profile fetch requests are no longer marked as sent while the WebSocket is disconnected.
- User-directory refresh clears stale profile-fetch state.
- Contact avatar action menu now starts a voice call from **Ara** instead of performing contact search.

## Server hardening
- Case-insensitive socket lookup is centralized for messaging and call signaling.
- `getUserDirectory` uses the same profile-aware directory path as the presence flow.
- Account/message JSON writes are atomic to reduce corruption risk during interruption.
- Profile response events explicitly include `profileType`.

## Validation
- `dart analyze lib/main.dart test/widget_test.dart` was previously clean on the project baseline.
- `flutter test --no-pub test/widget_test.dart` previously passed on the baseline.
- This environment does not contain the Flutter/Dart SDK binaries, so a fresh local analyzer/build cannot be executed inside this packaging step.
