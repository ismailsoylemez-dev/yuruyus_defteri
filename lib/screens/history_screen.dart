import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../services/route_service.dart';
import '../theme/app_theme.dart';
import '../utils/aggregate.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';
import '../utils/root_nav.dart';
import '../widgets/activity_sheet.dart';
import '../widgets/hour_chart.dart';
import '../widgets/info_card.dart';
import '../widgets/period_chart.dart';
import '../widgets/period_selector.dart';
import '../widgets/year_heatmap.dart';
import 'route_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Period _period = Period.day;
  int _offset = 0;
  DateTime? _selectedDate;

  /// Gun sekmesi grafiginin 7 gunluk penceresinin son gunu. Secili gun
  /// pencere icinde kaldikca grafik yerinde durur (kayma olmaz); disina
  /// cikilinca pencere bir sayfa kayar.
  DateTime? _dayWindowEnd;

  DateTime _dayWindowFor(DateTime sel) {
    final today = _today();
    var end = _dayWindowEnd;
    if (end == null || end.isAfter(today)) end = sel;
    final start = Metrics.addDays(end, -6);
    if (sel.isBefore(start)) {
      // Geriye gidildi: secili gun en sagda.
      end = sel;
    } else if (sel.isAfter(end)) {
      // Ileriye gidildi: secili gun en solda (bugunu gecmeden).
      final e = Metrics.addDays(sel, 6);
      end = e.isAfter(today) ? today : e;
    }
    _dayWindowEnd = end;
    return end;
  }

  /// Tempo kartindaki "Rotayi gor": o gunun haritasi.
  void _openRoute(DateTime day) async {
    final pts = await RouteService.load(day, day);
    if (!mounted) return;
    if (pts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Bugüne ait rota kaydı bulunamadı.'),
      ));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RouteScreen(initialDate: day)),
    );
  }

  /// Grafik gecmise kaydirildi: bir onceki hafta / ay / yil.
  void _swipePrev() => setState(() {
        _offset--;
        _selectedDate = null;
      });

  /// Grafik ileri kaydirildi: guncel doneme kadar.
  void _swipeNext() {
    if (_offset >= 0) return;
    setState(() {
      _offset++;
      _selectedDate = null;
    });
  }

  void _setPeriod(Period p) => setState(() {
        _period = p;
        _offset = 0;
        _selectedDate = null;
      });

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();
    final water = context.watch<WaterProvider>();

    final h = settings.heightCm;
    final w = settings.weightKg;
    final goal = settings.goal;

    final range = Aggregate.range(_period, _offset);
    final series = Aggregate.series(
      step.history,
      _period,
      _offset,
      dayWindowEnd:
          _period == Period.day ? _dayWindowFor(range.start) : null,
    );
    final total = Aggregate.totalBetween(step.history, range.start, range.end);
    // Tek kaynak: normal + tempolu + kosu toplami.
    // Tempo kaydi yoksa eski hesapla birebir aynidir.
    final bd = step.breakdownBetween(range.start, range.end);

    if (step.recordedDays == 0 && step.todaySteps == 0) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Geçmiş'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                tooltip: 'Ayarlar',
                onPressed: () => RootNav.openSettings(),
                icon: Icon(Icons.settings_outlined, color: AppColors.textDim),
              ),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 40, color: AppColors.textDim),
                const SizedBox(height: 16),
                Text(
                  'Henüz kayıt yok',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Yürümeye başla; günlük, haftalık, aylık\nve yıllık dökümler burada birikecek.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geçmiş'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              tooltip: 'Ayarlar',
              onPressed: () => RootNav.openSettings(),
              icon: Icon(Icons.settings_outlined, color: AppColors.textDim),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: PeriodSelector(selected: _period, onChanged: _setPeriod),
              ),
              const SizedBox(width: 4),
              // Takvimden sec ya da kalem ikonuyla elle yaz: Gun sekmesinde
              // o gun acilir.
              _DatePickButton(
                onTap: () => _pickDay(
                  _period == Period.day ? range.start : _today(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RangeBar(
            title: range.title,
            onPrev: () => setState(() {
              _offset--;
              _selectedDate = null;
            }),
            onNext: _offset < 0
                ? () => setState(() {
                      _offset++;
                      _selectedDate = null;
                    })
                : null,
          ),
          const SizedBox(height: 16),
          if (total == 0)
            _buildEmptyState()
          else ...[
            // Sira: donem ozeti (adim/km/kcal/sure/su) -> hemen altinda grafik.
            _SectionCaption(switch (_period) {
              Period.day => 'Gün özeti',
              Period.week => 'Hafta özeti',
              Period.month => 'Ay özeti',
              Period.year => 'Yıl özeti',
            }),
            const SizedBox(height: 8),
            SummaryRow(
              steps: total,
              km: bd.km,
              kcal: bd.kcal,
              minutes: bd.minutes,
              waterMl: settings.waterEnabled
                  ? Aggregate.totalBetween(water.history, range.start, range.end)
                  : null,
            ),
            const SizedBox(height: 12),
            _InsightCard(period: _period, offset: _offset, step: step),
            const SizedBox(height: 12),
            PeriodChart(
              series: series,
              goal: goal,
              showGoalLine: _period != Period.year,
              caption: _chartCaption(),
              heightCm: h,
              weightKg: w,
              activeMinutes: (from, to) =>
                  step.activeMinutesBetween(from, to),
              breakdown: step.breakdownBetween,
              waterOf: settings.waterEnabled
                  ? (a, b) => Aggregate.totalBetween(water.history, a, b)
                  : null,
              // Hafta / Ay / Yil: grafigi kaydirarak onceki doneme gecilir.
              onSwipePrev: _period == Period.day ? null : _swipePrev,
              onSwipeNext:
                  _period == Period.day || _offset >= 0 ? null : _swipeNext,
              // Hedef her derlemede guncel ayardan okunur: hedef degisince
              // rozetler aninda guncellenir.
              goalDaysOf: _period == Period.day || _period == Period.week
                  ? (a, b) => _goalDays(step.history, a, b, goal)
                  : null,
              onBarTap: (p) {
                final s = p.start;
                final e = p.end;
                if (s == null || e == null) return;
                if (p.value <= 0) {
                  _noData(s == e ? 'Bu gün' : 'Bu ay');
                  return;
                }
                
                final title = s == e 
                    ? '${Metrics.numericDate(s)} ${Metrics.longLabel(s)}'
                    : '${Metrics.fullLabel(s)} ${s.year} Özeti';
                    
                showActivitySheet(
                  context,
                  title: title,
                  breakdown: step.breakdownBetween(s, e),
                );
              },
            ),
            const SizedBox(height: 16),
            // Yil isi haritasi yalniz Yil sekmesinde.
            if (_period == Period.year) ...[
              YearHeatmap(
                year: range.start.year,
                history: step.history,
                goal: goal,
              ),
              const SizedBox(height: 16),
            ],
            _TempoCard(breakdown: bd),
            const SizedBox(height: 20),
            // Ortalama / en iyi gun / hedef gunleri: yalniz Hafta, Ay, Yil.
            if (_period != Period.day) ...[
              ..._periodStats(step.history, goal, range, total, bd),
              const SizedBox(height: 24),
            ],
            // Saatlik grafik yalniz Gun sekmesinde (hafta/ay/yilda anlamsiz);
            // ok tuslari ve tarih seciciyle herhangi bir gune gidilir.
            if (_period == Period.day) ...[
              _HourChartCard(
                step: step,
                targetDate: _selectedDate ?? range.end,
                // Saatlik kartta secilen gun tum sayfaya uygulanir: Gun
                // sekmesi o gune gecer (ozet, grafik, kirilim ve dokum ayni gun).
                onDateChanged: _goToDay,
              ),
              const SizedBox(height: 24),
            ],
          ],
          Row(
            children: [
              Text(
                _period == Period.day ? 'Gün detayı' : 'Dönem dökümü',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _breakdownHint(),
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._buildBreakdown(step, settings, range),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_graph_outlined,
                size: 48, color: AppColors.accent),
          ),
          const SizedBox(height: 24),
          Text(
            'Kayıt Bulunamadı',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seçtiğiniz zaman aralığında herhangi bir\nadım kaydı bulunmuyor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Donem dokumundeki bir satirin adi (mesajlarda).
  String _unitName() => switch (_period) {
        Period.day => 'Bu gün',
        Period.week => 'Bu gün',
        Period.month => 'Bu hafta',
        Period.year => 'Bu ay',
      };

  void _noData(String what, {bool future = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(future
            ? '$what henüz gelmedi.'
            : '$what için kayıtlı adım verisi yok.'),
      ));
  }

  /// Aralikta guncel hedefi tutan gun sayisi.
  static int _goalDays(
      Map<String, int> history, DateTime from, DateTime to, int goal) {
    if (goal <= 0) return 0;
    var n = 0;
    for (var d = from; !d.isAfter(to); d = Metrics.addDays(d, 1)) {
      if ((history[Metrics.dayKey(d)] ?? 0) >= goal) n++;
    }
    return n;
  }

  /// Sayfayi Gun sekmesinde verilen gune getirir.
  void _goToDay(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final diff = Metrics.daysBetween(_today(), day);
    setState(() {
      _period = Period.day;
      _offset = diff > 0 ? 0 : diff;
      _selectedDate = day;
    });
  }

  Future<void> _pickDay(DateTime current) async {
    final today = _today();
    final keys = context.read<StepProvider>().history.keys
        .map(Metrics.tryParseKey)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final first = keys.isEmpty
        ? Metrics.addDays(today, -365)
        : (keys.first.isBefore(today) ? keys.first : today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first)
          ? first
          : (current.isAfter(today) ? today : current),
      firstDate: first,
      lastDate: today,
      // Kalem ikonu: takvim yerine tarihi elle yazma (gg.aa.yyyy).
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: 'Tarih seç veya yaz',
      fieldLabelText: 'Tarih',
      fieldHintText: 'gg.aa.yyyy',
      errorFormatText: 'Geçersiz tarih biçimi',
      errorInvalidText: 'Kayıt aralığı dışında',
      cancelText: 'Vazgeç',
      confirmText: 'Git',
    );
    if (picked != null && mounted) _goToDay(picked);
  }

  /// Hafta / Ay / Yil sekmelerine ozel kartlar (Gun'de anlamsiz).
  List<Widget> _periodStats(
    Map<String, int> history,
    int goal,
    PeriodRange range,
    int total,
    ActivityBreakdown bd,
  ) {
    var days = 0;
    var bestVal = 0;
    var bestKey = range.start;
    history.forEach((k, v) {
      final d = Metrics.tryParseKey(k);
      if (d == null || d.isBefore(range.start) || d.isAfter(range.end)) return;
      if (v > 0) days++;
      if (v > bestVal) {
        bestVal = v;
        bestKey = d;
      }
    });

    return [
      const _SectionCaption('Günlük ortalama'),
      const SizedBox(height: 8),
      SummaryRow(
        steps: days == 0 ? 0 : (total / days).round(),
        km: days == 0 ? 0.0 : bd.km / days,
        kcal: days == 0 ? 0.0 : bd.kcal / days,
        minutes: days == 0 ? 0 : (bd.minutes / days).round(),
      ),
      const SizedBox(height: 14),
      StatTile(
        icon: Icons.emoji_events_outlined,
        value: bestVal == 0 ? 'Veri yok' : '${Metrics.thousands(bestVal)} adım',
        label: bestVal == 0
            ? 'Bu dönemde kayıt yok'
            : 'En iyi gün - ${Metrics.fullLabel(bestKey)} ${bestKey.year}',
      ),
    ];
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _chartCaption() => switch (_period) {
        Period.day => '7 günlük görünüm',
        Period.week => 'Günlere göre',
        Period.month => 'Ayın günlerine göre',
        Period.year => 'Aylara göre',
      };

  String _breakdownHint() => switch (_period) {
        Period.day => 'dokun: tempo dökümü',
        Period.week => 'günlere göre · dokun',
        Period.month => 'haftalara göre · dokun',
        Period.year => 'aylara göre · dokun',
      };

  List<Widget> _buildBreakdown(
    StepProvider step,
    SettingsProvider settings,
    PeriodRange range,
  ) {
    final rows = <_Row>[];
    final history = step.history;

    switch (_period) {
      case Period.day:
        rows.add(_Row(
          title: Metrics.longLabel(range.start),
          subtitle: '${Metrics.fullLabel(range.start)} ${range.start.year}',
          steps: history[Metrics.dayKey(range.start)] ?? 0,
          from: range.start,
          to: range.start,
        ));
      case Period.week:
        for (var i = 0; i < 7; i++) {
          final d = range.start.add(Duration(days: i));
          rows.add(_Row(
            title: Metrics.longLabel(d),
            subtitle: '${Metrics.fullLabel(d)} ${d.year}',
            steps: history[Metrics.dayKey(d)] ?? 0,
            future: d.isAfter(DateTime.now()),
            from: d,
            to: d,
          ));
        }
      case Period.month:
        // Haftalar ay sinirina kirpilir; aksi halde komsu ayin gunleri
        // bu ayin dokumune karisir ve toplamlar tutmaz.
        var cursor = Metrics.weekStart(range.start);
        var index = 1;
        while (!cursor.isAfter(range.end)) {
          final weekEnd = cursor.add(const Duration(days: 6));
          final from = cursor.isBefore(range.start) ? range.start : cursor;
          final to = weekEnd.isAfter(range.end) ? range.end : weekEnd;

          rows.add(_Row(
            title: from.day == to.day
                ? '${from.day} ${Metrics.monthName(range.start.month)}'
                : '${from.day} - ${to.day} ${Metrics.monthName(range.start.month)}',
            subtitle: '$index. hafta - ${range.start.year}',
            steps: Aggregate.totalBetween(history, from, to),
            future: from.isAfter(DateTime.now()),
            from: from,
            to: to,
          ));

          cursor = cursor.add(const Duration(days: 7));
          index++;
        }
      case Period.year:
        for (var m = 1; m <= 12; m++) {
          final s = DateTime(range.start.year, m, 1);
          final e = DateTime(range.start.year, m + 1, 0);
          rows.add(_Row(
            title: Metrics.monthName(m),
            subtitle: '${range.start.year}',
            steps: Aggregate.totalBetween(history, s, e),
            future: s.isAfter(DateTime.now()),
            from: s,
            to: e,
          ));
        }
    }

    final best = rows.fold<int>(0, (m, r) => r.steps > m ? r.steps : m);

    return rows.map((r) {
      final bd = step.breakdownBetween(r.from, r.to);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        // Dokununca o gunun / haftanin / ayin tempo kirilimi acilir.
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
                  // Gelecek (pasif) satir: bilgi. Verisiz satir: mesaj.
                  if (r.future) {
                    _noData(_unitName(), future: true);
                    return;
                  }
                  if (r.steps <= 0) {
                    _noData(_unitName());
                    return;
                  }
                  if (r.from == r.to) {
                    setState(() => _selectedDate = r.from);
                  }
                  showActivitySheet(
                    context,
                    title: '${r.title} - ${r.subtitle}',
                    breakdown: bd,
                    onShowRoute:
                        r.from == r.to ? () => _openRoute(r.from) : null,
                  );
                },
          child: _BreakdownTile(
            row: r,
            breakdown: bd,
            goal: settings.goal,
            isBest: best > 0 && r.steps == best,
            dayLevel: _period == Period.day || _period == Period.week,
          ),
        ),
      );
    }).toList();
  }
}

