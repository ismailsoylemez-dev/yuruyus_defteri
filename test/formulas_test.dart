import 'package:flutter_test/flutter_test.dart';

import 'package:yuruyus_defteri/utils/intensity.dart';
import 'package:yuruyus_defteri/utils/metrics.dart';

/// Formul referans degerleri. Ayni sayilar native tarafta
/// android/app/src/main/kotlin/com/ismail/adim_sayar/Formulas.kt ile de
/// cikmali; Dart ya da Kotlin formulu degisirse bu test ve Kotlin birlikte
/// guncellenmeli.
void main() {
  test('normal yuruyus: 10.000 adim, 172 cm, 93 kg', () {
    expect(Metrics.distanceKm(10000, 172), closeTo(7.138, 1e-9));
    expect(Metrics.kcal(10000, 172, 93), closeTo(493.675, 1e-6));
  });

  test('tempolu ve kosu MET', () {
    expect(Metrics.briskMet(120, 172), closeTo(5.0, 1e-9));
    expect(Metrics.runMet(150, 172), closeTo(10.14057, 1e-4));
    // Intensity kisayollari ayni sonucu verir.
    expect(Intensity.briskMet(120, 172), Metrics.briskMet(120, 172));
    expect(Intensity.runMet(150, 172), Metrics.runMet(150, 172));
  });

  test('kirilim: 10.000 adim (3.000 tempolu/25 dk, 1.500 kosu/10 dk)', () {
    final bd = ActivityBreakdown.compute(
      totalSteps: 10000,
      briskSteps: 3000,
      briskMin: 25,
      runSteps: 1500,
      runMin: 10,
      hasData: true,
      heightCm: 172,
      weightKg: 93,
    );
    expect(bd.km, closeTo(7.6669, 1e-6));
    expect(bd.kcal, closeTo(622.17886, 1e-4));
    expect(bd.minutes, 85);
  });
}
