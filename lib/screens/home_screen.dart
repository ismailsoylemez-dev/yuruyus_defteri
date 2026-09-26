import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../theme/app_theme.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';
import '../widgets/activity_sheet.dart';
import '../widgets/fitness_rings.dart';
import '../widgets/week_rings.dart';
import '../widgets/water_quick.dart';
import '../utils/achievements.dart';
import '../widgets/achievement_section.dart';
import '../widgets/weather_suggestion_card.dart';
import '../utils/root_nav.dart';
import 'water_screen.dart';
import 'weight_screen.dart';
import 'insights_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ConfettiController _confettiController;
  int _lastSteps = -1;
  String? _lastBadgeId;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();
    final waterProvider = context.watch<WaterProvider>();

    final steps = step.todaySteps;
    // Su takibi kapaliysa su ile ilgili her sey gizlenir (null = gosterme).
    final waterOn = settings.waterEnabled;
    final effectiveGoal = step.effectiveGoal > 0 ? step.effectiveGoal : settings.goal;

    // Hedef gecildiyse ve daha once gecilmemisse confetti firlat
    if (_lastSteps != -1 &&
        effectiveGoal > 0 &&
        steps >= effectiveGoal &&
        _lastSteps < effectiveGoal) {
      _confettiController.play();
    }
    _lastSteps = steps;

    if (_lastBadgeId != null && step.lastBadgeId != _lastBadgeId && step.lastBadgeId.isNotEmpty) {
      _confettiController.play();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showBadgeDialog(context, step.lastBadgeId);
      });
    }
    _lastBadgeId = step.lastBadgeId;

    return Stack(
      children: [
        Scaffold(
      appBar: AppBar(
        title: const Text('Bugün'),
        actions: [
          const Center(child: _VisualSummaryChip()),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Kilo takibi',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WeightScreen()),
            ),
            icon: Icon(Icons.monitor_weight_outlined, color: AppColors.textDim),
          ),
          Center(
            child: _StreakChip(
              days: step.currentStreak,
              onTap: () => _showStreak(context, step, step.effectiveGoal),
            ),
          ),
          // Ayarlar alt menude degil, burada (en sagda).
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (step.state == SensorState.denied) const _PermissionBanner(),
          if (step.state == SensorState.unavailable) const _SensorBanner(),
          const _BatteryBanner(),
          const SizedBox(height: 8),
          const WeatherSuggestionCard(),
          const SizedBox(height: 8),
          // Halkaya dokununca grafigin icinde gunun detayi acilir/kapanir.
          _RingWithDetail(
            steps: steps,
            goal: step.effectiveGoal,
            breakdown: step.breakdownForDay(DateTime.now()),
            waterMl: waterOn ? waterProvider.todayWater : null,
          ),
          const SizedBox(height: 12),
          // Yuruyor / Duruyor halkanin hemen altinda.
          Center(child: _StatusChip(text: step.walkStatus)),
          const SizedBox(height: 14),
          _TodayCard(
            steps: steps,
            goal: step.effectiveGoal,
            waterMl: waterOn ? waterProvider.todayWater : null,
            breakdown: step.breakdownForDay(DateTime.now()),
          ),
          const SizedBox(height: 26),
          const _LatestBadgeCard(),
          const SizedBox(height: 26),
          _WeeklyReportCard(
            weekSteps: step.thisWeekSteps,
            week: step.currentWeek(),
            goal: step.effectiveGoal,
            // Detaylar yalnizca acikken hesaplanir.
            details: () => [
              for (final e in step.currentWeek())
                WeekDayDetail.from(
                  steps: e.value,
                  breakdown: step.breakdownForDay(e.key),
                  waterMl: waterOn
                      ? waterProvider.history[Metrics.dayKey(e.key)] ?? 0
                      : null,
                ),
            ],
            onDayTap: (date) {
              showActivitySheet(
                context,
                title: '${Metrics.numericDate(date)} '
                    '${Metrics.longLabel(date)}',
                breakdown: step.breakdownForDay(date),
              );
            },
          ),
        ],
      ),
    ),
    Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: _confettiController,
        blastDirection: pi / 2, // asagi dogru
        maxBlastForce: 25,
        minBlastForce: 10,
        emissionFrequency: 0.05,
        numberOfParticles: 25,
        gravity: 0.2,
      ),
    ),
    ],
    );
  }

  void _showBadgeDialog(BuildContext context, String badgeId) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber, size: 32),
              SizedBox(width: 8),
              Text('Yeni Rozet!'),
            ],
          ),
          content: const Text(
            'Tebrikler, yeni bir rozet kazandınız! Daha fazlasını görmek için Rozetler sayfasına göz atın.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }
}

