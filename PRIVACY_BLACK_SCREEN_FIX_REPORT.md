# Gizlilik Ekranı Siyah Ekran Düzeltme Raporu

**Tarih:** 5 Ekim 2026  
**İncelenen kaynak:** Kullanıcının son eklediği `matrix-zero-app-main(22).zip`

## Bulunan kök nedenler

1. **İç içe Navigator’ların HeroController çakışması:** `AppLockGate`, kilit ekranı için uygulamanın Navigator’ına paralel ikinci bir `Navigator` açıyordu. Bu Navigator, ana Navigator’ın `HeroController`’ını miras alabiliyordu. Flutter aynı HeroController’ın birden fazla Navigator tarafından kullanılmasına izin vermediğinden `A HeroController can not be shared by multiple Navigators` hatası oluşuyor; doğrulamadan sonra arayüz boş/siyah ekranda kalabiliyordu.
2. **PIN alanının controller’ı geç dispose ediliyordu:** PIN dialogu kapatılınca `showDialog` sonucu, çıkış animasyonu ve overlay tamamen kaldırılmadan dönebiliyordu. Metin alanı hâlâ yeniden oluşturulurken `TextEditingController` dispose edilmiş olduğundan `TextEditingController was used after being disposed` hatası oluşabiliyordu.

## Yapılan düzeltmeler

- Kilit katmanındaki Navigator `HeroControllerScope.none` ile izole edildi. Kilit overlay’i artık ana Navigator’ın HeroController’ını paylaşmıyor.
- PIN oluşturma ve PIN doğrulama dialogları `DialogRoute.completed` tamamlanana kadar bekliyor. Böylece dialog içindeki controller’lar overlay kaldırılmadan dispose edilmiyor.
- Uygulama kilidini PIN ile açma, gizlilik merkezine PIN ile girme ve gizlilik ekranını kapatıp tekrar açma akışları için widget testi eklendi.
- Parmak izi akışı; `AppLockGate` açıkken, Android biyometri penceresinin uygulamayı `inactive/hidden/paused` durumlarına geçirip geri döndürmesi simüle edilerek test edildi.

## Doğrulama

- `flutter analyze --no-pub`: **temiz — No issues found**.
- `flutter test --no-pub`: **91 test geçti**.
- Yeni PIN tekrar-giriş ve biyometri/lifecycle widget testleri de bu test paketine dahil ve **geçti**.

## APK sınırı

Bu sandbox’ta Android SDK/`android.jar` bulunmadığı için düzeltilmiş kaynaklardan APK derleyemedim. Parmak izi widget testi `local_auth` platformunu mock’lar ve lifecycle olaylarını simüle eder; fiziksel Android cihazdaki parmak izi donanımında son APK testi bu doğrulamaya dahil değildir. Sonraki adım olarak bu kaynak ZIP’inden APK’yı Android SDK bulunan ortamda derleyip cihazda PIN ve parmak iziyle tekrar giriş test edilmelidir.
