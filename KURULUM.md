# Adım Sayar - Kurulum

## 1. Flutter iskeletini oluştur (bir kez)

VS Code terminalinde (PowerShell):

```powershell
cd C:\Flutter_Projects
flutter create --org com.ismail --project-name adim_sayar --platforms android adim_sayar_tmp
```

`adim_sayar_tmp` içindeki `android`, `.gitignore`, `analysis_options.yaml` klasör/dosyalarını
`C:\Flutter_Projects\adim_sayar` içine kopyala, sonra `adim_sayar_tmp` klasörünü sil.
**Dikkat:** `android\app\src\main\AndroidManifest.xml` dosyasının üzerine yazma -
hazır olan (izinleri içeren) sürüm zaten projede duruyor.

Alternatif (daha kısa): doğrudan `C:\Flutter_Projects\adim_sayar` içinde

```powershell
cd C:\Flutter_Projects\adim_sayar
flutter create --org com.ismail --project-name adim_sayar --platforms android .
```

Bu komut eksik platform dosyalarını üretir, `lib/` ve `pubspec.yaml` üzerine yazmaz.
Sadece `AndroidManifest.xml` değişirse dosyayı geri alman gerekir (git yoksa önce yedekle).

## 2. Paketleri kur

```powershell
flutter pub get
```

Sürüm çakışması olursa:

```powershell
flutter pub add provider pedometer permission_handler shared_preferences
```

## 3. Telefonda dene

USB hata ayıklama açık, telefon bağlıyken:

```powershell
flutter devices
flutter run
```

## 4. APK al

```powershell
flutter build apk --release
```

Çıktı: `build\app\outputs\flutter-apk\app-release.apk`
Tek cihaz için daha küçük dosya:

```powershell
flutter build apk --release --split-per-abi
```

`app-arm64-v8a-release.apk` dosyasını telefona at ve kur.

## Notlar

- İlk açılışta "Fiziksel aktivite" izni istenir; reddedilirse ana ekranda uyarı çıkar.
- Android sensörü cihaz açılışından beri toplam adımı verir; uygulama günlük farkı
  hesaplayıp `SharedPreferences` içine yazar. Telefon yeniden başlatılırsa sayaç
  sıfırlandığı için baseline otomatik güncellenir.
- Uygulama kapalıyken de sistem sensörü saymaya devam eder; uygulama açıldığında
  fark okunup güne eklenir.
- Veriler yalnızca cihazda tutulur, internet izni yok.
