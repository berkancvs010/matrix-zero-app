# ZeroLog — Final Audit Report
Date: 2026-10-05

## Old reminder report — line-by-line verification

1. Lock-screen incoming call / screen wake
   - Native FCM owns the single incoming-call notification and ringtone.
   - Foreground suppression checks both process state and Keyguard state, so a locked device is not treated as ordinary foreground.
   - CALL notification uses CATEGORY_CALL, MAX priority, PUBLIC visibility and full-screen intent.
   - MainActivity / IncomingCallActivity explicitly use SHOW_WHEN_LOCKED and TURN_SCREEN_ON.
   - Android 14+ full-screen-intent permission is checked and the system permission page is opened when needed.
   - Result: code path is present and internally consistent. Device/OEM behavior still requires physical APK testing; this audit does not claim that every Xiaomi/Android build can be guaranteed.

2. Chats stuck on “Bağlantı yeniden kuruluyor…” after cold start
   - WebSocket connections use a generation token so stale socket callbacks cannot overwrite a newer connection.
   - Reconnect scheduling is centralized and retries with bounded backoff.
   - socket close has a 2-second timeout so a dead socket cannot block the next connection indefinitely.
   - MainScreen checks the authoritative WsClient.connected state before displaying the reconnect banner.
   - Successful authentication emits connectionRestored and restores active rooms / directory state.
   - Result: the reported permanent-banner failure path is addressed in source.

3. PIN lock “Kilidi aç” behavior
   - The first complete 6-digit PIN entry auto-submits.
   - After a failed attempt, automatic submission is disabled; the next attempt requires keyboard submit or the on-screen Doğrula button.
   - Verification is serialized so duplicate onChanged/onSubmitted races cannot create double attempts.
   - Result: requested behavior is implemented.

4. Call accepted but WebRTC remains stuck
   - A connection watchdog starts immediately after acceptance, before SDP offer availability.
   - A 45-second global connection timeout terminates a call that never connects.
   - Failed/disconnected WebRTC state receives a 12-second recovery grace period before termination.
   - Signaling disconnect terminates the local call instead of leaving stale call UI.
   - callEnd is sent before slow native/WebRTC cleanup.
   - Result: the reported indefinite “connecting” path is bounded and cleaned up.

## Additional issue found during this audit and fixed
- Native cold-start incoming-call state now preserves the `video` flag when the full-screen intent is persisted and later read. This prevents a cold-start video-call intent from losing its original media mode.

## Retro audit
- 9 distinct offline games are present.
- Breakout now has actual brick state/collision handling and receives the virtual gamepad visibility state.
- Pong reset direction is calculated before resetting the ball position.
- Snake food placement uses a finite available-cell list instead of a potentially infinite random loop.
- Space Shooter consumes a shot/enemy pair only once per tick.
- Tetris contains seven tetrominoes and a real game-over state.
- 2048 and Minesweeper protect terminal states.
- Virtual gamepad actions are concrete and game-specific.

## Static verification performed
- ZIP extraction and source-tree inspection: PASS.
- No APK/AAB included in final source package: PASS.
- server/package.json JSON parse: PASS.
- server/server.js `node --check`: PASS.
- Android XML parse: PASS.
- Regression-test source checks updated for the audited behaviors.
- ZIP integrity will be verified with `unzip -t` after packaging.

## Limitation
Flutter SDK is not installed in this analysis container, so `flutter analyze`, `flutter test`, and `flutter build apk` cannot honestly be marked PASS here. The source is prepared for the VDS/GitHub Actions Flutter 3.44.0 verification step.
