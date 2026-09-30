# matrix_zero

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Play Store release

- Privacy policy: https://zerolog.giize.com/privacy
- Account and data deletion: https://zerolog.giize.com/delete-account
- Production Android target: API 36.
- Play release artifact: Android App Bundle (`.aab`).

### GitHub Actions signing secrets

The release workflow expects these GitHub repository secrets:

- `ZEROLOG_UPLOAD_KEYSTORE_B64` — base64-encoded production upload keystore.
- `ZEROLOG_UPLOAD_STORE_PASSWORD`
- `ZEROLOG_UPLOAD_KEY_ALIAS`
- `ZEROLOG_UPLOAD_KEY_PASSWORD`

The keystore and `android/key.properties` are intentionally not stored in Git.
