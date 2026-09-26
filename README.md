# Yürüyüş Defteri 🚶‍♂️

Yürüyüş Defteri, açık kaynaklı, reklamsız ve gizliliğe önem veren kişisel bir adım sayar ve yürüyüş takip uygulamasıdır. Sağlıklı bir yaşam için günlük adımlarınızı takip ederken, aynı zamanda harita üzerinden yürüyüş rotalarınızı da kaydedebilirsiniz.

## 🌟 Özellikler

- **Gelişmiş Adım Sayar:** Cihaz sensörlerini (Pedometer) kullanarak doğru ve tutarlı adım sayımı.
- **Rota Takibi:** `flutter_map` ve `Geolocator` entegrasyonu ile yürüyüşlerinizi harita üzerinde canlı takip edip kaydedebilirsiniz (Google API Anahtarı gerektirmez).
- **Reklamsız Deneyim:** Hiçbir reklam veya dikkat dağıtıcı öğe olmadan sade, temiz kullanım.
- **Firebase Entegrasyonu:** Google Sign-in ile kolay giriş, Firestore ile güvenli bulut senkronizasyonu.
- **Home Widget:** Ana ekranınızda günlük adımlarınızı anlık olarak takip edebileceğiniz widget desteği.
- **Paylaşım Özelliği:** Yürüyüş verilerinizi ve başardığınız hedefleri şık bir kart tasarımı (screenshot & share_plus) ile arkadaşlarınızla paylaşın.
- **Yerel Bildirimler:** Hedefinize ulaştığınızda ve günlük motivasyon uyarılarıyla haberdar olun.
- **Insights & Isı Haritası:** Adım verilerinizin geçmişe dönük istatistikleri ve GitHub benzeri katkı/ısı haritası.

## 📱 Ekran Görüntüleri

Proje ekran görüntülerini incelemek için aşağıdaki önizlemelere göz atabilirsiniz:

| Ana Ekran (Adım Sayar) | Rota Takibi | İstatistikler (Heatmap) | Paylaşım / Profil |
| :---: | :---: | :---: | :---: |
| <img src="screenshots/home.png" width="200" alt="Ana Ekran"> | <img src="screenshots/route.png" width="200" alt="Rota Takibi"> | <img src="screenshots/heatmap.png" width="200" alt="İstatistikler"> | <img src="screenshots/profile.png" width="200" alt="Profil"> |

> *Not: Ekran görüntülerini eklemek için uygulamanızdan aldığınız görüntüleri `screenshots` klasörüne aynı isimlerle (örneğin `home.png`, `route.png`) kaydediniz.*

## 🛠 Kullanılan Teknolojiler

- **[Flutter](https://flutter.dev/):** Cross-platform UI geliştirme kiti.
- **[Provider](https://pub.dev/packages/provider):** State (Durum) yönetimi.
- **[Firebase Auth & Firestore](https://firebase.google.com/):** Arka uç, kimlik doğrulama ve veritabanı.
- **[Pedometer](https://pub.dev/packages/pedometer):** Cihaz sensöründen adım verisi okuma.
- **[Flutter Map](https://pub.dev/packages/flutter_map) & [Geolocator](https://pub.dev/packages/geolocator):** Harita gösterimi ve konum alma.
- **[Home Widget](https://pub.dev/packages/home_widget):** Android ve iOS için ana ekran widget geliştirmesi.

## 🚀 Başlangıç ve Kurulum

Bu projeyi kendi ortamınızda çalıştırmak için aşağıdaki adımları izleyin:

1. Depoyu klonlayın:
   ```bash
   git clone https://github.com/ismailsoylemez-dev/yuruyus_defteri.git
   ```
2. Proje dizinine gidin:
   ```bash
   cd yuruyus_defteri
   ```
3. Bağımlılıkları yükleyin:
   ```bash
   flutter pub get
   ```
4. Firebase Kurulumu:
   - Projenin `FIREBASE_KURULUM.md` dosyasındaki talimatları izleyerek kendi Firebase projenizi bağlayın (`google-services.json` vb.).
5. Uygulamayı çalıştırın:
   ```bash
   flutter run
   ```

## 📜 Lisans

Bu proje kişisel kullanım amacıyla açık kaynak olarak sunulmuştur. Katkıda bulunmak isterseniz bir PR (Pull Request) oluşturabilirsiniz.
