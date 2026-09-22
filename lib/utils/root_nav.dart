import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

/// Alt menu sekmeleri arasinda gecis ve Ayarlar sayfasini acma.
///
/// Alt menude 4 sekme var (Bugun, Gecmis, Basarilar, Rota).
/// Su takibi Bugun sayfasindaki halkanin sag ustundeki "Su" dugmesiyle
/// ayri sayfa olarak acilir.
/// Istatistik sekmesi Gecmis'e birlestirildi.
/// Ayarlar alt menuden cikarildi; Bugun sayfasinin sag ustundeki disli
/// ikonundan ayri sayfa olarak acilir.
class RootNav {
  static const home = 0;
  static const history = 1;
  static const achievements = 2;
  static const route = 3;

  static final tab = ValueNotifier<int>(home);

  /// Ayarlar sayfasini herhangi bir yerden acmak icin (MaterialApp'e bagli).
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Her artista acik Ayarlar sayfasi "Gunluk hedef" bolumune kayar.
  static final goalFocus = ValueNotifier<int>(0);

  static void go(int index) {
    // Ustte acik bir sayfa (or. Ayarlar) varsa once kapanir.
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    tab.value = index;
  }

  static Future<void> openSettings({bool focusGoal = false}) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(focusGoal: focusGoal),
      ),
    );
  }

  /// Bugun > "Hedefe ... kaldi" kartindan: Ayarlar'i acip hedefe kayar.
  static void focusGoal() => openSettings(focusGoal: true);
}
