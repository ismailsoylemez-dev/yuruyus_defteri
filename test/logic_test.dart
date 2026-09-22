import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adim_sayar/providers/step_provider.dart';
import 'package:adim_sayar/services/prefs_service.dart';
import 'package:adim_sayar/utils/aggregate.dart';
import 'package:adim_sayar/utils/metrics.dart';

/// Duzeltilen mantik hatalarinin geri gelmemesi icin regresyon testleri.
/// Calistirmak icin: flutter test test/logic_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String key(DateTime d) => Metrics.dayKey(d);
  final today = DateTime.now();
  final todayKey = key(today);

  Future<StepProvider> buildProvider({
    Map<String, int> history = const {},
    Map<String, List<int>> hourly = const {},
    int goal = 8000,
  }) async {
    SharedPreferences.setMockInitialValues({
      PrefsKeys.goal: goal,
      PrefsKeys.history: _json(history),
      PrefsKeys.hourly: _jsonHourly(hourly),
      PrefsKeys.lastDate: todayKey,
      PrefsKeys.savedToday: history[todayKey] ?? 0,
      PrefsKeys.baseline: -1,
    });
    final prefs = await PrefsService.create();
    return StepProvider(prefs);
  }

  group('Metrics - sure ve kalori', () {
    test('saat basina gurultu esigi: 24 saat x 1 adim aktif sayilmaz', () {
      expect(Metrics.activeMinutesFromHours(List.filled(24, 1)), 0);
      expect(Metrics.activeMinutesFromHours(List.filled(24, 19)), 0);
    });

    test('dolu saat normal tempoya gore hesaplanir', () {
      final hours = List<int>.filled(24, 0);
      hours[8] = 3300; // 110 adim/dk -> 30 dk
      expect(Metrics.activeMinutesFromHours(hours), 30);
    });

    test('bir saat 60 dakikayi asamaz', () {
      final hours = List<int>.filled(24, 0);
      hours[8] = 100000;
      expect(Metrics.activeMinutesFromHours(hours), 60);
    });

    test('eksik sure kaloriyi katlamaz (hiz kirpma)', () {
      const steps = 10000;
      final normal = Metrics.kcal(
        steps,
        172,
        93,
        activeMin: Metrics.activeMinutes(steps),
      );
      // Saatlik kayit yarim kalmis gibi: sure yariya iner.
      final yarim = Metrics.kcal(steps, 172, 93, activeMin: 45);
      expect(yarim, lessThanOrEqualTo(normal * 1.05));
    });

    test('kirpma sinirlari MET tablosuyla tutarli', () {
      // 7.5 km/sa -> kosu kademesine (9.8 MET) gecilmez.
      expect(Metrics.metForSpeed(Metrics.maxSpeedKmh), 7.0);
      expect(Metrics.metForSpeed(Metrics.minSpeedKmh), 2.8);
    });

    test('adim yoksa kalori sifir', () {
      expect(Metrics.kcal(0, 172, 93), 0);
    });
  });

  group('Metrics - tarih yardimcilari', () {
    test('tryParseKey bozuk anahtarda null doner', () {
      expect(Metrics.tryParseKey('2026-13-01'), isNull);
      expect(Metrics.tryParseKey('2026-02-31'), isNull);
      expect(Metrics.tryParseKey('bozuk'), isNull);
      expect(Metrics.tryParseKey('2026-09-20'), DateTime(2026, 9, 20));
    });

    test('daysBetween gun bileseni uzerinden sayar', () {
      expect(Metrics.daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 29)),
          1);
      expect(Metrics.daysBetween(DateTime(2025, 12, 31), DateTime(2026, 1, 1)),
          1);
      expect(Metrics.daysBetween(DateTime(2026, 9, 13), DateTime(2026, 9, 20)),
          7);
    });

    test('weekStart pazartesiyi verir', () {
      expect(Metrics.weekStart(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
      expect(Metrics.weekStart(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
    });

    test('addDays takvim aritmetigi', () {
      expect(Metrics.addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });
  });

  group('Aggregate - seriler', () {
    test('bestStreak bozuk anahtari atlar ve dogru sayar', () {
      final history = {
        '2026-09-01': 9000,
        '2026-09-02': 9000,
        '2026-09-03': 9000,
        'bozuk-anahtar': 9000,
        '2026-09-05': 9000,
      };
      expect(Aggregate.bestStreak(history, 8000), 3);
    });

    test('currentStreak bugun bossa dunden baslar', () {
      final d1 = key(today.subtract(const Duration(days: 1)));
      final d2 = key(today.subtract(const Duration(days: 2)));
      expect(Aggregate.currentStreak({d1: 9000, d2: 9000}, 8000), 2);
    });

    test('totalBetween bozuk anahtari yok sayar', () {
      final history = {'2026-09-01': 100, 'bozuk': 999, '2026-09-02': 200};
      final total = Aggregate.totalBetween(
        history,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );
      expect(total, 300);
    });
  });

  group('PrefsService - bozuk kayit dayanikliligi', () {
    test('gecersiz anahtar ve deger elenir', () {
      final decoded = PrefsService.decodeHistory(
        '{"2026-09-20":8000,"bozuk":5,"2026-09-21":-3}',
      );
      expect(decoded, {'2026-09-20': 8000});
    });

    test('24 uzunlugunda olmayan saatlik kayit elenir', () {
      final decoded = PrefsService.decodeHourly(
        '{"2026-09-20":[1,2,3],"2026-09-21":${_hours()}}',
      );
      expect(decoded.keys, ['2026-09-21']);
      expect(decoded['2026-09-21']!.length, 24);
    });

    test('bildirim izni bayragi varsayilan kapali', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      expect(prefs.notificationAsked, isFalse);
      await prefs.setNotificationAsked(true);
      expect(prefs.notificationAsked, isTrue);
    });
  });

  group('StepProvider - gun gecisi', () {
    /// Gece yarisi gecildikten sonra uygulama acildiginda bugun, dunun
    /// sayisiyla baslamamali. Eskiden _baseline korundugu icin dunun
    /// TAMAMI bugune devrediyordu (ekranda 8.732 adim gorunuyordu).
    test('dun -> bugun: bugun sifirdan baslar, dunun kaydi bozulmaz',
        () async {
      final dun = key(today.subtract(const Duration(days: 1)));
      SharedPreferences.setMockInitialValues({
        PrefsKeys.goal: 10000,
        PrefsKeys.history: '{"$dun":8732}',
        PrefsKeys.hourly: '{}',
        PrefsKeys.lastDate: dun,
        PrefsKeys.savedToday: 0,
        // Dun gun donusunde cakilmis ham taban.
        PrefsKeys.baseline: 500000,
      });
      final prefs = await PrefsService.create();
      final p = StepProvider(prefs);

      expect(p.todaySteps, 0);
      expect(p.history[dun], 8732);
      p.dispose();
    });

    test('servis bugune yazmissa o deger benimsenir', () async {
      final dun = key(today.subtract(const Duration(days: 1)));
      SharedPreferences.setMockInitialValues({
        PrefsKeys.goal: 10000,
        PrefsKeys.history: '{"$dun":8732,"$todayKey":420}',
        PrefsKeys.hourly: '{}',
        PrefsKeys.lastDate: dun,
        PrefsKeys.savedToday: 0,
        PrefsKeys.baseline: 500000,
      });
      final prefs = await PrefsService.create();
      final p = StepProvider(prefs);

      expect(p.todaySteps, 420);
      expect(p.history[dun], 8732);
      p.dispose();
    });

    test('ayni gun yeniden baslatmada sayim korunur', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.goal: 10000,
        PrefsKeys.history: '{"$todayKey":3000}',
        PrefsKeys.hourly: '{}',
        PrefsKeys.lastDate: todayKey,
        PrefsKeys.savedToday: 0,
        PrefsKeys.baseline: 700000,
      });
      final prefs = await PrefsService.create();
      final p = StepProvider(prefs);

      expect(p.todaySteps, 3000);
      p.dispose();
    });
  });

  group('StepProvider - dayaniklilik', () {
    test('hourlyFor her zaman 24 uzunlugunda dizi doner', () async {
      final p = await buildProvider();
      expect(p.hourlyFor(today).length, 24);
      expect(p.hourlyFor(DateTime(2020, 1, 1)).length, 24);
      p.dispose();
    });
  });

  group('StepProvider - saatlik kapsama', () {
    test('eksik kapsamali gun icin gercek sure kullanilmaz', () async {
      final hours = List<int>.filled(24, 0);
      hours[9] = 4000; // gunun yalnizca %40'i
      final p = await buildProvider(
        history: {todayKey: 10000},
        hourly: {todayKey: hours},
      );
      expect(p.activeMinutesFor(today), isNull);
      p.dispose();
    });

    test('yeterli kapsamali gun icin gercek sure kullanilir', () async {
      final hours = List<int>.filled(24, 0);
      hours[9] = 5000;
      hours[18] = 4500; // %95
      final p = await buildProvider(
        history: {todayKey: 10000},
        hourly: {todayKey: hours},
      );
      expect(p.activeMinutesFor(today), isNotNull);
      p.dispose();
    });

    test('kismi saatlik kayitli genis donemde tahmine dusulur', () async {
      final history = <String, int>{};
      final hourly = <String, List<int>>{};
      for (var i = 0; i < 200; i++) {
        final d = today.subtract(Duration(days: i));
        history[key(d)] = 8000;
        if (i < 50) {
          final h = List<int>.filled(24, 0);
          h[8] = 4000;
          h[18] = 4000;
          hourly[key(d)] = h;
        }
      }
      final p = await buildProvider(history: history, hourly: hourly);
      final from = today.subtract(const Duration(days: 220));
      expect(p.activeMinutesBetween(from, today), isNull);
      expect(p.activeMinutesAllTime, isNull);
      p.dispose();
    });
  });

  group('StepProvider - importHistory', () {
    test('ayni gunde buyuk deger kazanir, kucuk deger geri goturmez',
        () async {
      final p = await buildProvider(history: {todayKey: 3000});
      await p.importHistory({todayKey: 5000});
      expect(p.todaySteps, 5000);
      await p.importHistory({todayKey: 100});
      expect(p.todaySteps, 5000);
      p.dispose();
    });

    test('buluttaki daha dolu saatlik kayit birlestirilir', () async {
      final yerel = List<int>.filled(24, 0);
      yerel[9] = 1000;
      final bulut = List<int>.filled(24, 0);
      bulut[9] = 1000;
      bulut[18] = 4000;

      final p = await buildProvider(
        history: {todayKey: 1000},
        hourly: {todayKey: yerel},
      );
      await p.importHistory({todayKey: 5000}, hourly: {todayKey: bulut});
      expect(p.activeMinutesFor(today), isNotNull);

      // Daha bos bir kayit uzerine yazmamali.
      await p.importHistory({todayKey: 5000},
          hourly: {todayKey: List<int>.filled(24, 0)});
      expect(p.activeMinutesFor(today), isNotNull);
      p.dispose();
    });

    test('replace: true saatlik kaydi da temizler', () async {
      final eskiGun = today.subtract(const Duration(days: 40));
      final eski = key(eskiGun);
      final hours = List<int>.filled(24, 0);
      hours[9] = 9000;

      final p = await buildProvider(
        history: {eski: 9000},
        hourly: {eski: hours},
      );
      await p.importHistory({todayKey: 4000}, replace: true);

      expect(p.history.containsKey(eski), isFalse);
      expect(p.hourlyFor(eskiGun).every((v) => v == 0), isTrue);
      expect(p.todaySteps, 4000);
      p.dispose();
    });

    test('gecmis gunler korunur', () async {
      final dun = key(today.subtract(const Duration(days: 1)));
      final p = await buildProvider(history: {dun: 8000, todayKey: 1000});
      await p.importHistory({dun: 500, todayKey: 1200});
      expect(p.history[dun], 8000);
      expect(p.todaySteps, 1200);
      p.dispose();
    });
  });
}

String _json(Map<String, int> m) =>
    '{${m.entries.map((e) => '"${e.key}":${e.value}').join(',')}}';

String _jsonHourly(Map<String, List<int>> m) =>
    '{${m.entries.map((e) => '"${e.key}":[${e.value.join(',')}]').join(',')}}';

String _hours() => '[${List<int>.filled(24, 0).join(',')}]';
