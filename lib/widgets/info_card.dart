import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? iconColor;

  const InfoCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor ?? AppColors.accent, size: 20),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Donem ozeti: ustte adim seridi, altinda 2x2 kutu (km / kcal / sure / su).
/// Her olcu kendi renginde. [waterMl] null ise su kutusu cikmaz, sure
/// satiri tam genislik olur. [goalPercent] verilirse adim seridinde
/// hedef yuzdesi gosterilir.
class SummaryRow extends StatelessWidget {
  final int steps;
  final double km;
  final double kcal;
  final int minutes;
  final int? waterMl;
  final int? goalPercent;

  const SummaryRow({
    super.key,
    required this.steps,
    required this.km,
    required this.kcal,
    required this.minutes,
    this.waterMl,
    this.goalPercent,
  });

  @override
  Widget build(BuildContext context) {
    final stepColor = MetricColors.steps;
    final kmTile = _MetricTile(
      icon: Icons.route_rounded,
      color: MetricColors.km,
      value: km.toStringAsFixed(2).replaceAll('.', ','),
      label: 'kilometre',
    );
    final kcalTile = _MetricTile(
      icon: Icons.local_fire_department_rounded,
      color: MetricColors.kcal,
      value: kcal.round().toString(),
      label: 'kalori (kcal)',
    );
    final timeTile = _MetricTile(
      icon: Icons.timer_rounded,
      color: MetricColors.time,
      value: Metrics.duration(minutes),
      label: 'aktif süre',
    );
    final waterTile = waterMl == null
        ? null
        : _MetricTile(
            icon: Icons.water_drop_rounded,
            color: MetricColors.water,
            value: (waterMl! / 1000).toStringAsFixed(1).replaceAll('.', ','),
            label: 'litre su',
          );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          // Adim seridi
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  stepColor.withValues(alpha: AppColors.isLight ? 0.16 : 0.2),
                  stepColor.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _IconBadge(icon: Icons.directions_walk_rounded, color: stepColor, size: 40),
                const SizedBox(width: 12),
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
                              color: AppColors.text,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                        'adım',
                        style: TextStyle(
                          color: stepColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ),
                    ],
                  ),
                ),
                if (goalPercent != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: stepColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag_rounded, size: 13, color: stepColor),
                        const SizedBox(width: 4),
                        Text(
                          '%$goalPercent',
                          style: TextStyle(
                            color: stepColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: kmTile),
              const SizedBox(width: 8),
              Expanded(child: kcalTile),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: timeTile),
              if (waterTile != null) ...[
                const SizedBox(width: 8),
                Expanded(child: waterTile),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _IconBadge({required this.icon, required this.color, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// 2x2 izgaradaki tek olcu: solda renkli ikon rozeti, sagda deger + etiket.
class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isLight ? 0.06 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(width: 10),
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
                      fontSize: 18,
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
                    fontSize: 11.5,
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
