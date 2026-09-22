import 'dart:math' as math;

import 'metrics.dart';

/// Tempo kaydi: native servis her tamamlanan dakikanin adim sayisindan
/// (kadans) o dakikayi normal / tempolu / kosu olarak siniflandirir.
///
/// Gun basina 5 deger tutulur:
///   [normalDk, tempoluAdim, tempoluDk, kosuAdim, kosuDk]
/// Normal adim ayrica tutulmaz: gunun toplami - tempolu - kosu. Boylece
/// siniflandirilamayan her adim (uygulama kapaliyken servis yoksa, toplu
/// teslim, dur-kalk) normal sayilir ve toplam gunluk adimla hep tutarli kalir.
class Intensity {
  static const walkMin = 0;
  static const briskSteps = 1;
  static const briskMin = 2;
  static const runSteps = 3;
  static const runMin = 4;
  static const length = 5;

  /// Esikler ve formuller [Metrics]'te; buradakiler kisayol.
  static const briskMinCadence = Metrics.briskMinCadence;
  static const runMinCadence = Metrics.runMinCadence;
  static double runStrideMeters(int heightCm) =>
      Metrics.runStrideMeters(heightCm);

  /// Gecersiz kaydi eler; negatifleri sifirlar.
  static List<int>? sanitize(Object? v) {
    if (v is! List || v.length != length) return null;
    final out = <int>[];
    for (final e in v) {
      if (e is! num) return null;
      final n = e.toInt();
      out.add(n < 0 ? 0 : n);
    }
    return out;
  }

  static Map<String, List<int>> decodeMap(Object? raw) {
    final out = <String, List<int>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final key = k.toString();
      if (!Metrics.isValidKey(key)) return;
      final arr = sanitize(v);
      if (arr != null) out[key] = arr;
    });
    return out;
  }

  /// Ayni gunun iki kopyasi: her alan icin buyuk olan (servis sayaclari
  /// yalnizca artar).
  static List<int> mergeMax(List<int> a, List<int> b) =>
      List<int>.generate(length, (i) => math.max(a[i], b[i]));

  static double briskMet(double cadence, int heightCm) =>
      Metrics.briskMet(cadence, heightCm);
  static double runMet(double cadence, int heightCm) =>
      Metrics.runMet(cadence, heightCm);
}

class ActivityPart {
  final int steps;
  final int minutes;
  final double km;
  final double kcal;

  const ActivityPart({
    required this.steps,
    required this.minutes,
    required this.km,
    required this.kcal,
  });

  static const zero = ActivityPart(steps: 0, minutes: 0, km: 0, kcal: 0);
}

/// Bir gun / donem icin normal, tempolu ve kosu kirilimi.
class ActivityBreakdown {
  final ActivityPart normal;
  final ActivityPart brisk;
  final ActivityPart run;

  /// Donemde tempo kaydi olan en az bir gun var mi.
  final bool hasData;

  const ActivityBreakdown({
    required this.normal,
    required this.brisk,
    required this.run,
    required this.hasData,
  });

  int get steps => normal.steps + brisk.steps + run.steps;
  int get minutes => normal.minutes + brisk.minutes + run.minutes;
  double get km => normal.km + brisk.km + run.km;
  double get kcal => normal.kcal + brisk.kcal + run.kcal;

  /// [totalSteps] donemin tum adimlari; tempolu/kosu degerleri zaten
  /// gun bazinda toplama kirpilmis olarak gelir.
  ///
  /// Tempo kaydi yoksa sonuc eski hesapla birebir aynidir (tum adimlar
  /// normal, [activeMin] varsa gercek sure).
  static ActivityBreakdown compute({
    required int totalSteps,
    required int briskSteps,
    required int briskMin,
    required int runSteps,
    required int runMin,
    required bool hasData,
    required int heightCm,
    required double weightKg,
    int? activeMin,
  }) {
    final h = heightCm;
    final w = weightKg;
    if (!hasData || (briskSteps <= 0 && runSteps <= 0)) {
      return ActivityBreakdown(
        normal: ActivityPart(
          steps: totalSteps,
          minutes: activeMin ?? Metrics.activeMinutes(totalSteps),
          km: Metrics.distanceKm(totalSteps, h),
          kcal: Metrics.kcal(totalSteps, h, w, activeMin: activeMin),
        ),
        brisk: ActivityPart.zero,
        run: ActivityPart.zero,
        hasData: hasData,
      );
    }

    final rs = runMin > 0 ? runSteps : 0;
    final bs = briskMin > 0 ? briskSteps : 0;
    final normalSteps = math.max(0, totalSteps - bs - rs);

    // Normal yuruyusun suresi: saatlik kayittan gelen toplam sureden
    // tempolu/kosu dakikalari dusulur; 60-130 adim/dk araligina sigmazsa
    // (kapsama eksik) tahmine dusulur.
    int? normalMin;
    if (activeMin != null && normalSteps > 0) {
      final rest = activeMin - briskMin - runMin;
      final lo = (normalSteps / 130).ceil();
      final hi = (normalSteps / 60).ceil();
      if (rest >= lo && rest <= hi) normalMin = rest;
    }

    ActivityPart brisk = ActivityPart.zero;
    if (bs > 0) {
      final cad = bs / briskMin;
      brisk = ActivityPart(
        steps: bs,
        minutes: briskMin,
        km: Metrics.distanceKm(bs, h),
        kcal: Metrics.briskMet(cad, h) * w * briskMin / 60,
      );
    }

    ActivityPart run = ActivityPart.zero;
    if (rs > 0) {
      final cad = rs / runMin;
      run = ActivityPart(
        steps: rs,
        minutes: runMin,
        km: rs * Metrics.runStrideMeters(h) / 1000,
        kcal: Metrics.runMet(cad, h) * w * runMin / 60,
      );
    }

    return ActivityBreakdown(
      normal: ActivityPart(
        steps: normalSteps,
        minutes: normalMin ?? Metrics.activeMinutes(normalSteps),
        km: Metrics.distanceKm(normalSteps, h),
        kcal: Metrics.kcal(normalSteps, h, w, activeMin: normalMin),
      ),
      brisk: brisk,
      run: run,
      hasData: true,
    );
  }
}
