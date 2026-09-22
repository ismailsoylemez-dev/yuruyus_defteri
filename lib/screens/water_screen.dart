import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../theme/app_theme.dart';
import '../utils/aggregate.dart';
import '../utils/metrics.dart';
import '../widgets/period_chart.dart';
import '../widgets/period_selector.dart';

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  // Halkada kisa sure yukari kayan "+250 ml" etiketi.
  int _flashMl = 0;
  int _flashKey = 0;

  Period _period = Period.week;
  int _offset = 0;

  void _setPeriod(Period p) => setState(() {
        _period = p;
        _offset = 0;
      });

  @override
  Widget build(BuildContext context) {
    final water = context.watch<WaterProvider>();
    final today = water.todayWater;
    final total = water.totalWaterAllTime;
    
    // Su hedefi (Ornek olarak 2500 ml)
    // Ayarlar > Su hedefi.
    final dailyGoal = context.watch<SettingsProvider>().waterGoal;
    final progress = (today / dailyGoal).clamp(0.0, 1.0);

    final range = Aggregate.range(_period, _offset);
    final series = Aggregate.series(water.history, _period, _offset);
    final periodTotal = Aggregate.totalBetween(water.history, range.start, range.end);

    return Scaffold(
      appBar: AppBar(title: const Text('Su Takibi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          // Gunluk Su Durumu
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 16,
                    color: AppColors.water,
                    backgroundColor: AppColors.waterSoft,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.water_drop, color: AppColors.water, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      (today / 1000).toStringAsFixed(today % 1000 == 0 ? 0 : 2),
                      style: TextStyle(
                        color: AppColors.water,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    Text(
                      'Litre',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hedef: ${(dailyGoal / 1000).toStringAsFixed(1)} L',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12),
                    ),
                  ],
                ),
                if (_flashKey > 0)
                  Positioned(
                    top: 26,
                    child: IgnorePointer(
                      child: _WaterFlash(key: ValueKey(_flashKey), ml: _flashMl),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Ekle / cikar: esit genislikte iki sira, altta manuel giris.
          const _RowTitle(icon: Icons.add_circle_outline, text: 'Ekle'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final ml in const [250, 500, 1000]) ...[
                if (ml != 250) const SizedBox(width: 10),
                Expanded(
                  child: _WaterButton(
                    ml: ml,
                    onTap: () => _change(context, water, ml),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const _RowTitle(icon: Icons.remove_circle_outline, text: 'Çıkar'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final ml in const [250, 500, 1000]) ...[
                if (ml != 250) const SizedBox(width: 10),
                Expanded(
                  child: _WaterButton(
                    ml: -ml,
                    onTap: today <= 0 ? null : () => _change(context, water, -ml),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => _manual(context, water),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Manuel giriş (litre)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.water,
                side: BorderSide(color: AppColors.water.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
          // Tum zamanlar: dolu, vurgulu kart (donem kartindan ayri gorunur).
          _AllTimeWaterCard(totalMl: total, days: water.history.values.where((v) => v > 0).length),
          const SizedBox(height: 24),

          PeriodSelector(selected: _period, onChanged: _setPeriod),
          const SizedBox(height: 14),
          RangeBar(
            title: range.title,
            onPrev: () => setState(() => _offset--),
            onNext: _offset < 0 ? () => setState(() => _offset++) : null,
          ),
          const SizedBox(height: 12),
          // Secili donem: cerceveli, sade kart (tum zamanlar kartindan farkli).
          _PeriodWaterCard(
            title: range.title,
            totalMl: periodTotal,
            days: _daysWithWater(water.history, range),
          ),
          const SizedBox(height: 12),
          PeriodChart(
            series: series,
            goal: dailyGoal,
            showGoalLine: _period != Period.year,
            caption: 'Su tüketimi',
            barColor: AppColors.water,
            valueLabel: (p) => _liters(p.value),
            valueLegend: 'litre',
            // Dokununca bilgi grafigin icinde, sutunun ustunde gorunur.
            tipIcon: Icons.local_drink,
            tipLabel: (p) {
              final s = p.start;
              final e = p.end;
              final when = s == null
                  ? p.label
                  : e != null && e != s
                      ? '${Metrics.monthName(s.month)} ${s.year}'
                      : '${Metrics.numericDate(s)} ${Metrics.shortLabel(s)}';
              return p.value <= 0
                  ? '$when · kayıt yok'
                  : '$when · ${_liters(p.value)} L';
            },
            // Gunluk su hedefini tutan gunler 🏅 (yilda aydaki gun sayisi).
            goalDaysOf: _period == Period.month || _period == Period.year
                ? null
                : (a, b) {
              var n = 0;
              for (var d = a; !d.isAfter(b); d = Metrics.addDays(d, 1)) {
                if ((water.history[Metrics.dayKey(d)] ?? 0) >= dailyGoal) n++;
              }
              return n;
                  },
          ),
        ],
      ),
    );
  }

  static String _liters(int ml) {
    final l = ml / 1000;
    return l.toStringAsFixed(l >= 10 ? 0 : 1).replaceAll('.', ',');
  }

  static int _daysWithWater(Map<String, int> h, PeriodRange r) {
    var n = 0;
    h.forEach((k, v) {
      final d = Metrics.tryParseKey(k);
      if (d == null || v <= 0) return;
      if (!d.isBefore(r.start) && !d.isAfter(r.end)) n++;
    });
    return n;
  }

  Future<void> _change(BuildContext context, WaterProvider water, int ml) async {
    HapticFeedback.lightImpact();
    setState(() {
      _flashMl = ml;
      _flashKey++;
    });
    if (ml > 0) {
      await water.addWater(ml);
    } else {
      await water.removeWater(-ml);
    }
    if (context.mounted) _refreshSteps(context);
  }

  Future<void> _manual(BuildContext context, WaterProvider water) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Manuel giriş', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Litre (örn: 1,5)',
            hintStyle: TextStyle(color: AppColors.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Ekle', style: TextStyle(color: AppColors.water)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    final liters = double.tryParse(result.trim().replaceAll(',', '.'));
    if (liters == null || liters <= 0 || liters > 20) return;
    await water.addWater((liters * 1000).round());
    if (context.mounted) _refreshSteps(context);
  }

  void _refreshSteps(BuildContext context) {
    if (context.mounted) {
      context.read<StepProvider>().refreshAll(force: true);
    }
  }
}

class _RowTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RowTitle({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textDim),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ],
      );
}

/// Esit genislikte ekle/cikar dugmesi. Negatif ml cikarma dugmesidir.
class _WaterButton extends StatelessWidget {
  final int ml;
  final VoidCallback? onTap;

  const _WaterButton({required this.ml, this.onTap});

  String get _label {
    final a = ml.abs();
    final v = a >= 1000 ? '${a ~/ 1000} L' : '$a ml';
    return ml < 0 ? '−$v' : '+$v';
  }

  IconData get _icon => switch (ml.abs()) {
        250 => Icons.local_drink_outlined,
        500 => Icons.coffee_outlined,
        _ => Icons.water_drop_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final negative = ml < 0;
    final enabled = onTap != null;
    final color = negative ? AppColors.textDim : AppColors.water;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: negative ? AppColors.surface : AppColors.waterSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: negative ? 48 : 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: negative
                ? Center(
                    child: Text(
                      _label,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_icon, color: color, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        _label,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Secili donem: cerceveli, sade kart.
class _PeriodWaterCard extends StatelessWidget {
  final String title;
  final int totalMl;
  final int days;

  const _PeriodWaterCard({
    required this.title,
    required this.totalMl,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final avg = days == 0 ? 0 : totalMl ~/ days;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.date_range_outlined, color: AppColors.water, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEÇİLİ DÖNEM',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_WaterScreenState._liters(totalMl)} L',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                days == 0
                    ? 'kayıt yok'
                    : 'günlük ort. ${_WaterScreenState._liters(avg)} L',
                style: TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simdiye kadar: dolu mavi, vurgulu kart.
class _AllTimeWaterCard extends StatelessWidget {
  final int totalMl;
  final int days;

  const _AllTimeWaterCard({required this.totalMl, required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E5AA8), Color(0xFF123056)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.waves, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ŞİMDİYE KADAR TOPLAM',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_WaterScreenState._liters(totalMl)} litre',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$days gün',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Ekle/cikar sonrasi halkanin ustunde yukari kayip kaybolan etiket.
class _WaterFlash extends StatelessWidget {
  final int ml;

  const _WaterFlash({super.key, required this.ml});

  @override
  Widget build(BuildContext context) {
    final add = ml > 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(
        opacity: t < 0.6 ? 1 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, -28 * t), child: child),
      ),
      child: Text(
        '${add ? '+' : '−'}${ml.abs()} ml',
        style: TextStyle(
          color: add ? AppColors.water : const Color(0xFFEF5350),
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
