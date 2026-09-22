import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adim_sayar/services/backup_service.dart';
import 'package:adim_sayar/utils/achievements.dart';
import 'package:adim_sayar/utils/aggregate.dart';
import 'package:adim_sayar/utils/intensity.dart';
import 'package:adim_sayar/utils/metrics.dart';
import 'package:adim_sayar/widgets/activity_sheet.dart';
import 'package:adim_sayar/widgets/hour_chart.dart';
import 'package:adim_sayar/widgets/info_card.dart';
import 'package:adim_sayar/widgets/week_rings.dart';
import 'package:adim_sayar/widgets/period_chart.dart';

/// Veri dokumu, rozetler, tarih/yag yardimcilari ve grafik etiketleri.
/// Calistirmak icin: flutter test test/features_test.dart
void main() {
  final history = <String, int>{
    for (var i = 0; i < 40; i++)
      Metrics.dayKey(DateTime(2026, 8, 1 + i)): 6000 + i * 200,
  };

  test('numericDate ve fatKg', () {
    expect(Metrics.numericDate(DateTime(2026, 9, 21)), '21.09.2026');
    expect(Metrics.longLabel(DateTime(2026, 9, 21)), 'Pazartesi');
    expect(Metrics.fatKg(15400, 70.0, 170), closeTo(2.0, 1e-9));
    expect(Metrics.fatKg(0, 70.0, 170), 0);
  });

  test('veri dokumu: ozet, aylik ve gunluk tablo', () {
    final text = BackupService.report(
      BackupData(goal: 8000, heightCm: 172, weightKg: 93, history: history),
      now: DateTime(2026, 9, 21, 9, 5),
    );
    expect(text, contains('Oluşturulma: 21.09.2026 09:05'));
    expect(text, contains('Kayıtlı gün: 40'));
    expect(text, contains('Ağustos 2026\t'));
    expect(text, contains('Eylül 2026\t'));
    expect(text, contains('01.08.2026\tCumartesi\t6.000\t'));
    // Gunluk tablo yeniden eskiye.
    final daily = text.substring(text.indexOf('GÜNLÜK'));
    expect(daily.indexOf('09.09.2026'), lessThan(daily.indexOf('01.08.2026')));
    expect(text, isNot(contains('{')));
  });

  test('bos veri dokumu cokmez', () {
    final text = BackupService.report(
      BackupData(goal: 8000, heightCm: 172, weightKg: 93, history: const {}),
    );
    expect(text, contains('Henüz kayıt yok.'));
  });

  test('rozet istatistikleri: en iyi hafta ve ay', () {
    final s = AchievementStats.from(
      history: history,
      goal: 8000,
      heightCm: 172,
      totalKcal: 8000,
    );
    expect(s.recordedDays, 40);
    expect(s.bestDay, 6000 + 39 * 200);
    final aug = List.generate(31, (i) => 6000 + i * 200).reduce((a, b) => a + b);
    expect(s.bestMonth, aug);
    // 31.08-06.09 haftasi (Pzt-Paz) tam hafta ve en buyuk degerlerden.
    final w = List.generate(7, (i) => 6000 + (30 + i) * 200).reduce((a, b) => a + b);
    expect(s.bestWeek, w);
    expect(s.goalDays, history.values.where((v) => v >= 8000).length);

    final items = Achievements.evaluate(s);
    expect(items.length, Achievements.all.length);
    expect(
      items.firstWhere((e) => e.item.kind == AchievementKind.calories).unlocked,
      isTrue,
    );
    final next = Achievements.next(items);
    expect(next, isNotNull);
    expect(next!.unlocked, isFalse);
    for (final c in Achievements.categories) {
      expect(Achievements.all.any((a) => a.kind == c.kind), isTrue);
    }
  });

  test('seri noktalarinda tarih araligi dolu', () {
    for (final p in Period.values) {
      for (final s in Aggregate.series(history, p, 0)) {
        expect(s.start, isNotNull);
        expect(s.end, isNotNull);
        expect(s.end!.isBefore(s.start!), isFalse);
      }
    }
  });

  testWidgets('grafik: ay gorunumu tasmadan kayar, deger etiketleri var',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final period in Period.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PeriodChart(
                series: Aggregate.series(history, period, 0),
                goal: 8000,
                showGoalLine: period != Period.year,
                caption: 'test',
                heightCm: 172,
                weightKg: 93,
                activeMinutes: (_, __) => null,
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('kcal'), findsOneWidget);
    }
  });

  testWidgets('saatlik grafik: sutuna dokununca yalnizca o saat gorunur',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          HourChart(
            hours: List.generate(24, (i) => i == 14 ? 1234 : 0),
            day: DateTime(2026, 9, 21),
          ),
        ]),
      ),
    ));
    expect(
      find.descendant(of: find.byType(HourChart), matching: find.text('0')),
      findsOneWidget,
    );
    expect(find.text('23'), findsOneWidget);
    final hourBar = tester.getRect(find.descendant(
      of: find.byType(HourChart),
      matching: find.byType(GestureDetector),
    ).at(14));
    await tester.tapAt(hourBar.center);
    await tester.pump();
    expect(find.text('14:00-15:00 · 1.234 adım'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('tempo kirilimi', () {
    test('tempo kaydi yoksa eski hesapla birebir ayni', () {
      final bd = ActivityBreakdown.compute(
        totalSteps: 9000,
        briskSteps: 0,
        briskMin: 0,
        runSteps: 0,
        runMin: 0,
        hasData: false,
        heightCm: 172,
        weightKg: 93,
        activeMin: 80,
      );
      expect(bd.kcal, Metrics.kcal(9000, 172, 93, activeMin: 80));
      expect(bd.km, Metrics.distanceKm(9000, 172));
      expect(bd.minutes, 80);
      expect(bd.brisk.steps + bd.run.steps, 0);
    });

    test('ayni adim: kosu > tempolu > normal kalori', () {
      const steps = 3600;
      final normal = Metrics.kcal(steps, 172, 93);
      final brisk = ActivityBreakdown.compute(
        totalSteps: steps, briskSteps: steps, briskMin: 30,
        runSteps: 0, runMin: 0, hasData: true, heightCm: 172, weightKg: 93,
      );
      final run = ActivityBreakdown.compute(
        totalSteps: steps, briskSteps: 0, briskMin: 0,
        runSteps: steps, runMin: 22, hasData: true, heightCm: 172, weightKg: 93,
      );
      expect(brisk.kcal, greaterThan(normal));
      expect(run.kcal, greaterThan(brisk.kcal));
      // Kosuda adim boyu uzun: ayni adimda daha fazla km.
      expect(run.km, greaterThan(brisk.km));
      expect(brisk.km, closeTo(Metrics.distanceKm(steps, 172), 1e-9));
    });

    test('parcalar toplami tutarli, normal = toplam - diger', () {
      final bd = ActivityBreakdown.compute(
        totalSteps: 12000, briskSteps: 3000, briskMin: 25,
        runSteps: 1600, runMin: 10, hasData: true,
        heightCm: 172, weightKg: 93, activeMin: 130,
      );
      expect(bd.normal.steps, 12000 - 3000 - 1600);
      expect(bd.steps, 12000);
      expect(bd.kcal,
          closeTo(bd.normal.kcal + bd.brisk.kcal + bd.run.kcal, 1e-9));
      expect(bd.minutes, bd.normal.minutes + 25 + 10);
    });

    test('MET degerleri makul araliklarda', () {
      expect(Intensity.briskMet(100, 172), closeTo(3.5, 0.6));
      expect(Intensity.briskMet(130, 172), closeTo(6.0, 0.01));
      expect(Intensity.runMet(160, 172), inInclusiveRange(9.0, 12.5));
    });

    test('bozuk kayit elenir', () {
      final m = Intensity.decodeMap({
        '2026-09-21': [1, 2, 3, 4, 5],
        '2026-09-22': [1, 2],
        'bozuk': [1, 2, 3, 4, 5],
        '2026-09-23': [-4, 2, 3, 4, 5],
      });
      expect(m.keys, containsAll(['2026-09-21', '2026-09-23']));
      expect(m.length, 2);
      expect(m['2026-09-23']![0], 0);
      expect(Intensity.mergeMax([1, 5, 2, 0, 0], [3, 1, 2, 4, 1]),
          [3, 5, 2, 4, 1]);
    });

    testWidgets('kirilim tablosu tasmadan cizilir', (tester) async {
      final bd = ActivityBreakdown.compute(
        totalSteps: 125000, briskSteps: 40000, briskMin: 330,
        runSteps: 21000, runMin: 130, hasData: true,
        heightCm: 172, weightKg: 93,
      );
      tester.view.physicalSize = const Size(960, 2000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ActivityBreakdownView(breakdown: bd),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Tempolu yürüyüş'), findsOneWidget);
      // Blok basligi + renk aciklamasi.
      expect(find.textContaining('Koşu'), findsNWidgets(2));
      expect(find.text('Toplam'), findsOneWidget);
    });
  });

  group('son duzenlemeler', () {
    test('rozet kimlikleri benzersiz (ayni baslik farkli kategoride olabilir)',
        () {
      final ids = Achievements.all.map(Achievements.idOf).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('yag karsiligi sabit 7.700 kcal = 1 kg (boy/kilodan bagimsiz)', () {
      expect(Metrics.fatKg(7700), closeTo(1.0, 1e-9));
      expect(Metrics.fatKg(7700, 93, 172), closeTo(1.0, 1e-9));
      expect(Metrics.fatKg(-5), 0);
    });

    testWidgets('su grafigi: tek degerli, ay/yil kaydirmali, tasma yok',
        (tester) async {
      final water = <String, int>{
        for (var i = 0; i < 60; i++)
          Metrics.dayKey(DateTime.now().subtract(Duration(days: i))):
              1500 + (i % 5) * 250,
      };
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final period in Period.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PeriodChart(
                  series: Aggregate.series(water, period, 0),
                  goal: 2500,
                  showGoalLine: period != Period.year,
                  caption: 'Su',
                  barColor: Colors.blue,
                  valueLabel: (p) => (p.value / 1000).toStringAsFixed(1),
                  valueLegend: 'litre',
                ),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('litre'), findsOneWidget);
        // Adim grafigine ozgu aciklamalar su grafiginde cikmamali.
        expect(find.text('kcal'), findsNothing);
        if (period == Period.month || period == Period.year) {
          expect(find.byType(SingleChildScrollView), findsOneWidget);
        }
      }
    });
  });

  group('arayuz duzenlemeleri', () {
    Future<void> pumpAt360(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [child]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    int goalDays(Map<String, int> h, DateTime a, DateTime b, int goal) {
      var n = 0;
      for (var d = a; !d.isAfter(b); d = Metrics.addDays(d, 1)) {
        if ((h[Metrics.dayKey(d)] ?? 0) >= goal) n++;
      }
      return n;
    }

    testWidgets('hedef rozeti guncel hedefe gore (2.000 -> 4.000)',
        (tester) async {
      final start = Metrics.weekStart(DateTime.now());
      final h = <String, int>{
        for (var i = 0; i < 7; i++)
          Metrics.dayKey(Metrics.addDays(start, i)): [1500, 2500, 3000, 4500, 800, 5000, 2100][i],
      };
      for (final entry in {2000: 5, 4000: 2}.entries) {
        await pumpAt360(
          tester,
          PeriodChart(
            series: Aggregate.series(h, Period.week, 0),
            goal: entry.key,
            showGoalLine: true,
            caption: 'test',
            heightCm: 172,
            weightKg: 93,
            goalDaysOf: (a, b) => goalDays(h, a, b, entry.key),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('🏅'), findsNWidgets(entry.value));
      }
    });

    testWidgets('ozet satiri 5 kutu (su dahil) tasmaz', (tester) async {
      await pumpAt360(
        tester,
        const SummaryRow(
          steps: 123456,
          km: 88.45,
          kcal: 5432,
          minutes: 1234,
          waterMl: 45500,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('litre su'), findsOneWidget);
    });

    testWidgets('haftalik rapor gun detaylari tasmaz', (tester) async {
      final start = Metrics.weekStart(DateTime.now());
      final week = [
        for (var i = 0; i < 7; i++)
          MapEntry(Metrics.addDays(start, i), i * 3000),
      ];
      final bd = ActivityBreakdown.compute(
        totalSteps: 18000, briskSteps: 4000, briskMin: 35,
        runSteps: 0, runMin: 0, hasData: true, heightCm: 172, weightKg: 93,
      );
      await pumpAt360(
        tester,
        WeekRings(
          week: week,
          goal: 8000,
          details: [
            for (final e in week)
              WeekDayDetail.from(steps: e.value, breakdown: bd, waterMl: 1750),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