/// Haftalik rapor: halkalar her zaman, gun detaylari "Detaylari goster"
/// ile acilir (sayfa sade kalsin). Tercih uygulama acikken hatirlanir.
class _WeeklyReportCard extends StatefulWidget {
  final int weekSteps;
  final List<MapEntry<DateTime, int>> week;
  final int goal;
  final List<WeekDayDetail> Function() details;
  final void Function(DateTime) onDayTap;

  const _WeeklyReportCard({
    required this.weekSteps,
    required this.week,
    required this.goal,
    required this.details,
    required this.onDayTap,
  });

  @override
  State<_WeeklyReportCard> createState() => _WeeklyReportCardState();
}

class _WeeklyReportCardState extends State<_WeeklyReportCard> {
  static bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Haftalık rapor',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${Metrics.thousands(widget.weekSteps)} adım',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: WeekRings(
              week: widget.week,
              goal: widget.goal,
              details: _open ? widget.details() : null,
              onDayTap: widget.onDayTap,
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(
              _open ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(_open ? 'Detayları gizle' : 'Detayları göster'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textDim,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final int steps;
  final int goal;

  /// null: su takibi kapali, su cipi cikmaz.
  final int? waterMl;

  /// Normal / tempolu / kosu kirilimi; km, kcal ve sure bunun toplamidir.
  final ActivityBreakdown breakdown;

  const _TodayCard({
    required this.steps,
    required this.goal,
    required this.waterMl,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    final km = breakdown.km;
    final minutes = breakdown.minutes;
    final kcal = breakdown.kcal;
    final percent = goal <= 0 ? 0 : ((steps / goal) * 100).round();
    final left = goal - steps;
    final now = DateTime.now();

    final chips = <Widget>[
      _MetricChip(
        icon: Icons.route_rounded,
        color: MetricColors.km,
        value: '${km.toStringAsFixed(2).replaceAll('.', ',')} km',
        label: 'mesafe',
      ),
      _MetricChip(
        icon: Icons.local_fire_department_rounded,
        color: MetricColors.kcal,
        value: '${kcal.toStringAsFixed(0)} kcal',
        label: 'kalori',
      ),
      if (waterMl != null)
        _MetricChip(
          icon: Icons.water_drop_rounded,
          color: MetricColors.water,
          value: '${(waterMl! / 1000).toStringAsFixed(1).replaceAll('.', ',')} L',
          label: 'su',
        ),
      _MetricChip(
        icon: left <= 0 ? Icons.verified_rounded : Icons.flag_rounded,
        color: left <= 0 ? AppColors.best : AppColors.accent,
        value: goal <= 0
            ? '—'
            : left <= 0
                ? 'Tamam!'
                : Metrics.thousands(left),
        label: goal <= 0 ? 'hedef kapalı' : (left <= 0 ? 'hedef tuttu' : 'adım kaldı'),
      ),
    ];

    // 2'li satirlar; tek kalan son cip tam genislik.
    final rows = <Widget>[];
    for (var i = 0; i < chips.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(Row(
        children: [
          Expanded(child: chips[i]),
          if (i + 1 < chips.length) ...[
            const SizedBox(width: 8),
            Expanded(child: chips[i + 1]),
          ],
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.pick(const Color(0xFF16261D), const Color(0xFFE6F6EC)), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: AppColors.isLight ? 0.35 : 0.28),
          width: 1.2,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.today_rounded, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 8),
              Text(
                'Bugün',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${Metrics.numericDate(now)} ${Metrics.longLabel(now)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Metrics.thousands(steps),
                          maxLines: 1,
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'adım',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_rounded, size: 18, color: MetricColors.time),
                  const SizedBox(width: 4),
                  Text(
                    Metrics.duration(minutes),
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (goal > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (steps / goal).clamp(0.0, 1.0),
                      minHeight: 9,
                      backgroundColor: AppColors.surfaceAlt,
                      color: percent >= 100 ? AppColors.best : AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '%$percent',
                  style: TextStyle(
                    color: percent >= 100 ? AppColors.best : AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ...rows,
          const SizedBox(height: 10),
          // Dokununca normal / tempolu / kosu dokumu acilir.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showActivitySheet(
              context,
              title: 'Bugün - ${Metrics.numericDate(now)}',
              breakdown: breakdown,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ActivityStrip(breakdown: breakdown),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bugun kartindaki renkli olcu cipi: ikon rozeti + deger + etiket.
class _MetricChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MetricChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isLight ? 0.09 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sag ustteki "Gorsel Ozet" girisi: paylasilabilir haftalik/aylik kartlar.
class _VisualSummaryChip extends StatelessWidget {
  const _VisualSummaryChip();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Görsel Özet (haftalık / aylık paylaşım kartı)',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF14B8A6), Color(0xFF8B5CF6), Color(0xFFF59E0B)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const InsightsScreen(weekly: true)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
                  SizedBox(width: 5),
                  Text(
                    'Özet',
                    style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sag ustteki seri rozeti: dokununca ziplar ve seri detayini acar.
class _StreakChip extends StatefulWidget {
  final int days;
  final VoidCallback onTap;
  const _StreakChip({required this.days, required this.onTap});

  @override
  State<_StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends State<_StreakChip> {
  double _scale = 1;

  Future<void> _tap() async {
    setState(() => _scale = 1.25);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (mounted) setState(() => _scale = 1);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final active = days > 0;
    return GestureDetector(
      onTap: _tap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.bestSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? AppColors.best.withValues(alpha: 0.4)
                  : AppColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department,
                size: 15,
                color: active ? AppColors.best : AppColors.textDim,
              ),
              const SizedBox(width: 5),
              Text(
                '$days',
                style: TextStyle(
                  color: active ? AppColors.best : AppColors.textDim,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seri detayi: guncel/en uzun seri, bugunun durumu, son 7 gun.
void _showStreak(BuildContext context, StepProvider step, int goal) {
  final current = step.currentStreak;
  final best = step.bestStreak;
  final today = step.todaySteps;
  final hit = goal > 0 && today >= goal;
  final week = step.lastDays(7);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              size: 56,
              color: current > 0 ? AppColors.best : AppColors.textDim,
            ),
            const SizedBox(height: 6),
            Text(
              current > 0 ? '$current günlük seri' : 'Seri henüz başlamadı',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Günlük hedefi (${Metrics.thousands(goal)} adım) üst üste '
              'tuttuğun gün sayısı.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final e in week)
                  Column(
                    children: [
                      Icon(
                        goal > 0 && e.value >= goal
                            ? Icons.local_fire_department
                            : Icons.circle_outlined,
                        size: 22,
                        color: goal > 0 && e.value >= goal
                            ? AppColors.best
                            : AppColors.divider,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Metrics.shortLabel(e.key),
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                goal <= 0
                    ? 'Günlük hedefin kapalı. Seri takibi için bir hedef belirle.'
                    : (hit
                        ? 'Bugün hedefi tuttun, serin güvende. 🔥'
                        : 'Bugün ${Metrics.thousands((goal - today).clamp(0, goal))} '
                            'adım daha atarsan seri ${current + 1} güne çıkar.'),
                style: TextStyle(color: AppColors.text, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'En uzun serin: $best gün',
              style: TextStyle(color: AppColors.best, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Adim halkasi + Su butonu.
class _RingWithDetail extends StatelessWidget {
  final int steps;
  final int goal;
  final ActivityBreakdown breakdown;

  /// null: su takibi kapali (Su dugmesi ve su hapi gizlenir).
  final int? waterMl;

  const _RingWithDetail({
    required this.steps,
    required this.goal,
    required this.breakdown,
    required this.waterMl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FitnessRings(
            steps: steps, 
            goal: goal,
            kcal: breakdown.kcal.toInt(),
            minutes: breakdown.minutes,
            km: breakdown.km,
          ),
          if (waterMl != null)
            const Positioned(top: 0, right: 0, child: _WaterButton()),
        ],
      ),
    );
  }
}

/// Su takibi: dokununca Su sayfasi acilir, uzun basinca sayfaya girmeden
/// +/- ekleme yapilan kucuk kart cikar.
class _WaterButton extends StatelessWidget {
  const _WaterButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Su takibi (uzun bas: hızlı ekle)',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const WaterScreen()),
        ),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showWaterQuick(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MetricColors.water.withValues(alpha: 0.5),
                  ),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Icon(Icons.water_drop,
                    size: 21, color: MetricColors.water),
              ),
              const SizedBox(height: 4),
              Text(
                'Su',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _StatusChip extends StatelessWidget {
  final String text;
  const _StatusChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final walking = text == 'Yürüyor';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: walking ? AppColors.accent : AppColors.textDim,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pick(const Color(0xFF2A1A1A), const Color(0xFFFDECEC)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pick(const Color(0xFF4A2626), const Color(0xFFF5C2C2))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aktivite izni verilmedi',
            style: TextStyle(color: AppColors.pick(const Color(0xFFEF8A8A), const Color(0xFFC62828)), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Adım sayımı için "Fiziksel aktivite" izni gerekli.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => context.read<StepProvider>().start(),
                child: const Text('Tekrar iste'),
              ),
              TextButton(
                onPressed: () => context.read<StepProvider>().openSettings(),
                child: const Text('Ayarlar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SensorBanner extends StatelessWidget {
  const _SensorBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Cihazda adım sensörü bulunamadı veya veri alınamıyor.',
        style: TextStyle(color: AppColors.textDim, fontSize: 13),
      ),
    );
  }
}

class _BatteryBanner extends StatefulWidget {
  const _BatteryBanner();

  @override
  State<_BatteryBanner> createState() => _BatteryBannerState();
}

class _BatteryBannerState extends State<_BatteryBanner> {
  bool _ignored = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final status = await Permission.ignoreBatteryOptimizations.isGranted;
    if (mounted) setState(() => _ignored = status);
  }

  @override
  Widget build(BuildContext context) {
    if (_ignored || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.pick(const Color(0xFF332200), const Color(0xFFFFF4E5)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.pick(const Color(0xFF664400), const Color(0xFFFFD580))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pil Optimizasyonu Uyarısı',
            style: TextStyle(color: AppColors.pick(const Color(0xFFFFB74D), const Color(0xFFE65100)), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Adımların arka planda doğru sayılabilmesi için uygulamanın pil optimizasyonunu kapatmanız önerilir.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await Permission.ignoreBatteryOptimizations.request();
                  _check();
                },
                child: const Text('Kapat'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LatestBadgeCard extends StatefulWidget {
  const _LatestBadgeCard();

  @override
  State<_LatestBadgeCard> createState() => _LatestBadgeCardState();
}

class _LatestBadgeCardState extends State<_LatestBadgeCard> {
  AchievementStats? _stats;
  int _lastUpdateSteps = -1;

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();

    if (step.history.isEmpty) return const SizedBox.shrink();

    final currentSteps = step.todaySteps;
    // Performans için her adımda değil, 50 adımda bir veya gün değiştiğinde hesapla
    if (_stats == null || (currentSteps - _lastUpdateSteps).abs() >= 50 || currentSteps < _lastUpdateSteps) {
      final all = step.breakdownAllTime;
      _stats = AchievementStats.from(
        history: step.history,
        goal: settings.goal,
        heightCm: settings.heightCm,
        totalKcal: all.kcal,
        totalKm: all.km,
      );
      _lastUpdateSteps = currentSteps;
    }

    final stats = _stats!;

    final unlocked = Achievements.evaluate(stats).where((p) => p.unlocked).toList();
    if (unlocked.isEmpty) return const SizedBox.shrink();

    // En son acilan rozet kaydedilir (StepProvider._checkAchievements).
    // Kayit yoksa (ilk surum) listedeki son acilan gosterilir.
    final id = step.lastBadgeId;
    final latest = unlocked.firstWhere(
      (p) => Achievements.idOf(p.item) == id,
      orElse: () => unlocked.last,
    );

    return GestureDetector(
      onTap: () => showBadgeDialog(context, latest),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.bestSoft.withValues(alpha: 0.5)),
        ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.bestSoft.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(latest.item.icon, color: AppColors.best, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Son Kazanılan Rozet',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  latest.item.title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  latest.item.unit,
                  style: TextStyle(color: AppColors.best, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textDim),
        ],
      ),
      ),
    );
  }
}

