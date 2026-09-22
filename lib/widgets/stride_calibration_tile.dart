import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

/// Ayarlar > Vucut: adim boyu. Boydan tahmin ile GPS'le olculen deger
/// yan yana; olculen kullanilsin mi anahtari.
///
/// Olcum: disarida en az ~250 m ve 300 adimlik rota parcalarinda
/// GPS mesafesi / adim (RouteService.syncRecent hesaplar).
class StrideCalibrationTile extends StatelessWidget {
  const StrideCalibrationTile({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final est = Metrics.estimatedStrideMeters(s.heightCm) * 100;
    final cal = s.strideCal;
    final n = s.strideCalCount;
    final ready = cal != null && n >= SettingsProvider.minCalSamples;
    final used = Metrics.strideMeters(s.heightCm) * 100;

    TextStyle dim() => TextStyle(color: AppColors.textDim, fontSize: 12.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.straighten, size: 18, color: MetricColors.km),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Adım uzunluğu: ${used.toStringAsFixed(0)} cm',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Boydan tahmin: ${est.toStringAsFixed(0)} cm', style: dim()),
        Text(
          cal == null
              ? 'GPS ölçümü: henüz yok. Dışarıda Rota açıkken birkaç yürüyüşten sonra ölçülür.'
              : 'GPS ölçümü: ${(cal * 100).toStringAsFixed(0)} cm · $n yürüyüş'
                  '${ready ? '' : ' (en az ${SettingsProvider.minCalSamples} gerekli)'}',
          style: dim(),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'GPS ölçümünü kullan',
                style: TextStyle(color: AppColors.text, fontSize: 13.5),
              ),
            ),
            Switch(
              value: s.strideUseCal,
              onChanged: (v) async {
                await s.setStrideUseCal(v);
                if (context.mounted) {
                  await context.read<StepProvider>().refreshAll(force: true);
                }
              },
            ),
          ],
        ),
        if (cal != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await s.resetStrideCal();
                if (context.mounted) {
                  await context.read<StepProvider>().refreshAll(force: true);
                }
              },
              child: const Text('Ölçümü sıfırla'),
            ),
          ),
      ],
    );
  }
}
