import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../screens/login_screen.dart';

/// Ayarlar ekranindaki hesap ve bulut yedekleme karti.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final user = AuthService.instance.currentUser;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hesap',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (!AuthService.available)
            Text(
              'Bulut yedekleme bu platformda kullanılamıyor. '
              'Veriler yalnızca bu cihazda tutuluyor.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            )
          else if (user == null)
            Text(
              'Giriş yapılmadı. Veriler yalnızca bu cihazda tutuluyor.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            )
          else
            _UserRow(user: user),
          const SizedBox(height: 14),
          _SyncStatus(step: step),
          if (AuthService.available) ...[
            const SizedBox(height: 14),
            if (user == null)
              OutlinedButton.icon(
                onPressed: () => _openLogin(context),
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Giriş yap / Kayıt ol'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.divider),
                  minimumSize: const Size.fromHeight(46),
                ),
              )
            else if (user.isAnonymous)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openLogin(context, isLinking: true),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text("Hesabı Bağla/Yedekle"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: BorderSide(color: AppColors.divider),
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Çıkış yap'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF5350),
                        side: BorderSide(color: AppColors.divider),
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _syncNow(context),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Şimdi yedekle'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: BorderSide(color: AppColors.divider),
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Çıkış yap'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        side: BorderSide(color: AppColors.divider),
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _confirmDeleteAccount(context),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hesabı ve Verileri Sil'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF5350),
                  side: BorderSide(color: AppColors.divider),
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _openLogin(BuildContext context, {bool isLinking = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => LoginScreen(
          isLinking: isLinking,
          onSkip: () {
            Navigator.of(ctx).pop();
            // Eger baglama tamamlandiysa state'i guncellemek icin
            if (isLinking && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hesap başarıyla bağlandı!')),
              );
              final step = context.read<StepProvider>();
              step.prefs.setSkipLogin(false);
              // rebuild tetiklemek icin settings ekranina bir sinyal gonderilebilir 
              // (stateful olmadigi icin en temizi kullanicinin sayfadan cikip girmesi veya bir sekilde state'in yenilenmesidir, ancak authStateChanges genellikle bunu halleder)
            }
          },
        ),
      ),
    );
  }

  Future<void> _syncNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final step = context.read<StepProvider>();
    await step.flushCloud();
    if (!context.mounted) return;
    final error = step.cloudError;
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Yedekleme tamamlandı.')),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final step = context.read<StepProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text(
          'Adım geçmişin bulutta kalır. Aynı hesapla tekrar giriş '
          'yaptığında geri yüklenir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Çıkış yap',
              style: TextStyle(color: Color(0xFFEF5350)),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;
    // Cikmadan once bekleyen veri gonderilir, sonra baglanti cozulur.
    await step.flushCloud();
    step.attachCloud(null);
    await step.prefs.setSkipLogin(false);
    
    // YALNIZCA yerel verileri temizle, buluttaki silinmesin.
    await step.clearLocalDataOnly();
    if (context.mounted) {
      final water = context.read<WaterProvider>();
      await water.clearLocalDataOnly();
    }
    
    await AuthService.instance.signOut();
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final step = context.read<StepProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Hesabı ve Verileri Sil?'),
        content: const Text(
          'Hesabınız ve buluttaki TÜM verileriniz kalıcı olarak silinecek. '
          'Bu işlem geri alınamaz.\n\nEmin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Hesabımı Sil',
              style: TextStyle(color: Color(0xFFEF5350), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      step.attachCloud(null);
      await step.prefs.setSkipLogin(false);
      await step.clearLocalDataOnly();
      if (context.mounted) {
        final water = context.read<WaterProvider>();
        await water.clearLocalDataOnly();
      }
      
      await AuthService.instance.deleteAccount();
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Hesap silinemedi. Lütfen tekrar giriş yapıp deneyin.')));
    }
  }
}

class _UserRow extends StatelessWidget {
  final User user;
  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context) {
    final photo = user.photoURL;
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.accentSoft,
          backgroundImage: photo != null ? NetworkImage(photo) : null,
          child: photo == null
              ? Icon(Icons.person, color: AppColors.accent, size: 20)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName ?? 'Hesap',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                user.email ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncStatus extends StatelessWidget {
  final StepProvider step;
  const _SyncStatus({required this.step});

  @override
  Widget build(BuildContext context) {
    final error = step.cloudError;
    final synced = step.cloudLastSyncedAt;

    final (IconData icon, Color color, String label) = switch ((
      step.cloudEnabled,
      error,
      synced,
    )) {
      (false, _, _) => (
          Icons.cloud_off_outlined,
          AppColors.textDim,
          'Bulut yedekleme kapalı',
        ),
      (true, final String e, _) => (
          Icons.cloud_off_outlined,
          const Color(0xFFEF5350),
          e,
        ),
      (true, null, final DateTime t) => (
          Icons.cloud_done_outlined,
          AppColors.accent,
          'Son yedek ${_clock(t)}',
        ),
      _ => (
          Icons.cloud_queue_outlined,
          AppColors.textDim,
          'Yedekleme bekliyor',
        ),
    };

    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  static String _clock(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}';
  }
}
