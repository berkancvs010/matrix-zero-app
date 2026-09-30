# ZeroLog 1.0.10+26 — Görüntülü görüşme ve profesyonel arayüz (2026-09-30)

- WebRTC tabanlı gerçek görüntülü görüşme eklendi.
- Sesli ve görüntülü çağrı aynı çağrı sinyalleşme altyapısını kullanır; görüntülü çağrı türü davet, FCM, kabul ve SDP/ICE akışında korunur.
- Ön ve arka kamera arasında geçiş, kamera aç/kapat, mikrofon ve hoparlör kontrolleri eklendi.
- Uzak görüntü tam ekran, yerel kamera küçük önizleme olarak gösterilir.
- Android kamera + mikrofon izinleri görüntülü çağrı başlatıldığında istenir.
- Aktif görüşmeler için Android foreground service eklendi; Android 14+ kamera/mikrofon foreground-service gereksinimleri desteklendi.
- Tema önizlemeleri, Gizlilik Merkezi/PIN-biyometri kilidi ve profesyonel web ana sayfa yenilemesi korunmuştur.
- `/download/` indirme sayfası ve 443 canonical web bağlantıları doğrulandı.

## ZeroLog 1.0.10 — Privacy / UI / Web refresh

- Unified the visible in-app version to 1.0.10.
- Added professional live chat previews to the theme selector.
- Protected the Privacy Center with device-local PIN and optional biometric authentication.
- Added persistent PIN brute-force protection with progressive temporary lockouts after repeated failures.
- Refreshed the public ZeroLog website with a new premium landing page, animated network background and “Why ZeroLog exists” section.
- Added a dedicated Android download page and canonical APK download target.
- Removed public website references to the retired HTTPS :8443 endpoint; production web/API traffic uses standard HTTPS 443.

## V31.4

- Fixed Dart library directive ordering in `lib/main.dart` so all `part` directives precede declarations.
- Fixed the CI Android release path by generating and validating the Gradle 9.3.1 wrapper before Flutter release builds.
- Canonicalized the public web/API endpoints to HTTPS 443; removed the temporary :8443 deployment references from the static site.
- Removed the unused `lib/main_web.dart` WebSocket client so the static legal web surface matches the release regression test.

- Security hardening: CSRF-protected web account deletion, transfer failure cleanup, socket cleanup, HTTP security headers, public-room moderation, and release validation fixes.

# V31.3 — Final security/session hardening

- Fixed case-insensitive socket-map cleanup during account deletion.
- Account deletion now sends `callEnded` to active call peers and falls back to call-status push when needed.
- Account-deletion file transfers now use the existing durable terminal-failure path, including transfer-specific background sockets and persisted failure events.
- Added production HTTP security headers.
- Added single-use, expiring CSRF protection to the web account-deletion form.

## V31.2 — Play Store final hardening (2026-09-28)

- Fixed the release-build `zeroLog()` library-scope compile error in `file_transfer.dart`.
- Added block/report actions to public community-room messages.
- Added protected moderation report review/action endpoints.
- Added rate limiting to the public web account-deletion form.
- Account deletion now removes room messages, block-list references, active calls, live sockets and reliable file-transfer sessions.
- Added Terms of Use covering prohibited user-generated content and moderation.
- Expanded the public privacy policy to document networking, moderation, IP/rate-limit and call-related data.
- Added the Terms page to the static legal-site CI validation.
- Kept the V30 reliable file-transfer ACK retransmission and zero-copy payload path unchanged.

## V31.1 — Final Play Store / web hardening (2026-09-28)

- Corrected the GitHub Actions signing path so the CI-created upload keystore is resolved from the Android project root by the app Gradle module.
- Removed the public Flutter Web chat build/deployment path; the web surface is now a static information/legal site with no WebSocket client.
- Added static privacy and account/data deletion pages under `web/`; the existing server deletion endpoint remains the form target.
- Kept V30 reliable file-transfer ACK retransmission and V31 zero-copy payload decoding unchanged.

## V31 — Play Store release hardening (2026-09-28)

