import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Giris hatalarinin kullaniciya gosterilebilir hali.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Google hesabi ile Firebase Authentication.
///
/// Oturum Firebase tarafindan cihazda kalici saklanir; uygulama her acildiginda
/// tekrar giris istenmez. Sadece uygulama silinir veya cihaz degisirse
/// bir kez hesap secimi gerekir.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Firebase konsolunda Google saglayicisi acilinca olusan "Web client ID".
  /// Bos birakilirsa eklenti google-services.json'dan uretilen
  /// `default_web_client_id` kaynagini kullanir; normalde bos kalmali.
  static const String serverClientId = '';

  /// [Firebase.initializeApp] basarili oldu mu. main() tarafindan yazilir.
  /// false iken FirebaseAuth'a dokunmak [core/no-app] firlatir, bu yuzden
  /// asagidaki erisimlerin hepsi bu bayragi kontrol eder.
  static bool available = false;

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _initialized = true;
  }

  Stream<User?> get authState {
    if (!available) return Stream<User?>.value(null);
    return FirebaseAuth.instance.authStateChanges();
  }

  User? get currentUser {
    if (!available) return null;
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Ekran acmadan, daha once verilmis izinle sessiz giris dener.
  /// Basarisiz olursa sessizce gecilir; kullanici butonla girer.
  Future<void> trySilentSignIn() async {
    if (!available || currentUser != null) return;
    try {
      await _ensureInit();
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account != null) await _linkToFirebase(account);
    } catch (_) {
      // Yoksay.
    }
  }

  /// Kullanici butona bastiginda calisir. Iptal edilirse null doner.
  Future<User?> signInWithGoogle() async {
    if (!available) {
      throw const AuthFailure(
        'Bulut yedekleme bu platformda kullanılamıyor.',
      );
    }
    try {
      await _ensureInit();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const AuthFailure(
          'Bu platformda Google ile giris desteklenmiyor.',
        );
      }
      final account = await GoogleSignIn.instance.authenticate();
      return await _linkToFirebase(account);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthFailure(_mapGoogleError(e));
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  Future<User?> _linkToFirebase(GoogleSignInAccount account) async {
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure(
        'Kimlik dogrulanamadi. Firebase konsolunda SHA-1 parmak izinin '
        'ekli oldugundan emin ol.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result =
        await FirebaseAuth.instance.signInWithCredential(credential);
    return result.user;
  }

  Future<void> signOut() async {
    if (!available) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google tarafi temizlenemese de Firebase oturumu kapatilir.
    }
    await FirebaseAuth.instance.signOut();
  }

  String _mapGoogleError(GoogleSignInException e) {
    return switch (e.code) {
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Firebase yapilandirmasi eksik: google-services.json ve SHA-1 kontrol et.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Istemci yapilandirmasi hatali. Paket adi ve Web client ID uyusmuyor.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Giris ekrani acilamadi. Google Play Hizmetleri guncel mi?',
      _ => 'Google girisi basarisiz oldu (${e.code.name}).',
    };
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    return switch (e.code) {
      'network-request-failed' => 'Internet baglantisi yok.',
      'account-exists-with-different-credential' =>
        'Bu e-posta baska bir yontemle kayitli.',
      'operation-not-allowed' =>
        'Google saglayicisi Firebase konsolunda acik degil.',
      'invalid-credential' => 'Kimlik bilgisi gecersiz veya suresi dolmus.',
      _ => 'Giris basarisiz oldu (${e.code}).',
    };
  }
}
