import 'metrics.dart';

enum Period { day, week, month, year }

extension PeriodLabel on Period {
  String get label => switch (this) {
        Period.day => 'Gün',
        Period.week => 'Hafta',
        Period.month => 'Ay',
        Period.year => 'Yıl',
      };
}

class Bucket {
  final DateTime start;
  final String title;
  final String subtitle;
  final int steps;
  final int dayCount;
  final Period period;

  const Bucket({
    required this.start,
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.dayCount,
    required this.period,
  });

  int get avgSteps => dayCount == 0 ? 0 : (steps / dayCount).round();
}

class Aggregate {
  /// Gecmisi secilen periyoda gore gruplar; yeniden eskiye siralar.
  static List<Bucket> build(Map<String, int> history, Period period, int goal) {
    final entries = history.entries
        .where((e) => e.value > 0 && Metrics.isValidKey(e.key))
        .map((e) => MapEntry(Metrics.parseKey(e.key), e.value))
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    if (entries.isEmpty) return [];

    if (period == Period.day) {
      return entries
          .map((e) => Bucket(
                start: e.key,
                title: _dayTitle(e.key),
                subtitle: Metrics.longLabel(e.key),
                steps: e.value,
                dayCount: 1,
                period: Period.day,
              ))
          .toList();
    }

    final groups = <DateTime, List<MapEntry<DateTime, int>>>{};
    for (final e in entries) {
      final k = switch (period) {
        Period.week => Metrics.weekStart(e.key),
        Period.month => DateTime(e.key.year, e.key.month),
        Period.year => DateTime(e.key.year),
        Period.day => e.key,
      };
      groups.putIfAbsent(k, () => []).add(e);
    }

    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return keys.map((k) {
      final items = groups[k]!;
      final total = items.fold<int>(0, (a, b) => a + b.value);
      final reached = items.where((e) => goal > 0 && e.value >= goal).length;

      return Bucket(
        start: k,
        title: switch (period) {
          Period.week => _weekTitle(k),
          Period.month => '${Metrics.monthName(k.month)} ${k.year}',
          Period.year => '${k.year}',
          Period.day => _dayTitle(k),
        },
        subtitle:
            '${items.length} gün kayıt - $reached gün hedef tuttu',
        steps: total,
        dayCount: items.length,
        period: period,
      );
    }).toList();
  }

  static String _dayTitle(DateTime d) {
    final today = DateTime.now();
    final isToday = d.year == today.year &&
        d.month == today.month &&
        d.day == today.day;
    if (isToday) return 'Bugün';
    final y = Metrics.addDays(today, -1);
    if (d.year == y.year && d.month == y.month && d.day == y.day) {
      return 'Dün';
    }
    return '${d.day} ${Metrics.monthName(d.month)} ${d.year}';
  }