- Added production upload-keystore based release signing configuration; debug signing is no longer used for release builds.
- GitHub Actions now builds and uploads a signed Android App Bundle (AAB) for Play Store release, plus an APK smoke artifact.
- Pinned the production target SDK to API 36 and verified the CI target configuration.
- Added public HTTPS privacy policy and web account/data deletion endpoints.
- Added in-app user blocking and user reporting with server-side enforcement for private messages, calls, and file transfers.
- Added local account-data cleanup on account deletion, including ZeroLog file storage and app preferences.
- Disabled Android backup/data extraction for the production app.
- Made camera and microphone device features optional so devices without those features can install the app.
- Unified the notification channel ID and added a dedicated monochrome notification icon.
- Gated diagnostic logging behind kDebugMode.
- Restored zero-copy file-transfer payload slicing with Uint8List.sublistView without changing V30 ACK retransmission reliability logic.

## V30 — Reliable ACK retransmission / 26% stall repair (2026-09-27)

- Re-audited the complete reliable file-transfer path after the 128 KiB / 26% stall shown in the device test.
- The sender now retains the exact outstanding binary frame and retransmits it every 2 seconds until its cumulative ACK arrives.
- A lost ACK can no longer leave the receiver permanently parked at the last chunk while the sender waits for the 90-second timeout.
- Receiver ACK-send failure is now treated as recoverable; a retransmitted duplicate chunk is detected as already committed and causes the ACK to be sent again instead of tearing down the transfer.
- A transient `sendBinary()` failure now gets a connection-recovery attempt before the transfer is failed.
- Sequence ordering, resume, SHA-256 verification, manifest checkpoints, completion handshake, foreground service and server relay behavior remain intact.
- Added regression assertions for outstanding-frame retransmission and non-fatal ACK-send failure.

## V29 — Reliable file-transfer forward-progress repair (2026-09-27)

- Outgoing reliable file transfers now use a single 128 KiB chunk in flight instead of an 8-chunk burst.
- This prevents the Android/WebSocket receiver and server relay from being overwhelmed by a burst and then stalling around the first chunk while the sender waits for a cumulative ACK.
- Resume, SHA-256 verification, durable receiver manifest, background transfer and terminal completion logic are unchanged.
- Added a regression assertion that prevents the sender window from being accidentally raised back to the burst mode.

## V22 — Mesaj rate-limit istemci görünürlüğü (2026-09-16)

- `messageRateLimited` artık özel sohbet istemcisinde ilgili optimistic mesajı `Gönderilemedi` durumuna geçirir.
- `privateMessageRejected` artık `clientMessageId` üzerinden ilgili optimistic mesajı `Gönderilemedi` olarak işaretler.
- Başarısız özel mesajlar kırmızı hata simgesi ve `Tekrar gönder` eylemiyle görünür.
- Başarısız yerel mesajlar sohbet geçmişi yeniden yüklenirken korunur.
- Oda mesajlarında rate-limit olayı kullanıcıya bekleme süresiyle bildirilir.
- Sunucu rate-limit/rejection olaylarına gerekli mesaj kimliğini ve kapsam bilgisini ekler.

## V21 kontrollü birleşim — V20 tabanı + güvenli V21 düzeltmeleri (2026-09-15)

- `callRejected` içinde `reason: busy` için kullanıcıya özel meşgul mesajı eklendi. Sunucunun V20 tabanında zaten gönderdiği `reason: busy` alanıyla uyumludur.
- Android APK sürüm/build numarası `1.0.8+15` → `1.0.8+16` olarak artırıldı.
- V21 sunucusundaki `reliableFileFrameSequence()` değişikliği alınmadı: gerçek binary handler hâlâ `buffer.length<=headerLength` kontrolünü yaptığı için bu değişiklik tek başına sıfır-byte final chunk sorununu çözmüyor. Çalışan V20 dosya-transfer sunucusuna gereksiz/yarım bir değişiklik eklenmedi.
- V21'de `file_transfer.dart` ve `main_screen.dart` için V20'den farklı bir kaynak kodu değişikliği bulunmadı; bu nedenle sahte bir birleşim yapılmadı.

## V17 — Reliable stale-socket routing and notification queue ACK (2026-09-15)

