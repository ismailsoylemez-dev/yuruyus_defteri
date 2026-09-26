import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../services/foreground_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';
import '../widgets/account_section.dart';
import '../utils/root_nav.dart';
import '../widgets/backup_section.dart';
import '../widgets/route_settings_panel.dart';
import '../widgets/stride_calibration_tile.dart';
import 'weight_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatelessWidget {
  /// true ise acilista "Gunluk hedef" bolumune kayar ve vurgular.
  final bool focusGoal;

  const SettingsScreen({super.key, this.focusGoal = false});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final step = context.watch<StepProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        actions: [
          IconButton(
            tooltip: 'Hakkında',
            onPressed: () => _showAbout(context),
            icon: Icon(Icons.info_outline, color: AppColors.textDim),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const AccountSection(),
          const _GroupLabel('HEDEFLER'),
          // Bugun > "Hedefe ... kaldi" kartindan gelinince buraya kayar.
          _GoalAnchor(
            autoFocus: focusGoal,
            child: _Section(
              title: 'Günlük hedef',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SwitchRow(
                    label: 'Akıllı Hedef',
                    sub: 'Son 7 günün ortalamasına göre günlük hedef belirler.',
                    value: settings.smartGoal,
                    onChanged: (v) async {
                      await settings.setSmartGoal(v);
                      step.cloud?.saveSmartGoal(v);
                      step.refreshAll(force: true);
                    },
                  ),
                  if (!settings.smartGoal) _GoalSlider(settings: settings, step: step),
                  if (!settings.smartGoal) _GoalSuggestion(step: step, settings: settings),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Su takibi',
            subtitle: settings.waterEnabled
                ? 'Su sayfasındaki günlük hedef ve 🏅 rozetleri buna göre.'
                : 'Kapalı: su düğmesi, su satırları, bildirim ve widget\'taki su gizlenir. Kayıtların silinmez.',
            child: Column(
              children: [
                _SwitchRow(
                  label: 'Su takibi',
                  sub: 'Kapatınca su her yerden gizlenir',
                  value: settings.waterEnabled,
                  onChanged: (v) async {
                    await settings.setWaterEnabled(v);
                    // Kalici bildirim ve widget'taki su hucresi de guncellensin.
                    await step.refreshAll(force: true);
                  },
                ),
                if (settings.waterEnabled) ...[
                  const Divider(height: 22),
                  _WaterGoalSlider(settings: settings),
                ],
              ],
            ),
          ),
          const _GroupLabel('VÜCUT'),
          _Section(
            title: 'Vücut bilgileri',
            subtitle: 'Mesafe ve kalori hesabı için kullanılır.',
            child: Column(
              children: [
                _NumberField(
                  label: 'Boy (cm)',
                  value: settings.heightCm.toString(),
                  onSubmit: (v) {
                    final n = int.tryParse(v);
                    if (n != null) {
                      settings.setHeight(n);
                      step.refreshAll(force: true);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _NumberField(
                  label: 'Kilo (kg)',
                  value: settings.weightKg.toStringAsFixed(1).replaceAll('.0', ''),
                  onSubmit: (v) async {
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    if (n != null) {
                      // Bugunun kilo kaydi olarak da yazilir (trend grafigi).
                      await settings.addWeight(DateTime.now(), n);
                      step.refreshAll(force: true);
                    }
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const WeightScreen()),
                    ),
                    icon: const Icon(Icons.monitor_weight_outlined, size: 18),
                    label: const Text('Kilo takibi ve trend'),
                  ),
                ),
                const Divider(height: 18),
                const StrideCalibrationTile(),
              ],
            ),
          ),
          const _GroupLabel('UYGULAMA'),
          _Section(
            title: 'Görünüm',
            subtitle: 'Varsayılan koyu tema. AMOLED: tam siyah zemin '
                '(OLED ekranda pil tasarrufu).',
            child: ValueListenableBuilder<AppThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (context, mode, _) => SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: AppThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Koyu'),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.amoled,
                      icon: Icon(Icons.contrast),
                      label: Text('AMOLED'),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Açık'),
                    ),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) {
                    final m = v.first;
                    context.read<StepProvider>().prefs.setThemeMode(m.name);
                    ThemeController.set(m);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Sensör',
            subtitle: 'Adımları telefonun donanım adım sayacından okur. '
                'Sayım durursa veya izin sıfırlanırsa buradan yeniden bağlayın.',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        switch (step.state) {
                          SensorState.running => 'Aktif - veri alınıyor',
                          SensorState.demo => 'Demo modu (web/masaüstü - sahte veri)',
                          SensorState.denied => 'İzin verilmedi',
                          SensorState.unavailable => 'Sensör bulunamadı',
                          SensorState.idle => 'Başlatılmadı',
                        },
                        style: TextStyle(color: AppColors.textDim, fontSize: 13.5),
                      ),
                    ),
                    _BusyButton(
                      label: step.state == SensorState.running
                          ? 'Yeniden bağlan'
                          : 'İzin iste',
                      task: () async {
                        await step.start();
                        return switch (step.state) {
                          SensorState.running =>
                            'Sensör bağlandı - izin: ${step.permissionLabel}',
                          SensorState.denied =>
                            'İzin verilmedi (${step.permissionLabel})',
                          SensorState.unavailable =>
                            'Sensör okunamadı: ${step.lastError ?? 'bilinmiyor'}',
                          SensorState.demo => 'Demo modu - gerçek sensör yok',
                          SensorState.idle => 'Sensör başlatılamadı',
                        };
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pil Optimizasyonu\n(Arka plan sayımı için kapatılmalı)',
                        style: TextStyle(color: AppColors.textDim, fontSize: 13.5),
                      ),
                    ),
                    _BusyButton(
                      label: 'Kontrol Et',
                      task: () async {
                        final status = await Permission.ignoreBatteryOptimizations.status;
                        if (status.isGranted) {
                          return 'Pil optimizasyonu zaten kapalı, arka plan takibi güvende.';
                        } else {
                          final result = await Permission.ignoreBatteryOptimizations.request();
                          if (result.isGranted) {
                            return 'Harika! Optimizasyon kapatıldı.';
                          } else {
                            return 'Ayarlardan optimizasyon kapatılmadı.';
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Bildirimler',
            child: Column(
              children: [
                _SwitchRow(
                  label: 'Hedef tamamlandı',
                  sub: 'Günlük hedefe ulaşınca bildirim',
                  value: settings.notifyGoal,
                  onChanged: (v) async {
                    if (v) await NotificationService.requestPermission();
                    await settings.setNotifyGoal(v);
                  },
                ),
                const Divider(height: 22),
                _SwitchRow(
                  label: 'Akşam hatırlatması',
                  sub: 'Hedef tutulmadıysa 20:00\'de kalan adımla',
                  value: settings.notifyEvening,
                  onChanged: (v) async {
                    if (v) {
                      await NotificationService.requestPermission();
                      await NotificationService.scheduleEvening();
                    } else {
                      await NotificationService.cancelEvening();
                    }
                    await settings.setNotifyEvening(v);
                  },
                ),
                const Divider(height: 22),
                _SwitchRow(
                  label: 'Haftalık özet',
                  sub: 'Pazar 20:30',
                  value: settings.notifyWeekly,
                  onChanged: (v) async {
                    if (v) {
                      await NotificationService.requestPermission();
                      await NotificationService.scheduleWeekly();
                    } else {
                      await NotificationService.cancelWeekly();
                    }
                    await settings.setNotifyWeekly(v);
                  },
                ),
                const Divider(height: 22),
                _SwitchRow(
                  label: 'Hareketsizlik uyarısı',
                  sub: '09:00 - 20:00 arası 2 saat hareketsiz kalınca',
                  value: settings.notifyStandup,
                  onChanged: (v) async {
                    if (v) await NotificationService.requestPermission();
                    await settings.setNotifyStandup(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Konum ve rota',
            subtitle: 'Yürüdüğün yerleri haritada iz olarak kaydeder. '
                'Veriler cihazda ve kendi bulut hesabında kalır.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RouteSettingsPanel(),
                const SizedBox(height: 4),
                TextButton.icon(
                  // Rota artik alt menude: Ayarlar kapanir, Rota sekmesi acilir.
                  onPressed: () => RootNav.go(RootNav.route),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Rota haritasını aç'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _Section(
            title: 'Performans',
            subtitle:
                'Arka plan servisinin uyutulmaması için pil kısıtlamasını kaldırın.',
            child: _BatteryOptimizationRow(),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Tanılama',
            subtitle: 'Sorun olursa buradaki satırları paylaş.',
            child: Column(
              children: [
                _DiagRow('İzin durumu', step.permissionLabel),
                _DiagRow('Sensör olayı', '${step.eventCount} adet'),
                _DiagRow(
                  'Ham sayaç',
                  step.lastRawSensor < 0 ? 'veri yok' : '${step.lastRawSensor}',
                ),
                _DiagRow(
                  'Sensör kanalı',
                  step.fastSensor ? 'hızlı (donanım)' : 'eklenti (toplu)',
                ),
                _DiagRow(
                  'Arka plan servisi',
                  step.backgroundRunning ? 'çalışıyor' : 'kapalı',
                ),
                _DiagRow('Bugün', '${step.todaySteps}'),
                _DiagRow('Widget yenileme', '${WidgetService.updateCount}'),
                if (step.lastError != null) ...[
                  const Divider(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      'Sensör hatası: ${step.lastError}',
                      style: TextStyle(
                        color: AppColors.pick(const Color(0xFFEF8A8A), const Color(0xFFC62828)),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
                if (WidgetService.lastError != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      'Widget hatası: ${WidgetService.lastError}',
                      style: TextStyle(
                        color: AppColors.pick(const Color(0xFFEF8A8A), const Color(0xFFC62828)),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => step.openSettings(),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Uygulama izin ayarlarını aç'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Ana ekran widget',
            subtitle:
                'Widget en sik 30 dakikada bir kendi yenilenir; uygulama açıkken anında güncellenir.',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ana ekrana uzun bas > Widget\'lar > Yürüyüş Defteri',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ),
                _BusyButton(
                  label: 'Şimdi yenile',
                  task: () async {
                    final before = WidgetService.updateCount;
                    await step.refreshWidget(force: true);
                    if (WidgetService.updateCount > before) {
                      return 'Widget güncellendi '
                          '(${WidgetService.updateCount}. yenileme)';
                    }
                    return WidgetService.lastError != null
                        ? 'Widget hatası: ${WidgetService.lastError}'
                        : 'Güncellenecek widget bulunamadı. '
                            'Önce ana ekrana ekleyin.';
                  },
                ),
              ],
            ),
          ),
          const _GroupLabel('VERİ'),
          const _Section(
            title: 'Verilerim',
            subtitle: 'Kayıtlarını okunaklı bir tablo olarak panoya kopyala; '
                'Gmail\'e yapıştırıp kendine gönderebilir, not olarak '
                'saklayabilir veya yazdırabilirsin.',
            child: BackupSection(),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Veri',
            child: OutlinedButton.icon(
              onPressed: () => _confirmReset(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF5350),
                minimumSize: const Size.fromHeight(46),
                side: BorderSide(color: AppColors.pick(const Color(0xFF4A2626), const Color(0xFFF5C2C2))),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              label: const Text('Tüm kayıtları sil'),
            ),
          ),
          const _GroupLabel('HAKKINDA'),
          _Section(
            title: 'Hakkında',
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Geliştirici',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'İSMAİL SÖYLEMEZ',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final versionText = snapshot.hasData ? 'v${snapshot.data!.version}' : '...';
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Sürüm',
                          style: TextStyle(color: AppColors.textDim, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          versionText,
                          style: TextStyle(
                            color: AppColors.text.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAbout(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.directions_walk,
                  color: AppColors.accent, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              'Yürüyüş Defteri',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'v1.0.0',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            const Divider(height: 26),
            Text(
              'GELİŞTİRİCİ',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _DeveloperAvatar(size: 38, radius: 19),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'İSMAİL SÖYLEMEZ',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Reklamsız, izlemesiz.\n'
              'Veriler cihazda tutulur; giriş yapıldığında yalnızca '
              'kendi Google hesabına yedeklenir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final provider = context.read<StepProvider>();
    final water = context.read<WaterProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Kayıtlar silinsin mi?'),
        content: const Text('Tüm günlük adım geçmişi kalıcı olarak silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
    if (ok == true) {
      await provider.resetData();
      // Su kaydi da bellekten silinir; yoksa ilk su eklemede eski gunler
      // geri yazilip buluta gonderiliyordu.
      await water.resetData();
    }
  }
}

/// Ayarlar > Hakkinda bolumundeki gelistirici gorseli.
///
/// Kare kutuya kirpilir (BoxFit.cover), kaynak 320x320 oldugu icin 3x
/// ekranlarda da net kalir ve buyuyup kuculmez; kutu boyutu cagiran
/// taraftan gelir. Asset bulunamazsa eski ikona duser, boylece arayuzde
/// bos kutu olusmaz.
class _DeveloperAvatar extends StatelessWidget {
  final double size;

  /// Kose yaricapi. size / 2 verilirse tam daire olur.
  final double radius;

  const _DeveloperAvatar({required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      // Olcu Container'dan gelir; Image ayrica boyut vermez ki kenarlik
      // payi yuzunden 2 px tasma olusmasin.
      child: Image.asset(
        'assets/about_ismail.jpg',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(
          Icons.code,
          color: AppColors.accent,
          size: size * 0.48,
        ),
      ),
    );
  }
}

/// Gunluk hedef kaydirici.
///
/// Eskiden [Slider.onChanged] her karede SharedPreferences'a yaziyordu;
/// tek surukleme onlarca disk yazmasi ve notifyListeners uretiyordu.
/// Deger surukleme boyunca yerel tutulur, yalnizca birakilinca kaydedilir.
class _GoalSlider extends StatefulWidget {
  final SettingsProvider settings;
  final StepProvider step;

  const _GoalSlider({required this.settings, required this.step});

  @override
  State<_GoalSlider> createState() => _GoalSliderState();
}

class _GoalSliderState extends State<_GoalSlider> {
  double? _draft;

  Future<void> _showManualInputDialog() async {
    final controller = TextEditingController(text: widget.settings.goal.toString());
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Hedef Belirle', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Örn: 10000',
            hintStyle: TextStyle(color: AppColors.textDim),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.divider)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('İptal', style: TextStyle(color: AppColors.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('Kaydet', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final parsed = int.tryParse(result);
      if (parsed != null && parsed >= 500) {
        await widget.settings.setGoal(parsed);
        await widget.step.refreshAll(force: true);
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = widget.settings.goal;
    // Kaydiricinin ust siniri 25000, ama hedef (oneri veya yedekten geri
    // yukleme ile) 40000'e kadar cikabiliyor. Baslikta clamp'li deger
    // yazilirsa 25000 ustu hedefler yanlis gorunur.
    final sliderValue =
        (_draft ?? stored.toDouble()).clamp(1000.0, 25000.0);
    final shown = _draft?.round() ?? stored;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${Metrics.thousands(shown)} adım',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit, color: AppColors.textDim, size: 20),
              onPressed: _showManualInputDialog,
              tooltip: 'Elle gir',
            ),
          ],
        ),
        Slider(
          value: sliderValue,
          min: 1000,
          max: 25000,
          divisions: 48,
          onChanged: (v) => setState(() => _draft = v),
          onChangeEnd: (v) async {
            await widget.settings.setGoal(v.round());
            if (!mounted) return;
            setState(() => _draft = null);
            await widget.step.refreshAll(force: true);
          },
        ),
      ],
    );
  }
}

/// Tiklaninca islem bitene kadar spinner gosterir, sonucu SnackBar ile bildirir.
class _BusyButton extends StatefulWidget {
  final String label;
  final Future<String> Function() task;

  const _BusyButton({required this.label, required this.task});

  @override
  State<_BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<_BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    String message;
    try {
      message = await widget.task();
    } catch (e) {
      message = 'Hata: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceAlt,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _busy ? null : _run,
      child: _busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            )
          : Text(widget.label),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sub,
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _GoalSuggestion extends StatelessWidget {
  final StepProvider step;
  final SettingsProvider settings;

  const _GoalSuggestion({required this.step, required this.settings});

  Future<void> _apply(int value) async {
    await settings.setGoal(value);
    await step.refreshAll(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final last30 = step.lastDays(30).map((e) => e.value).where((v) => v > 0).toList();
    if (last30.length < 7) return const SizedBox.shrink();

    final avg = last30.reduce((a, b) => a + b) ~/ last30.length;
    // setGoal ile ayni sinira kirpilir; aksi halde sinir ustu bir oneri
    // uygulandiginda hedef 40000'de kalip banner hic kaybolmuyordu.
    final suggested = (((avg * 1.1) / 500).round() * 500).clamp(1000, 40000);
    if (suggested <= 0 || (suggested - settings.goal).abs() < 500) {
      return const SizedBox.shrink();
    }

    final higher = suggested > settings.goal;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            higher ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: higher ? AppColors.accent : AppColors.textDim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Son 30 gün ortalaman ${Metrics.thousands(avg)} adım. '
              'Hedefi ${Metrics.thousands(suggested)} yapabilirsin.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => _apply(suggested),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  const _DiagRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
          SelectableText(
            value,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pil optimizasyonu durumu. Ayarlar ekranindan donunce durumu yeniden
/// sorgulamak icin kendi state'ini tutar; FutureBuilder tek basina
/// future'i yeniden kurmadigi icin eski deger ekranda kalirdi.
class _BatteryOptimizationRow extends StatefulWidget {
  const _BatteryOptimizationRow();

  @override
  State<_BatteryOptimizationRow> createState() =>
      _BatteryOptimizationRowState();
}

class _BatteryOptimizationRowState extends State<_BatteryOptimizationRow>
    with WidgetsBindingObserver {
  bool? _ignoring;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sistem ayarlarindan geri donuldugunde durumu tazele.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      final v = await ForegroundService.isIgnoringBatteryOptimizations();
      if (mounted) setState(() => _ignoring = v);
    } catch (_) {
      if (mounted) setState(() => _ignoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ignoring = _ignoring ?? false;
    return OutlinedButton.icon(
      onPressed: ignoring
          ? null
          : () async {
              try {
                await ForegroundService.openBatterySettings();
              } catch (e) {
                debugPrint('Pil ayarlari acilamadi: $e');
              }
              await _check();
            },
      icon: Icon(
        ignoring ? Icons.check_circle : Icons.battery_charging_full_outlined,
        size: 18,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: ignoring ? Colors.green : AppColors.accent,
        disabledForegroundColor: Colors.green,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      label: Text(
        ignoring ? 'Optimizasyon kapatıldı' : 'Pil optimizasyonunu kapat',
      ),
    );
  }
}

/// Ayarlar gruplari arasindaki kucuk baslik (HEDEFLER, VUCUT ...).
class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
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
            title,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onSubmit;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onSubmit,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Deger disaridan degistiyse (yedekten geri yukleme, buluttan senkron,
    // hedef onerisi) alan eski degerde kaliyordu; ilk disari dokunusta
    // onSubmit eski degeri geri yaziyor ve yeni degeri siliyordu.
    if (widget.value != oldWidget.value && widget.value != _c.text) {
      _c.text = widget.value;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: TextStyle(color: AppColors.textDim, fontSize: 14),
          ),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              // Deger degismediyse yazmaya gerek yok: her disari dokunusta
              // diske yazip widget'i yeniden render ediyordu.
              if (_c.text != widget.value) widget.onSubmit(_c.text);
            },
            onSubmitted: widget.onSubmit,
          ),
        ),
      ],
    );
  }
}

/// Hedef bolumunu gorunur yapar ve kisa sure vurgular.
class _GoalAnchor extends StatefulWidget {
  final Widget child;
  final bool autoFocus;
  const _GoalAnchor({required this.child, this.autoFocus = false});

  @override
  State<_GoalAnchor> createState() => _GoalAnchorState();
}

class _GoalAnchorState extends State<_GoalAnchor> {
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    RootNav.goalFocus.addListener(_focus);
    if (widget.autoFocus) _focus();
  }

  @override
  void dispose() {
    RootNav.goalFocus.removeListener(_focus);
    super.dispose();
  }

  void _focus() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        alignment: 0.1,
      );
      if (!mounted) return;
      setState(() => _flash = true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _flash ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Gunluk su hedefi: 1 - 6 L, 250 ml adim. Surukleme sirasinda yalnizca
/// ekran guncellenir, birakinca kaydedilir.
class _WaterGoalSlider extends StatefulWidget {
  final SettingsProvider settings;
  const _WaterGoalSlider({required this.settings});

  @override
  State<_WaterGoalSlider> createState() => _WaterGoalSliderState();
}

class _WaterGoalSliderState extends State<_WaterGoalSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final ml = (_drag ?? widget.settings.waterGoal.toDouble()).clamp(1000.0, 6000.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.water_drop_outlined,
                color: AppColors.water, size: 20),
            const SizedBox(width: 8),
            Text(
              '${(ml / 1000).toStringAsFixed(2).replaceAll('.', ',')} L',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '≈ ${(ml / 250).round()} bardak',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.water,
            thumbColor: AppColors.water,
            inactiveTrackColor: AppColors.waterSoft,
          ),
          child: Slider(
            value: ml,
            min: 1000,
            max: 6000,
            divisions: 20,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) async {
              await widget.settings.setWaterGoal(v.round());
              if (mounted) setState(() => _drag = null);
            },
          ),
        ),
      ],
    );
  }
}
