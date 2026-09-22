import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

class WeeklyReportDialog extends StatelessWidget {
  final int lastWeekSteps;
  final int previousWeekSteps;
  final int goal;

  const WeeklyReportDialog({
    super.key,
    required this.lastWeekSteps,
    required this.previousWeekSteps,
    required this.goal,
  });

  static Future<void> checkAndShow(BuildContext context) async {
    final step = context.read<StepProvider>();
    final settings = context.read<SettingsProvider>();
    
    // Yeterli veri yoksa gosterme
    if (step.history.isEmpty) return;

    final now = DateTime.now();
    // Gecen haftanin pazartesi gunu
    final lastWeekStart = Metrics.weekStart(now.subtract(const Duration(days: 7)));
    final lastWeekKey = Metrics.dayKey(lastWeekStart);

    final prefs = await PrefsService.create();
    final lastReported = prefs.lastWeeklyReport;

    // Zaten gosterildiyse cik
    if (lastReported == lastWeekKey) return;

    // Haftalik toplamlari hesapla
    int getWeekTotal(DateTime start) {
      int total = 0;
      for (int i = 0; i < 7; i++) {
        final d = start.add(Duration(days: i));
        total += step.history[Metrics.dayKey(d)] ?? 0;
      }
      return total;
    }

    final previousWeekStart = lastWeekStart.subtract(const Duration(days: 7));
    
    final lastWeekTotal = getWeekTotal(lastWeekStart);
    final previousWeekTotal = getWeekTotal(previousWeekStart);

    // Eger hic adim yoksa gostermeye gerek yok
    if (lastWeekTotal == 0) {
      await prefs.setLastWeeklyReport(lastWeekKey);
      return;
    }

    // Dialog goster
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => WeeklyReportDialog(
        lastWeekSteps: lastWeekTotal,
        previousWeekSteps: previousWeekTotal,
        goal: settings.goal * 7,
      ),
    );

    // Gosterildigini kaydet
    await prefs.setLastWeeklyReport(lastWeekKey);
  }

  @override
  Widget build(BuildContext context) {
    final diff = lastWeekSteps - previousWeekSteps;
    final isBetter = diff >= 0;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.insights, color: AppColors.accent, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'Haftalık Raporunuz',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Geçen hafta toplam ${Metrics.thousands(lastWeekSteps)} adım attınız.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _StatRow(
              title: 'Önceki Haftaya Göre',
              value: '${isBetter ? '+' : ''}${Metrics.thousands(diff)}',
              color: isBetter ? AppColors.best : AppColors.error,
              icon: isBetter ? Icons.trending_up : Icons.trending_down,
            ),
            const SizedBox(height: 12),
            _StatRow(
              title: 'Haftalık Hedef',
              value: lastWeekSteps >= goal ? 'Ulaşıldı!' : 'Ulaşılamadı',
              color: lastWeekSteps >= goal ? AppColors.best : AppColors.textDim,
              icon: lastWeekSteps >= goal ? Icons.check_circle : Icons.cancel,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Harika, Devam Et!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatRow({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