- Reliable file OFFER routing now rejects sockets marked dead by the server heartbeat (`isAlive === false`) and falls back to the DATA-only HIGH-priority FCM wake-up.
- Reliable file binary/signaling routing also ignores heartbeat-dead sockets, preventing false-success writes during stale WebSocket transitions.
- Terminal `fileTransferFailed` handling now updates the durable message state and routes a terminal failure to both peers; if a peer is offline, the failure is retained in the pending signaling queue for reconnect delivery.
- Native Android notification queue changed from pop-before-store to peek-then-ack. Dart acknowledges an item only after durable local storage succeeds.
- Dart pending private-message/file notifications now use a bounded 100-entry queue with identity-based deduplication instead of a single-slot value.
- Background file wake retries were tightened to at most once per 60 seconds, while receiver connection timeout was extended to 180 seconds to tolerate delayed Android/FCM wake-up.
- Added regression assertions for stale-socket routing, terminal failure fan-out, notification queue ACK, bounded notification queue, and wake/timeout timing.
- Android build version bumped to `1.0.8+14`.

## V16 — Reliable file wake-up / stale presence fix (2026-09-14)

- Fixed a transfer-start deadlock when the server's presence state still says `foreground` but the recipient's WebSocket is already gone.
- Reliable file OFFER wake-up now falls back to data-only HIGH-priority FCM whenever no live transfer/foreground socket actually accepted the OFFER.
- The 15-second recovery loop now checks the actual live sockets instead of trusting stale foreground presence, so a missed wake-up can be retried.
- Added a regression assertion covering the stale-presence/no-live-socket path.


## V9 — Reliable transfer protocol hardening (2026-09-13)

- Added durable receiver transfer manifests beside `.part` files with atomic updates.
- Added server-side transfer metadata persistence; file bytes remain RAM-only and are never written by the server.
- Added reconnect resume handshake using the receiver's committed sequence.
- Added sender seek/resume from the authoritative committed sequence after reconnect.
- Added controlled receive-queue failure handling so chunk exceptions cannot leave a transfer silently stuck.
- Added SHA-256 metadata to background file-transfer wake-up data.
- Added 1 GB client/server file-size validation.
- Delayed background queue removal until verified local-file registration completes.
- Preserved existing message delivery, profile-photo, and successful file-preview paths.

# ZeroLog V5 — hardened background transfer and session reliability


## Hardened reliability pass (2026-09-11)
- Background file wake-ups are stored in a durable native queue instead of a single pending-transfer slot; multiple FCM wake-ups no longer overwrite each other.
- A single headless Flutter worker processes queued transfers sequentially, preserving the existing proven single-transfer state machine and foreground chat/photo path.
- The foreground transfer service retains queued metadata across service/process restarts instead of clearing it prematurely.
- Background transfer reconnects keep the server-side reliable session as the source of truth; a transient headless transport exception no longer spins or discards the queued transfer.
- Verified transfer completion remains terminal; delayed failure/signaling events cannot roll a completed transfer back to failed.
- Existing foreground chat, photo preview and normal WebSocket transfer path are intentionally unchanged.

- Presence now follows foreground lifecycle state instead of merely an open WebSocket.
- Background live sockets can receive private messages and acknowledge delivery.
- Terminated/background FCM private-message delivery now sends a token-authenticated native delivery receipt.
- Background file OFFERs retain an FCM wake-up path and duplicate ACCEPT races cannot steal the transfer socket.
- File relay throughput increased to 64 KiB frames with a 64-frame send window and 16-frame ACK cadence.
- Server still relays file bytes only; file contents are never persisted server-side.

## 1.1.1+16 — Final reliability pass (2026-09-08)
- Dosya/fotoğraf aktarımı kimliği doğrulanmış WebSocket + ZLF2 binary chunk protokolüne taşındı; WebRTC DataChannel dosya aktarımı kullanılmıyor.
- Gönderici END bildirimi alıcıya aktarılıyor; alıcı gerçek `.part` dosyasını boyut + SHA-256 ile doğrulayıp `fileTransferComplete` ile sunucuya onaylıyor.
- END/COMPLETE kaybı için idempotent retry ve reconnect desteği eklendi; sunucu terminal transfer durumunu kısa süre koruyor.
- Uygulama kapalı/arka plandayken DATA-only FCM ile transfer servisi uyandırılıyor; FCM reserved `from` anahtarı kullanılmıyor.
- Background transfer socket'i presence/online durumunu değiştirmiyor.
- Dosya mesajı ile gerçek binary transfer durumu birbirinden ayrıldı; sohbet geçmişi tamamlanmış transferi doğru şekilde gösterebiliyor.
- Kamera/galeri fotoğrafları transfer başlamadan önce kalıcı kopyaya alınıyor; geçici picker dosyası kaybolsa bile aktarım etkilenmiyor.
- Mesaj okundu tiki ZeroLog için çift yeşil olarak gösteriliyor.
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

