# ZeroLog 1.0.7+7 — Release Candidate

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
