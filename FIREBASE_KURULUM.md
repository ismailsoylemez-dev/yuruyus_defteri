# Firebase kurulumu (Google ile giriş + bulut yedek)

Kod hazır. Bu adımlar tamamlanmadan `flutter run` derleme/çalışma hatası verir.

## 1. Firebase projesi

console.firebase.google.com → **Proje ekle** → ad: `adim-sayar` → Analytics kapatılabilir.

## 2. Google sağlayıcısını aç

Build → Authentication → Get started → **Google** → Etkinleştir → destek e-postası seç → Kaydet.

## 3. Firestore

Build → Firestore Database → Create database → konum **eur3 (europe-west)** → **Production mode**.
Rules sekmesine bu depodaki `firestore.rules` içeriğini yapıştır → Publish.

## 4. SHA parmak izleri

```powershell
cd $env:USERPROFILE\.android
keytool -list -v -keystore debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Çıktıdaki **SHA1** ve **SHA256** değerlerini Firebase → Proje ayarları → Android uygulaması → *Parmak izi ekle* ile gir.
Paket adı: `com.ismail.adim_sayar`

> Bu adım atlanırsa giriş hata vermeden başarısız olur (`idToken` null döner).

## 5. google-services.json

Firebase konsolundan indir → `android/app/google-services.json` konumuna koy.
Dosya `.gitignore` içinde; depoya gönderilmez.

Alternatif (otomatik):

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
cd C:\Flutter_Projects\adim_sayar
flutterfire configure
```

## 6. Çalıştır

```powershell
flutter clean
flutter pub get
flutter run
```

---

## Veri modeli

```
users/{uid}                -> email, displayName, goal, heightCm, weightKg, updatedAt
users/{uid}/years/{yyyy}   -> days { "2026-09-20": 8421, ... }
users/{uid}/data/steps     -> hourly { "2026-09-20": [24 değer], ... }
```

Geçmiş yıllara bölünür; tek dokümanın 1 MiB sınırı devreye girmez ve her senkronda
yalnızca değişen yıl yazılır — tipik olarak **1 yazma**. Girişte yıl sayısı kadar okuma
yapılır (bugün 1). Spark planın günlük 50.000 okuma / 20.000 yazma sınırının çok altında.

> Eski sürümde geçmiş `data/steps` içinde tutuluyordu. İlk senkronda otomatik olarak
> yıl dokümanlarına taşınır ve eski alan silinir.

## Senkron davranışı

| Olay | Ne olur |
|---|---|
| Adım atılır | Ekranda anında görünür (TYPE_STEP_DETECTOR); kesin toplam STEP_COUNTER olayında yerine geçer |
| Adım sensörü olayı | Yerel kayıt anında; bulut yazması 45 sn kuyruğa alınır |
| Uygulama arka plana alınır | Bekleyen bulut yazması hemen gönderilir |
| Giriş yapılır | Bulut çekilir, yerelle birleştirilir (aynı günde **büyük değer** kazanır), birleşmiş hâli geri yazılır |
| İnternet yok | Firestore yerel önbelleğe yazar, bağlanınca kendi senkronlar |
| Çıkış yapılır | Önce kalan veri gönderilir, sonra oturum kapanır |

## Bilinen sınırlar

- `Hesapsız devam et` seçilirse veri buluta gitmez. Sonradan **Ayarlar → Hesap → Google ile
  giriş yap** ile bağlanabilirsin; o andaki yerel geçmiş buluta yüklenir.
- Hedef/boy/kilo değişikliği bir sonraki adım olayında veya *Şimdi yedekle* ile buluta gider.
