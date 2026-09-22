import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ilk acilista, sistem izin istemlerinden once hangi iznin neden
/// istendigini aciklar. Kullanici "Devam et" dediginde kapanir.
Future<void> showPermissionIntro(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Adımlarını saymak için',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IntroRow(
              icon: Icons.directions_walk,
              color: MetricColors.steps,
              title: 'Fiziksel aktivite',
              text: 'Telefonun adım sensörünü okumak için gerekli. '
                  'Konum veya kamera kullanılmaz.',
            ),
            _IntroRow(
              icon: Icons.notifications_active_outlined,
              color: MetricColors.time,
              title: 'Bildirim',
              text: 'Günlük adım, km, kcal ve su özeti bildirimde görünür; '
                  'hedefe ulaştığında haber verilir.',
            ),
            _IntroRow(
              icon: Icons.battery_charging_full_outlined,
              color: MetricColors.kcal,
              title: 'Pil optimizasyonu',
              text: 'Sayımın arka planda kesilmemesi için Ayarlar > '
                  'Performans bölümünden kısıtlamayı kaldırabilirsin.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Devam et'),
        ),
      ],
    ),
  );
}

class _IntroRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  const _IntroRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12.5,
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
