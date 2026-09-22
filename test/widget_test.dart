import 'package:flutter_test/flutter_test.dart';

import 'package:adim_sayar/utils/metrics.dart';

void main() {
  test('adim -> mesafe ve kalori hesabi', () {
    // 172 cm boy icin adim uzunlugu ~71.4 cm
    expect(Metrics.strideMeters(172), closeTo(0.714, 0.001));
    expect(Metrics.distanceKm(10000, 172), closeTo(7.138, 0.01));
    // stepsPerMinute 100 iken 542 kcal cikiyordu; sabit 110'a alininca
    // bu beklenti guncellenmemis ve test kirilmisti.
    // 10000 adim -> 91 dk -> ~4.7 km/sa -> 3.5 MET -> ~494 kcal
    expect(Metrics.kcal(10000, 172, 93).round(), closeTo(494, 3));
  });

  test('sure bicimi', () {
    expect(Metrics.duration(45), '45 dk');
    expect(Metrics.duration(60), '1 sa');
    expect(Metrics.duration(134), '2 sa 14 dk');
  });

  test('binlik ayirici', () {
    expect(Metrics.thousands(8240), '8.240');
    expect(Metrics.thousands(1398305), '1.398.305');
  });

  test('gun anahtari ve cozumleme', () {
    final d = DateTime(2026, 9, 20);
    expect(Metrics.dayKey(d), '2026-09-20');
    expect(Metrics.parseKey('2026-09-20'), d);
  });

  test('hafta pazartesiden baslar', () {
    // 20 Eylul 2026 pazar -> hafta basi 14 Eylul pazartesi
    expect(Metrics.weekStart(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
  });
}
