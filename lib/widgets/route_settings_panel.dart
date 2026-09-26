import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/foreground_service.dart';
import '../services/route_service.dart';
import '../theme/app_theme.dart';

/// Rota kaydi ayarlari: ac/kapat, izin durumu, pil, kayitlari silme.
/// Hem Rota ekranindaki ayar penceresinde hem Ayarlar sayfasinda kullanilir.
class RouteSettingsPanel extends StatefulWidget {
  /// Durum degisince (izin/acma-kapama) ust ekran tazelensin.
  final VoidCallback? onChanged;

  /// Rota kayitlari silindiginde.
  final VoidCallback? onCleared;

  const RouteSettingsPanel({super.key, this.onChanged, this.onCleared});

  @override
  State<RouteSettingsPanel> createState() => _RouteSettingsPanelState();
}

class _RouteSettingsPanelState extends State<RouteSettingsPanel>
    with WidgetsBindingObserver {
  RouteStatus _status = const RouteStatus();
  bool _busy = false;
  int _voiceEvery = 0;
  bool _autoPause = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sistem izin ekranindan donuldu: servis tipi ve durum tazelenir.
    if (state == AppLifecycleState.resumed) {
      RouteService.refresh().then((_) => _reload());
    }
  }

  Future<void> _reload() async {
    final s = await RouteService.status();
    final v = await RouteService.voiceEvery();
    final ap = await RouteService.autoPause();
    if (!mounted) return;
    setState(() {
      _status = s;
      _voiceEvery = v;
      _autoPause = ap;
    });
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await RouteService.requestPermissions(background: true);
        if (!ok) {
          final denied = await Permission.locationWhenInUse.isPermanentlyDenied;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(denied
                  ? 'Konum izni kalıcı olarak reddedilmiş. Uygulama ayarlarından izin ver.'
                  : 'Rota kaydı için konum izni gerekli.'),
              action: denied
                  ? const SnackBarAction(label: 'Ayarlar', onPressed: RouteService.openAppSettings)
                  : null,
            ));
          }
          return;
        }
      }
      await RouteService.setEnabled(on);
      await _reload();
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rota kayıtları silinsin mi?'),
        content: const Text(
          'Cihazdaki tüm rota geçmişi silinir. Buluttaki yedek silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RouteService.clear();
    widget.onCleared?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Rota kayıtları silindi.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Otomatik rota',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.active
                        ? 'Şu an kaydediliyor'
                        : s.enabled
                            ? '2 dk kesintisiz yürüyünce GPS açılır'
                            : 'Kapalı · GPS yalnızca antrenmanda açılır',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Switch(
              value: s.enabled,
              onChanged: _busy ? null : _toggle,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Kapalıyken GPS yalnızca "Antrenmanı Başlat" ile açılır; en az pil tüketimi budur. '
          'Açarsan antrenman başlatmadan yürüdüğün yerler de haritaya işlenir: GPS 2 dakika '
          'kesintisiz yürüyünce açılır, 90 saniye durunca kapanır. Uygulama kapalıyken '
          'çalışması için konum izninin "Her zaman izin ver" olması gerekir ve pil tüketimi artar.',
          style: TextStyle(
            color: AppColors.textDim,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.motion_photos_auto_outlined, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Otomatik duraklatma',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Antrenmanda 10 sn adım atılmazsa süre ve mesafe durur, ilk adımda devam eder. '
                    'Bisiklet/bebek arabası gibi adımsız hareketlerde kapat.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Switch(
              value: _autoPause,
              onChanged: (v) {
                setState(() => _autoPause = v);
                RouteService.setAutoPause(v);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.record_voice_over_outlined, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              'Sesli koç',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Antrenmanda süre, mesafe ve ortalama tempoyu ne sıklıkla söylesin?',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Her km')),
              ButtonSegment(value: 5, label: Text('5 dk')),
              ButtonSegment(value: 10, label: Text('10 dk')),
            ],
            selected: {_voiceEvery},
            showSelectedIcon: false,
            onSelectionChanged: (v) {
              setState(() => _voiceEvery = v.first);
              RouteService.setVoiceEvery(v.first);
            },
          ),
        ),
        const SizedBox(height: 14),
        _StatusLine(
          ok: s.fine,
          text: s.fine ? 'Konum izni verildi' : 'Konum izni yok',
        ),
        const SizedBox(height: 6),
        if (s.enabled)
          _StatusLine(
            ok: s.background,
            text: s.background
                ? 'Uygulama kapalıyken de otomatik rota çalışır'
                : 'Kapalıyken otomatik rota için konumu "Her zaman izin ver" yap',
          ),
        const SizedBox(height: 6),
        _StatusLine(
          ok: s.serviceRunning,
          text: s.serviceRunning
              ? 'Arka plan servisi çalışıyor'
              : 'Arka plan servisi kapalı',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (s.enabled && !s.background)
              OutlinedButton.icon(
                onPressed: RouteService.openAppSettings,
                icon: const Icon(Icons.location_on_outlined, size: 18),
                label: const Text('Konum ayarı'),
              ),
            OutlinedButton.icon(
              onPressed: ForegroundService.openBatterySettings,
              icon: const Icon(Icons.battery_saver_outlined, size: 18),
              label: const Text('Pil kısıtı'),
            ),
            TextButton.icon(
              onPressed: _clear,
              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.error),
              label: Text('Kayıtları sil', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool ok;
  final String text;
  const _StatusLine({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          size: 16,
          color: ok ? AppColors.accent : AppColors.best,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