  static String _weekTitle(DateTime start) {
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year) {
      if (start.month == end.month) {
        return '${start.day} - ${end.day} ${Metrics.monthName(start.month)} ${start.year}';
      }
      return '${start.day} ${Metrics.monthName(start.month)} - '
          '${end.day} ${Metrics.monthName(end.month)} ${end.year}';
    }
    return '${start.day} ${Metrics.monthName(start.month)} ${start.year} - '
        '${end.day} ${Metrics.monthName(end.month)} ${end.year}';
  }

  /// Verilen tarih araligindaki toplam adim.
  static int totalBetween(Map<String, int> history, DateTime from, DateTime to) {
    var sum = 0;
    history.forEach((k, v) {
      final d = Metrics.tryParseKey(k);
      if (d == null) return;
      if (!d.isBefore(from) && !d.isAfter(to)) sum += v;
    });
    return sum;
  }

  /// [offset] 0 = icinde bulunulan donem, -1 = bir onceki.
  static PeriodRange range(Period period, int offset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (period) {
      case Period.day:
        final d = today.add(Duration(days: offset));
        return PeriodRange(d, d, _dayTitle(d));
      case Period.week:
        final s = Metrics.weekStart(today).add(Duration(days: offset * 7));
        return PeriodRange(s, s.add(const Duration(days: 6)), _weekTitle(s));
      case Period.month:
        final s = DateTime(today.year, today.month + offset, 1);
        final e = DateTime(s.year, s.month + 1, 0);
        return PeriodRange(s, e, '${Metrics.monthName(s.month)} ${s.year}');
      case Period.year:
        final s = DateTime(today.year + offset, 1, 1);
        return PeriodRange(s, DateTime(s.year, 12, 31), '${s.year}');
    }
  }

  /// Secili donemin mini grafigi icin etiketli seri uretir.
  ///
  /// Gun sekmesinde [dayWindowEnd] verilirse 7 gunluk pencere o gunde biter
  /// ve secili gun pencerenin icinde yalnizca vurgulanir; baska gune
  /// dokununca grafik kaymaz.
  static List<SeriesPoint> series(
    Map<String, int> history,
    Period period,
    int offset, {
    DateTime? dayWindowEnd,
  }) {
    final r = range(period, offset);

    switch (period) {
      case Period.day:
        final end = dayWindowEnd ?? r.start;
        return List.generate(7, (i) {
          final d = Metrics.addDays(end, i - 6);
          return SeriesPoint(
            label: Metrics.shortLabel(d),
            value: history[Metrics.dayKey(d)] ?? 0,
            highlight: Metrics.daysBetween(d, r.start) == 0,
            start: d,
            end: d,
          );
        });
      case Period.week:
        return List.generate(7, (i) {
          final d = r.start.add(Duration(days: i));
          return SeriesPoint(
            label: Metrics.shortLabel(d),
            value: history[Metrics.dayKey(d)] ?? 0,
            start: d,
            end: d,
          );
        });
      case Period.month:
        final days = r.end.day;
        return List.generate(days, (i) {
          final d = DateTime(r.start.year, r.start.month, i + 1);
          return SeriesPoint(
            label: '${i + 1}',
            value: history[Metrics.dayKey(d)] ?? 0,
            showLabel: true,
            start: d,
            end: d,
          );
        });
      case Period.year:
        return List.generate(12, (m) {
          final s = DateTime(r.start.year, m + 1, 1);
          final e = DateTime(r.start.year, m + 2, 0);
          return SeriesPoint(
            label: Metrics.months[m].substring(0, 3),
            value: totalBetween(history, s, e),
            showLabel: true,
            start: s,
            end: e,
          );
        });
    }
  }

  /// Ust uste hedefi tutturulan gun sayisi (bugun bos ise dunden baslar).
  static int currentStreak(Map<String, int> history, int goal) {
    if (goal <= 0) return 0;
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);

    if ((history[Metrics.dayKey(cursor)] ?? 0) < goal) {
      cursor = Metrics.addDays(cursor, -1);
    }

    var count = 0;
    while ((history[Metrics.dayKey(cursor)] ?? 0) >= goal) {
      count++;
      cursor = Metrics.addDays(cursor, -1);
    }
    return count;
  }

  static int bestStreak(Map<String, int> history, int goal) {
    if (goal <= 0 || history.isEmpty) return 0;
    final days = history.entries
        .where((e) => e.value >= goal)
        .map((e) => Metrics.tryParseKey(e.key))
        .whereType<DateTime>()
        .toList()
      ..sort();

    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && Metrics.daysBetween(prev, d) == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }
}

class PeriodRange {
  final DateTime start;
  final DateTime end;
  final String title;
  const PeriodRange(this.start, this.end, this.title);
}

class SeriesPoint {
  final String label;
  final int value;
  final bool highlight;
  final bool showLabel;

  /// Sutunun kapsadigi tarih araligi (gun sutununda ikisi ayni gun).
  /// Grafikteki km/kcal etiketleri icin kullanilir.
  final DateTime? start;
  final DateTime? end;

  const SeriesPoint({
    required this.label,
    required this.value,
    this.highlight = false,
    this.showLabel = true,
    this.start,
    this.end,
  });
}
