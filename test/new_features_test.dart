import 'package:flutter_test/flutter_test.dart';

import 'package:yuruyus_defteri/services/route_service.dart';
import 'package:yuruyus_defteri/utils/intensity.dart';
import 'package:yuruyus_defteri/utils/metrics.dart';
import 'package:yuruyus_defteri/widgets/week_rings.dart';

/// Yuruyus kaydi bicimleri, GPS adim boyu ve su gizleme.
void main() {
  tearDown(() => Metrics.strideOverrideM = null);

  test('sure ve tempo metinleri', () {
    expect(clockText(754), '12:34');
    expect(clockText(3700), '1:01:40');
    expect(paceText(612), '10:12 /km');
    expect(paceText(null), '-');
  });

  test('GPS adim boyu tum mesafe hesabina uygulanir', () {
    expect(Metrics.distanceKm(1000, 172), closeTo(0.7138, 1e-9));
    Metrics.strideOverrideM = 0.80;
    expect(Metrics.distanceKm(1000, 172), closeTo(0.80, 1e-9));
    expect(Metrics.estimatedStrideMeters(172), closeTo(0.7138, 1e-9));
    Metrics.strideOverrideM = null;
    expect(Metrics.distanceKm(1000, 172), closeTo(0.7138, 1e-9));
  });

  test('su kapaliyken haftalik gun detayinda su yok', () {
    final bd = ActivityBreakdown.compute(
      totalSteps: 5000,
      briskSteps: 0,
      briskMin: 0,
      runSteps: 0,
      runMin: 0,
      hasData: false,
      heightCm: 172,
      weightKg: 93,
    );
    expect(WeekDayDetail.from(steps: 5000, breakdown: bd).waterMl, isNull);
    expect(WeekDayDetail.from(steps: 5000, breakdown: bd, waterMl: 750).waterMl, 750);
  });

  test('yuruyus ozeti tempo', () {
    final w = Workout.fromJson({
      'start': 0,
      'end': 1800000,
      'durationSec': 1800,
      'distanceM': 3000.0,
      'steps': 3900,
      'splits': [590, 1190, 1790],
      'interval': true,
      'rounds': 5,
      'day': '2026-09-22',
    });
    expect(w.paceSecPerKm, 600);
    expect(paceText(w.paceSecPerKm), '10:00 /km');
    expect(w.splits.length, 3);
  });
}