# ZeroLog 1.0.8+13

## Fixes in this release

- File transfer offers now use foreground/background-aware delivery: background recipients are queued and receive an FCM file notification instead of silently consuming the offer through a still-open WebSocket.
- Incoming/background WebRTC file transfers start the Android foreground transfer service before peer/output preparation.
- Main screen now acknowledges private messages as **delivered** when they reach the device while the chat is not open. Read receipts remain the responsibility of the active private chat, restoring the intended single-tick → double-tick → green double-tick lifecycle.
- Profile cache now removes case-variant stale entries so a fresh `profileUpdated` event cannot be shadowed by an older differently-cased cache key.
- Existing profile revision/ACK handling remains authoritative; server confirmation continues to control successful profile-save completion.


## 2026-09-13 — Large-file / document transfer hardening

- Increased reliable WebSocket file chunks to 128 KiB and kept a bounded 64-frame sender window.
- Increased transfer/session timeouts so large files are not failed merely because a 40 MB transfer takes longer than five minutes.
- Kept server file contents memory-only; the relay does not persist file bytes to disk.
- File picker now supports Android SAF/cloud files without a local filesystem path by streaming the selected file into ZeroLog's local send staging file.
- Single-file selection now uses `FilePicker.pickFile()` to avoid multi-selection ambiguity.
- Throttled transfer UI updates and removed per-chunk chat auto-scroll to reduce UI work during large transfers.
- Chat auto-focus now defaults to off; when the keyboard opens, the private chat scrolls to the newest messages after the resize settles.

- Extended ACK/reconnect tolerance for large transfers and fixed session restore so account-in-use/maintenance/auth failures no longer open MainScreen as if the session were valid.
- Background transfer completion now cancels the exact FCM file notification when its durable queue item is removed.

- V7 integrity hardening: background transfer queue items are removed only after a real terminal state; observation timeout no longer discards an active transfer.
- Background transfer inactivity/completion windows are extended without changing the normal foreground transfer timeout.
- Reliable file relay pending-chunk buffer restored to 128 bounded in-memory chunks; file contents remain non-persistent.

## 2026-09-13 V7 final audit

- File-transfer FCM wake-up is DATA-ONLY so Android invokes `onMessageReceived()` while the app process is backgrounded/terminated; the foreground transfer service owns the persistent notification.
- Private chat no longer auto-focuses the composer on open, preventing the IME from covering the newest messages.
- Preserved bounded 128 KiB WebSocket chunks, durable background queue, 30-minute worker observation, and terminal-only queue removal.
## V14 — File notification single-authority repair

- Native Android FCM is the single owner of private file-transfer notifications.
- Foreground Dart `onMessage` no longer creates a duplicate file notification.
- Native OFFER and `privateFileStored` notifications use the same stable notification ID, allowing completion to replace the active transfer notification.
- File-transfer FCM remains data-only/high-priority so the native callback can wake the background transfer service.



## V15 notification reliability repair
- Native FCM is the sole authority for private-message notifications.
- Pending native message/file notification queue is drained in one bounded pass.
- Busy call invites are explicitly rejected instead of being silently dropped.
- Added notification architecture regression tests.

## V18 — Terminal failure reliability and auth hardening (2026-09-15)

- Retained failed file-transfer sessions for a short terminal TTL and added per-peer failure ACK/replay across reconnects.
- Propagated the actual failure reason to the sender UI.
- Added login rate limiting keyed by remote IP and normalized username.
- Corrected the login privacy text: ZeroLog currently provides TLS/WSS transport encryption, not end-to-end encryption.
- Kept the server file relay content-free; file bytes are not persisted by the server.

## V22 callback/reconnect hardening

- FileTransfer callback registration now uses per-owner handles and a callback multiplexer, so a second UI observer no longer overwrites the first observer's progress/offer/status callbacks.
- PrivateChat disposes only its own callback registration instead of clearing callbacks owned by another screen.
- The existing WebSocket transport is intentionally kept as the `WsClient` singleton; reconnect replaces its internal channel rather than the FileTransfer transport reference. No raw WebSocket reconnect change is required.
