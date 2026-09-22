import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/step_provider.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';

/// Ayarlar > Verilerim: bulutla esitlenmis kayitlari okunakli metin olarak
/// panoya kopyalar (Gmail'e yapistir, not al, yazdir).
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cloud = context.select<StepProvider, bool>((s) => s.cloudEnabled);
    return _ActionRow(
      icon: _busy ? Icons.hourglass_top : Icons.content_copy,
      title: 'Verileri panoya kopyala',
      subtitle: cloud
          ? 'Bulutla eşitlenmiş tüm günler: özet, aylık ve günlük tablo'
          : 'Giriş yapılmadı; cihazdaki kayıtlar kopyalanır',
      onTap: _busy ? null : _copy,
    );
  }

  Future<void> _copy() async {
    setState(() => _busy = true);
    final step = context.read<StepProvider>();
    try {
      // Bekleyen yazma once buluta gitsin; kopya buluttakiyle ayni olsun.
      var synced = step.cloudEnabled;
      if (synced) {
        try {
          await step.flushCloud().timeout(const Duration(seconds: 8));
        } catch (_) {
          synced = false;
        }
      }
      final text = BackupService.report(
        step.buildBackup(),
        activeMinutesBetween: step.activeMinutesBetween,
        activeMinutesFor: step.activeMinutesFor,
        breakdown: step.breakdownBetween,
        account: AuthService.available
            ? AuthService.instance.currentUser?.email
            : null,
      );
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      _toast(
        !step.cloudEnabled
            ? 'Cihazdaki kayıtlar panoya kopyalandı.'
            : synced
                ? 'Buluttaki kayıtlar panoya kopyalandı.'
                : 'Bulut şu an erişilemedi; cihazdaki güncel kayıtlar kopyalandı.',
      );
    } catch (e) {
      if (mounted) _toast('Kopyalanamadı: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              error ? AppColors.pick(const Color(0xFF4A2626), const Color(0xFFFDECEC)) : AppColors.surfaceAlt,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.accent, size: 19),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textDim, size: 20),
          ],
        ),
      ),
    );
  }
}
