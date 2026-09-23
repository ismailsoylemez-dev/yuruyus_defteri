import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'providers/step_provider.dart';
import 'providers/water_provider.dart';
import 'screens/auth_gate.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/prefs_service.dart';
import 'theme/app_theme.dart';
import 'utils/root_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}

  if (!kIsWeb) await NotificationService.init();

  // Yapilandirma android/app/google-services.json dosyasindan okunur; web
  // icin ayri bir yapilandirma tanimli olmadigindan orada atlanir.
  // Hazir degilse uygulama bulutsuz (yalniz cihaz) modda acilir.
  var firebaseReady = false;
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase baslatilamadi: $e');
    }
  }
  AuthService.available = firebaseReady;

  final prefs = await PrefsService.create();

  // Kayitli tema secimi (varsayilan koyu).
  ThemeController.init(ThemeController.parse(prefs.themeMode));
  if (AppColors.isLight || AppColors.isAmoled) applySystemUiStyle();

  // Planli bildirimler cihaz yeniden baslatildiginda veya uygulama
  // guncellendiginde dusebilir; acik olanlar her acilista yeniden kurulur.
  if (!kIsWeb) {
    if (prefs.notifyEvening) await NotificationService.scheduleEvening();
    if (prefs.notifyWeekly) await NotificationService.scheduleWeekly();
  }

  runApp(AdimSayarApp(prefs: prefs, firebaseReady: firebaseReady));
}

class AdimSayarApp extends StatelessWidget {
  final PrefsService prefs;
  final bool firebaseReady;

  const AdimSayarApp({
    super.key,
    required this.prefs,
    this.firebaseReady = true,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ChangeNotifierProvider(create: (_) => StepProvider(prefs)),
        ChangeNotifierProvider(create: (_) => WaterProvider(prefs)),
      ],
      child: ValueListenableBuilder<AppThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, _, __) => MaterialApp(
        navigatorKey: RootNav.navigatorKey,
        title: 'Yürüyüş Defteri',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        // Tarih secici, takvim ve sistem pencereleri Turkce.
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Sistem yazi boyutu cok buyutulurse kartlar tasmasin.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
          child: child!,
        ),
        home: !prefs.introShown
            ? OnboardingScreen(prefs: prefs, firebaseReady: firebaseReady)
            : (firebaseReady ? AuthGate(prefs: prefs) : const RootScreen()),
        ),
      ),
    );
  }
}
