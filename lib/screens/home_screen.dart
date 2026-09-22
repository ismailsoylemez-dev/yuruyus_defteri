import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../theme/app_theme.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';
import '../widgets/activity_sheet.dart';
import '../widgets/info_card.dart';
import '../widgets/step_ring.dart';
import '../widgets/week_rings.dart';
import '../widgets/water_quick.dart';
import '../utils/achievements.dart';
import '../widgets/achievement_section.dart';
import '../utils/root_nav.dart';
import 'water_screen.dart';
import 'weight_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();
    final waterProvider = context.watch<WaterProvider>();

    final steps = step.todaySteps;
    // Su takibi kapaliysa su ile ilgili her sey gizlenir (null = gosterme).
    final waterOn = settings.waterEnabled;

    final remaining = (settings.goal - steps).clamp(0, settings.goal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bugün'),
        actions: [
          // Kilo takibi
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
              onTap: () => _showStreak(context, step, settings.goal),
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
          const SizedBox(height: 8),
          // Halkaya dokununca grafigin icinde gunun detayi acilir/kapanir.
          _RingWithDetail(
            steps: steps,
            goal: settings.goal,
            breakdown: step.breakdownForDay(DateTime.now()),
            waterMl: waterOn ? waterProvider.todayWater : null,
          ),
          const SizedBox(height: 12),
          // Yuruyor / Duruyor halkanin hemen altinda.
          Center(child: _StatusChip(text: step.walkStatus)),
          const SizedBox(height: 14),
          // Dokununca Ayarlar > Gunluk hedef bolumune gider.
          GestureDetector(
            onTap: RootNav.focusGoal,
            child: StatTile(
              icon: remaining == 0 ? Icons.check_circle_outline : Icons.flag_outlined,
              value: remaining == 0 ? 'Hedef tuttu' : '%${settings.goal <= 0 ? 0 : ((steps / settings.goal) * 100).round()}',
              label: remaining == 0
                  ? '${Metrics.thousands(steps - settings.goal)} adım fazlasıyla'
                  : 'Hedefe ${Metrics.thousands(remaining)} adım kaldı',
            ),
          ),
          const SizedBox(height: 24),
          _TodayCard(
            steps: steps,
            goal: settings.goal,
            waterMl: waterOn ? waterProvider.todayWater : null,
            breakdown: step.breakdownForDay(DateTime.now()),
          ),
          const SizedBox(height: 26),
          const _LatestBadgeCard(),
          const SizedBox(height: 26),
          _WeeklyReportCard(
            weekSteps: step.thisWeekSteps,
            week: step.currentWeek(),
            goal: settings.goal,
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

  /// null: su takibi kapali, su kutusu cikmaz (kalan 3 kutu esit yayilir).
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
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.pick(const Color(0xFF16261D), const Color(0xFFE6F6EC)), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        // Ana kart: yesil ince kenarla diger kartlardan one cikar.
        border: Border.all(
          color: AppColors.accent
              .withValues(alpha: AppColors.isLight ? 0.35 : 0.24),
          width: 1.2,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today, size: 16, color: AppColors.accent),
              const SizedBox(width: 7),
              Text(
                'Bugün',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Tarih kartin sag ustunde sade bir etiket: 21.09.2026 Pazartesi
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${Metrics.numericDate(now)} ${Metrics.longLabel(now)}',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Metrics.thousands(steps),
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 1,
                    ),
                  ),
                  Text(
                    'adım',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Metrics.duration(minutes),
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    'yürünen süre',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 26),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.straighten,
                  color: MetricColors.km,
                  value: '${km.toStringAsFixed(2)} km',
                  label: 'mesafe',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.local_fire_department_outlined,
                  color: MetricColors.kcal,
                  value: '${kcal.toStringAsFixed(0)} kcal',
                  label: 'kalori',
                ),
              ),
              if (waterMl != null)
                Expanded(
                  child: _MiniStat(
                    icon: Icons.water_drop_outlined,
                    color: MetricColors.water,
                    value: '${(waterMl! / 1000).toStringAsFixed(1).replaceAll('.', ',')} L',
                    label: 'su',
                  ),
                ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.flag_outlined,
                  color: AppColors.accent,
                  value: '%$percent',
                  label: 'hedefin',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                hit
                    ? 'Bugün hedefi tuttun, serin güvende. 🔥'
                    : 'Bugün ${Metrics.thousands((goal - today).clamp(0, goal))} '
                        'adım daha atarsan seri ${current + 1} güne çıkar.',
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

/// Adim halkasi + dokununca halkanin altinda acilan gun detayi.
class _RingWithDetail extends StatefulWidget {
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
  State<_RingWithDetail> createState() => _RingWithDetailState();
}

class _RingWithDetailState extends State<_RingWithDetail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.breakdown;
    final percent =
        widget.goal <= 0 ? 0 : (widget.steps * 100 / widget.goal).round();
    return Column(
      children: [
        // Halka ortada; "Su" butonu halkanin sag ust kosesindeki bos alanda.
        SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: StepRing(steps: widget.steps, goal: widget.goal),
              ),
              if (widget.waterMl != null)
                const Positioned(top: 0, right: 0, child: _WaterButton()),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.5)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _Pill(Icons.flag_outlined, AppColors.accent,
                            '%$percent'),
                        _Pill(Icons.straighten, MetricColors.km,
                            '${b.km.toStringAsFixed(2).replaceAll('.', ',')} km'),
                        _Pill(Icons.local_fire_department_outlined,
                            MetricColors.kcal, '${b.kcal.round()} kcal'),
                        _Pill(Icons.timer_outlined, MetricColors.time,
                            Metrics.duration(b.minutes)),
                        if (widget.waterMl != null)
                          _Pill(
                              Icons.water_drop_outlined,
                              MetricColors.water,
                              '${(widget.waterMl! / 1000).toStringAsFixed(1).replaceAll('.', ',')} L'),
                      ],
                    ),
                  ),
                ),
        ),
      ],
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

class _Pill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Pill(this.icon, this.color, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData? icon;
  final Color? _color;
  final String value;
  final String label;
  const _MiniStat({
    this.icon,
    Color? color,
    required this.value,
    required this.label,
  }) : _color = color;

  @override
  Widget build(BuildContext context) {
    final color = _color ?? AppColors.accent;
    return Column(
      children: [
        if (icon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 5),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
        ),
      ],
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

class _LatestBadgeCard extends StatelessWidget {
  const _LatestBadgeCard();

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();
    final all = step.breakdownAllTime;

    if (step.history.isEmpty) return const SizedBox.shrink();

    final stats = AchievementStats.from(
      history: step.history,
      goal: settings.goal,
      heightCm: settings.heightCm,
      totalKcal: all.kcal,
      totalKm: all.km,
    );

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

