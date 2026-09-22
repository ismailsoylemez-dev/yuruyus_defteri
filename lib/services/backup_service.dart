import '../utils/aggregate.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';

class BackupData {
  final int goal;
  final int heightCm;
  final double weightKg;
  final Map<String, int> history;
  final Map<String, List<int>> hourly;

  BackupData({
    required this.goal,
    required this.heightCm,
    required this.weightKg,
    required this.history,
    this.hourly = const {},
  });
}

/// Kayitlari e-postaya yapistirilabilir / yazdirilabilir duz metne cevirir.
///
/// Sutunlar TAB ile ayrilir: Gmail'de hizali okunur, Excel/Sheets'e
/// yapistirildiginda da hucrelere dagilir.
class BackupService {
  static String report(
    BackupData d, {
    int? Function(DateTime from, DateTime to)? activeMinutesBetween,
    int? Function(DateTime day)? activeMinutesFor,
    ActivityBreakdown Function(DateTime from, DateTime to)? breakdown,
    String? account,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final days = <DateTime, int>{};
    d.history.forEach((k, v) {
      final day = Metrics.tryParseKey(k);
      if (day != null && v > 0) days[day] = v;
    });
    final sorted = days.keys.toList()..sort();

    double kcalOf(int steps, int? minutes) =>
        Metrics.kcal(steps, d.heightCm, d.weightKg, activeMin: minutes);
    String km(int steps) => Metrics.distanceKm(steps, d.heightCm)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    String kg(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';

    final b = StringBuffer()
      ..writeln('YÜRÜYÜŞ DEFTERİ - VERİ DÖKÜMÜ')
      ..writeln('Oluşturulma: ${Metrics.numericDate(at)} ${hm(at)}');
    if (account != null && account.isNotEmpty) b.writeln('Hesap: $account');
    b
      ..writeln('Profil: Boy ${d.heightCm} cm · Kilo ${kg(d.weightKg)} kg · '
          'Günlük hedef ${Metrics.thousands(d.goal)} adım')
      ..writeln();

    if (sorted.isEmpty) {
      b.writeln('Henüz kayıt yok.');
      return b.toString();
    }

    final total = days.values.fold<int>(0, (a, v) => a + v);
    final allMin = activeMinutesBetween?.call(sorted.first, sorted.last);
    final allBd = breakdown?.call(sorted.first, sorted.last);
    final totalKcal = allBd?.kcal ?? kcalOf(total, allMin);
    // Kosu adimlari uzun adim boyuyla; kirilim yoksa tek adim boyu.
    String kmOf(int steps, ActivityBreakdown? bd) => bd == null
        ? km(steps)
        : bd.km.toStringAsFixed(2).replaceAll('.', ',');
    final best = days.entries.reduce((a, e) => e.value > a.value ? e : a);
    final goalDays =
        d.goal > 0 ? days.values.where((v) => v >= d.goal).length : 0;

    b
      ..writeln('ÖZET')
      ..writeln('Kayıt aralığı: ${Metrics.numericDate(sorted.first)} - '
          '${Metrics.numericDate(sorted.last)}')
      ..writeln('Kayıtlı gün: ${sorted.length}')
      ..writeln('Toplam adım: ${Metrics.thousands(total)}')
      ..writeln('Toplam mesafe: ${kmOf(total, allBd)} km')
      ..writeln('Toplam kalori: ${Metrics.thousands(totalKcal.round())} kcal '
          '(≈ ${kg(Metrics.fatKg(totalKcal, d.weightKg, d.heightCm))} kg yağ karşılığı)')
      ..writeln('Toplam süre: '
          '${Metrics.duration(allBd?.minutes ?? allMin ?? Metrics.activeMinutes(total))}')
      ..writeln('Günlük ortalama: '
          '${Metrics.thousands((total / sorted.length).round())} adım')
      ..writeln('En iyi gün: ${Metrics.numericDate(best.key)} - '
          '${Metrics.thousands(best.value)} adım')
      ..writeln('Hedefe ulaşılan gün: $goalDays')
      ..writeln('En uzun seri: ${Aggregate.bestStreak(d.history, d.goal)} gün');
    if (allBd != null && allBd.hasData) {
      for (final (name, part) in [
        ('Normal yürüyüş', allBd.normal),
        ('Tempolu yürüyüş', allBd.brisk),
        ('Koşu', allBd.run),
      ]) {
        b.writeln('$name: ${Metrics.thousands(part.steps)} adım · '
            '${Metrics.duration(part.minutes)} · '
            '${part.km.toStringAsFixed(2).replaceAll('.', ',')} km · '
            '${Metrics.thousands(part.kcal.round())} kcal');
      }
    }
    b.writeln();

    // Aylik ozet (yeniden eskiye).
    final months = <DateTime, int>{};
    final monthDays = <DateTime, int>{};
    days.forEach((day, v) {
      final m = DateTime(day.year, day.month);
      months[m] = (months[m] ?? 0) + v;
      monthDays[m] = (monthDays[m] ?? 0) + 1;
    });
    final monthKeys = months.keys.toList()..sort((a, c) => c.compareTo(a));
    b
      ..writeln('AYLIK')
      ..writeln('Ay\tAdım\tKm\tKcal\tGün');
    for (final m in monthKeys) {
      final steps = months[m]!;
      final end = DateTime(m.year, m.month + 1, 0);
      final mBd = breakdown?.call(m, end);
      final kcal =
          mBd?.kcal ?? kcalOf(steps, activeMinutesBetween?.call(m, end));
      b.writeln('${Metrics.monthName(m.month)} ${m.year}\t'
          '${Metrics.thousands(steps)}\t${kmOf(steps, mBd)}\t'
          '${Metrics.thousands(kcal.round())}\t${monthDays[m]}');
    }
    b
      ..writeln()
      ..writeln('GÜNLÜK')
      ..writeln('Tarih\tGün\tAdım\tKm\tKcal\tTempolu dk\tKoşu dk\tHedef');
    for (final day in sorted.reversed) {
      final steps = days[day]!;
      final dBd = breakdown?.call(day, day);
      final kcal = dBd?.kcal ?? kcalOf(steps, activeMinutesFor?.call(day));
      final hit = d.goal > 0 && steps >= d.goal ? '✓' : '-';
      b.writeln('${Metrics.numericDate(day)}\t${Metrics.longLabel(day)}\t'
          '${Metrics.thousands(steps)}\t${kmOf(steps, dBd)}\t'
          '${Metrics.thousands(kcal.round())}\t'
          '${dBd?.brisk.minutes ?? 0}\t${dBd?.run.minutes ?? 0}\t$hit');
    }
    return b.toString();
  }
}