class _Row {
  final String title;
  final String subtitle;
  final int steps;
  final bool future;
  final DateTime from;
  final DateTime to;

  const _Row({
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.from,
    required this.to,
    this.future = false,
  });
}

/// Secili donemin tempo kirilimi (normal / tempolu / kosu) - satir ici.
class _TempoCard extends StatelessWidget {
  final ActivityBreakdown breakdown;

  const _TempoCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed, size: 18, color: ActivityColors.brisk),
              const SizedBox(width: 8),
              Text(
                'Tempo kırılımı',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ActivityBreakdownView(breakdown: breakdown),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final Period period;
  final int offset;
  final StepProvider step;

  const _InsightCard({
    required this.period,
    required this.offset,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    if (period != Period.week && period != Period.month) return const SizedBox.shrink();
    
    final currentRange = Aggregate.range(period, offset);
    final previousRange = Aggregate.range(period, offset - 1);
    
    final currentTotal = Aggregate.totalBetween(step.history, currentRange.start, currentRange.end);
    final previousTotal = Aggregate.totalBetween(step.history, previousRange.start, previousRange.end);
    
    if (previousTotal == 0 || currentTotal == 0) return const SizedBox.shrink(); // Yeterli veri yok
    
    final diff = currentTotal - previousTotal;
    final percent = (diff / previousTotal * 100).round();
    
    final String message;
    final IconData icon;
    final Color color;
    
    final periodName = period == Period.week ? 'haftaya' : 'aya';
    
    if (percent > 0) {
      message = 'Geçen $periodName göre %$percent daha fazla yürüdün, harika gidiyorsun!';
      icon = Icons.trending_up;
      color = AppColors.best;
    } else if (percent < 0) {
      message = 'Geçen $periodName göre %${percent.abs()} daha az yürüdün. Hedefine ulaşmak için temponu artır!';
      icon = Icons.trending_down;
      color = Colors.orange;
    } else {
      message = 'Geçen ayla tam olarak aynı tempodasın. İstikrarını koruyorsun!';
      icon = Icons.trending_flat;
      color = Colors.blue;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _BreakdownTile extends StatelessWidget {
  final _Row row;
  final ActivityBreakdown breakdown;
  final int goal;
  final bool isBest;
  final bool dayLevel;

  const _BreakdownTile({
    required this.row,
    required this.breakdown,
    required this.goal,
    required this.isBest,
    required this.dayLevel,
  });

  @override
  Widget build(BuildContext context) {
    final steps = row.steps;
    final reached = dayLevel && goal > 0 && steps >= goal;
    final km = breakdown.km;
    final kcal = breakdown.kcal;
    final tempo = [
      if (breakdown.brisk.minutes > 0)
        '${Metrics.duration(breakdown.brisk.minutes)} tempolu',
      if (breakdown.run.minutes > 0)
        '${Metrics.duration(breakdown.run.minutes)} koşu',
    ].join(' · ');

    final child = Opacity(
      opacity: row.future ? 0.45 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isBest && steps > 0
                ? AppColors.best.withValues(alpha: 0.55)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: steps == 0
                    ? AppColors.surfaceAlt
                    : isBest
                        ? AppColors.best
                        : reached
                            ? AppColors.accent
                            : AppColors.accent.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    row.subtitle,
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11.5,
                    ),
                  ),
                  if (tempo.isNotEmpty)
                    Text(
                      tempo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ActivityColors.brisk,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _Val(Metrics.thousands(steps), 'adım', accent: true),
                  const SizedBox(width: 12),
                  _Val(kcal.toStringAsFixed(0), 'kcal'),
                  const SizedBox(width: 12),
                  _Val(km.toStringAsFixed(1), 'km'),
                ],
              ),
            ),
            if (reached)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle,
                    size: 16, color: AppColors.accent),
              ),
          ],
        ),
      ),
    );
    
    return child;
  }
}

