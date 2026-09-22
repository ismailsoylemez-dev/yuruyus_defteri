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

/// Donem ozeti: adim / km / kcal / sure / su. Her olcu kendi renginde,
/// ilk bakista birbirinden ayrilir. [waterMl] null ise su kutusu cikmaz.
class SummaryRow extends StatelessWidget {
  final int steps;
  final double km;
  final double kcal;
  final int minutes;
  final int? waterMl;

  const SummaryRow({
    super.key,
    required this.steps,
    required this.km,
    required this.kcal,
    required this.minutes,
    this.waterMl,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _MiniInfo(
        icon: Icons.directions_walk,
        color: MetricColors.steps,
        value: Metrics.thousands(steps),
        label: 'adım',
      ),
      _MiniInfo(
        icon: Icons.straighten,
        color: MetricColors.km,
        value: km.toStringAsFixed(2).replaceAll('.', ','),
        label: 'km',
      ),
      _MiniInfo(
        icon: Icons.local_fire_department_outlined,
        color: MetricColors.kcal,
        value: kcal.round().toString(),
        label: 'kcal',
      ),
      _MiniInfo(
        icon: Icons.timer_outlined,
        color: MetricColors.time,
        value: Metrics.duration(minutes),
        label: 'süre',
      ),
      if (waterMl != null)
        _MiniInfo(
          icon: Icons.water_drop_outlined,
          color: MetricColors.water,
          value: (waterMl! / 1000).toStringAsFixed(1).replaceAll('.', ','),
          label: 'litre su',
        ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: items[i]),
        ],
      ],
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MiniInfo({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
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
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