class _Val extends StatelessWidget {
  final String value;
  final String label;
  final bool accent;

  const _Val(this.value, this.label, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            color: accent ? AppColors.accent : AppColors.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.textDim, fontSize: 11),
        ),
      ],
    );
  }
}

/// Donem seciciyle ayni yukseklikte yuvarlak takvim butonu.
class _DatePickButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DatePickButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tarihe git',
      child: Material(
        color: AppColors.surface,
        shape: CircleBorder(side: BorderSide(color: AppColors.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              Icons.edit_calendar_outlined,
              size: 20,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  final String text;
  const _SectionCaption(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppColors.textDim,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        ),
      );
}

/// Saatlik dagilim + gun gezinme (geri / ileri / tarih secici).
/// Veri kaynagi degismedi: [StepProvider.hourlyFor].
class _HourChartCard extends StatelessWidget {
  final StepProvider step;
  final DateTime targetDate;
  final ValueChanged<DateTime> onDateChanged;

  const _HourChartCard({
    required this.step,
    required this.targetDate,
    required this.onDateChanged,
  });

  /// Saatlik kayit bu kadar gun tutulur (StepProvider ile ayni).
  static const keepDays = 365;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final isToday = day == today;
    final first = Metrics.addDays(today, -(keepDays - 1));
    final canPrev = day.isAfter(first);
    final tooOld = day.isBefore(first);

    Future<void> pick() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: day.isBefore(first) ? first : day,
        firstDate: first,
        lastDate: today,
        helpText: 'Saatlik dağılım için gün seç',
        cancelText: 'Vazgeç',
        confirmText: 'Seç',
      );
      if (picked != null) onDateChanged(picked);
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Önceki gün',
                onPressed: canPrev
                    ? () => onDateChanged(Metrics.addDays(day, -1))
                    : null,
                icon: const Icon(Icons.chevron_left),
                color: AppColors.text,
                disabledColor: AppColors.divider,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: pick,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month_outlined,
                            size: 16, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isToday
                                ? 'Bugün · ${Metrics.numericDate(day)}'
                                : '${Metrics.numericDate(day)} '
                                    '${Metrics.longLabel(day)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sonraki gün',
                onPressed: isToday
                    ? null
                    : () => onDateChanged(Metrics.addDays(day, 1)),
                icon: const Icon(Icons.chevron_right),
                color: AppColors.text,
                disabledColor: AppColors.divider,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        HourChart(
          hours: step.hourlyFor(day),
          day: day,
        ),
        if (tooOld)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Saatlik kayıt son 1 yıl için tutulur.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ),
      ],
    );
  }
}
