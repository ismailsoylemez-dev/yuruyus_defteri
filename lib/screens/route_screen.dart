import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:screenshot/screenshot.dart';
import 'package:shimmer/shimmer.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/route_service.dart';
import '../theme/app_theme.dart';
import '../utils/aggregate.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';
import '../utils/root_nav.dart';
import '../widgets/period_selector.dart';
import '../widgets/share_card_widget.dart';
import '../widgets/workout_share_card.dart';
import 'heatmap_screen.dart';
import '../providers/settings_provider.dart';

Widget modernTileBuilder(
  BuildContext context,
  Widget tileWidget,
  TileImage tile,
) {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      0.33, 0.59, 0.11, 0, 15,
      0.33, 0.59, 0.11, 0, 15,
      0.33, 0.59, 0.11, 0, 15,
      0,    0,    0,    1, 0,
    ]),
    child: tileWidget,
  );
}

/// Rota haritasi: alt menudeki "Rota" sekmesi (embedded) ya da Gecmis'teki
/// "Rotayi gor" ile acilan ayri sayfa. Gun / Hafta / Ay / Yil filtresi
/// Gecmis sayfasindakiyle aynidir; takvim ikonuyla belirli bir gune gidilir.
class RouteScreen extends StatefulWidget {
  /// Verilirse sayfa dogrudan o gunle acilir.
  final DateTime? initialDate;

  /// Alt menu sekmesi olarak mi gosteriliyor. Sekmeler IndexedStack'te
  /// hep canli durdugu icin harita, zamanlayici ve "Konumu ac" penceresi
  /// yalnizca sekme gorunurken calisir.
  final bool embedded;

  const RouteScreen({super.key, this.initialDate, this.embedded = false});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> with WidgetsBindingObserver {
  static const _fallbackCenter = LatLng(39.0, 35.0); // Turkiye
  static const _dotLimit = 1500;

  final _boundaryKey = GlobalKey();
  bool _isSharing = false;

  final _map = MapController();
  Period _period = Period.day;
  int _offset = 0;
  RouteData _data = RouteData.empty;
  RouteStatus _status = const RouteStatus();
  bool _loading = true;
  bool _mapReady = false;
  int _loadToken = 0;
  Timer? _live;

  List<Workout> _pastWorkouts = [];

  /// Cihazin bilinen son konumu: rota yokken harita buraya odaklanir.
  LatLng? _me;

  /// Haritanin acilis merkezi (en son bilinen konum). Okunana kadar harita
  /// cizilmez; boylece acilista Turkiye/dunya geneli hic gorunmez.
  LatLng? _startCenter;
  bool _centerReady = false;
  bool _initialFitDone = false;

  /// "Konumu ac" penceresi bu acilista bir kez sorulur.
  bool _askedLocation = false;

  /// Sekme en az bir kez gorundu mu (harita ancak o zaman kurulur).
  bool _shown = false;

  /// Antrenmanda harita konumu takip etsin mi (haritayi elle kaydirinca kapanir).
  bool _follow = true;

  /// Antrenman sesli bildirimleri kapali mi (baslatmadan once de ayarlanir).
  bool _muted = false;

  /// Baslat butonunun ustundeki hedef secimi (son secim hatirlanir).
  static _Goal _goal = _Goal.free;

  bool get _visible =>
      !widget.embedded || RootNav.tab.value == RootNav.route;

  bool get _todayView => _offset == 0 && _period == Period.day;

  void _onTab() {
    if (!mounted || !_visible) return;
    _activate();
  }

  /// Kisayol / Hizli Ayarlar: "Antrenman baslat".
  void _onStartRequest() {
    if (!RootNav.startWorkout.value || !mounted) return;
    RootNav.startWorkout.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_workout.active) return; // zaten suruyor: panel gorunur
      if (!_todayView) {
        setState(() {
          _period = Period.day;
          _offset = 0;
        });
        _load(fit: true);
      }
      _startWorkout();
    });
  }

  // ---- Yuruyus kaydi ----
  WorkoutStatus _workout = const WorkoutStatus();
  Timer? _workoutTick;
  int _tickCount = 0;

  Future<void> _refreshWorkout() async {
    final w = await RouteService.workoutStatus();
    if (!mounted) return;
    setState(() => _workout = w);
    if (w.active && _visible) {
      _workoutTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_visible) return;
        _pollWorkout();
      });
    } else {
      _workoutTick?.cancel();
      _workoutTick = null;
    }
  }

  var _polling = false;
  Future<void> _pollWorkout() async {
    if (_polling) return;
    _polling = true;
    try {
      final w = await RouteService.workoutStatus();
      if (!mounted) return;
      final goalJustDone = w.goalDone && !_workout.goalDone;
      setState(() => _workout = w);
      if (goalJustDone) {
        HapticFeedback.heavyImpact();
        _snack('Tebrikler, hedefe ulaştın! 🎉');
      }
      if (!w.active) {
        // Bildirimden "Bitir" ile bitirildi: liste ve iz tazelenir.
        _workoutTick?.cancel();
        _workoutTick = null;
        _loadPastWorkouts();
        _load(fit: true);
        RouteService.syncWorkouts();
        return;
      }
      _tickCount++;
      // Canli takip: 3 sn'de bir konum, 5 sn'de bir iz tazelenir.
      if (_tickCount % 3 == 0) _followMe();
      if (_tickCount % 5 == 0) _load();
    } finally {
      _polling = false;
    }
  }

  Future<void> _followMe() async {
    final s = await RouteService.status();
    if (!mounted) return;
    setState(() => _status = s);
    final p = s.lastFix;
    if (p == null) return;
    setState(() => _me = p);
    if (_follow && _mapReady && _todayView) {
      try {
        _map.move(p, _map.camera.zoom < 15 ? 16 : _map.camera.zoom);
      } catch (_) {}
    }
  }

  Future<bool> _ensureGps() async {
    if (!_status.fine) {
      final ok = await RouteService.requestPermissions();
      if (!ok) {
        _snack('Antrenman rotası için konum izni gerekli.');
        return false;
      }
      await RouteService.refresh();
    }
    var s = await RouteService.status();
    if (!s.locationOn) {
      await RouteService.requestLocationOn();
      s = await RouteService.status();
      if (!s.locationOn) {
        _snack('Telefonun Konum özelliği kapalı.');
        return false;
      }
    }
    if (mounted) setState(() => _status = s);
    return true;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
      ));
  }

  Future<void> _shareRoute() async {
    if (_isSharing) return;
    try {
      setState(() => _isSharing = true);
      await Future.delayed(const Duration(milliseconds: 300));

      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _snack('Harita görüntüsü alınamadı.');
        return;
      }

      final mapImage = await boundary.toImage(pixelRatio: 2.0);
      final mapByteData = await mapImage.toByteData(format: ui.ImageByteFormat.png);
      if (mapByteData == null) return;
      if (!mounted) return;

      final controller = ScreenshotController();
      final shareBytes = await controller.captureFromWidget(
        ShareCardWidget(
          mapImage: mapByteData.buffer.asUint8List(),
          distance: _data.distanceM / 1000,
          minutes: (_data.durationMs / 60000).round(),
          kcal: ((_data.durationMs / 60000) * 5).round(),
          date: _range.start,
        ),
        delay: const Duration(milliseconds: 100),
        context: context,
      );

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/route_share.png');
      await file.writeAsBytes(shareBytes);

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'İşte bugünkü yürüyüş rotam ve istatistiklerim! #YürüyüşDefteri',
      );
    } catch (e) {
      debugPrint('Share error: $e');
      _snack('Paylaşım sırasında bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _toggleMute() async {
    final n = !_muted;
    await RouteService.setVoiceMuted(n);
    if (!mounted) return;
    setState(() => _muted = n);
    _snack(n ? 'Sesli bildirimler kapalı.' : 'Sesli bildirimler açık.');
  }

  Future<void> _startWorkout() async {
    final goal = _goal;
    final interval = goal == _Goal.interval;
    var rounds = 5;
    var phaseMin = 3;
    if (interval) {
      final pick = await showModalBottomSheet<(int, int)>(
        context: context,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const _IntervalSheet(),
      );
      if (pick == null) return;
      rounds = pick.$1;
      phaseMin = pick.$2;
    }
    if (!await _ensureGps()) return;

    if (!mounted) return;
    final start = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CountdownDialog(
        muted: _muted,
        onMuteChanged: (m) {
          RouteService.setVoiceMuted(m);
          if (mounted) setState(() => _muted = m);
        },
      ),
    );
    if (start != true) return;

    final ok = await RouteService.startWorkout(
      interval: interval,
      rounds: rounds,
      fastSec: phaseMin * 60,
      slowSec: phaseMin * 60,
      goalM: goal.meters,
      goalSec: goal.seconds,
    );
    if (!ok) {
      _snack('Antrenman başlatılamadı: arka plan servisi ya da konum izni yok.');
      return;
    }
    HapticFeedback.mediumImpact();
    _follow = true;
    _tickCount = 0;
    if (!_todayView) {
      setState(() {
        _period = Period.day;
        _offset = 0;
      });
      _load(fit: true);
    }
    await _refreshWorkout();
    _refreshStatus();
  }

  Future<void> _stopWorkout() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Antrenman bitirilsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Devam et'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final w = await RouteService.stopWorkout();
    await _refreshWorkout();
    _load(fit: true);
    _loadPastWorkouts();
    // Antrenman hemen bulut kuyruguna alinir (cevrimdisiysa baglaninca gider).
    RouteService.syncWorkouts();
    RouteService.syncRecent();
    if (w != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _WorkoutSummaryDialog(workout: w, justFinished: true),
      );
    }
  }

  void _activate() {
    if (!_shown) setState(() => _shown = true);
    _initialFitDone = false;
    _refreshWorkout();
    _refreshStatus();
    _load(fit: true);
    _locateMe();
    _loadPastWorkouts();
    RouteService.isVoiceMuted().then((m) {
      if (mounted) setState(() => _muted = m);
    });
  }

  Future<void> _loadPastWorkouts() async {
    final list = await RouteService.workouts();
    if (mounted) {
      setState(() {
        _pastWorkouts = list;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final d = widget.initialDate;
    if (d != null) {
      final diff = Metrics.daysBetween(_today(), d);
      _offset = diff > 0 ? 0 : diff;
    }
    _initCenter();
    if (widget.embedded) {
      RootNav.tab.addListener(_onTab);
      RootNav.startWorkout.addListener(_onStartRequest);
    }
    if (_visible) _activate();
    // GPS durumu ve iz 20 sn'de bir tazelenir (bugun gorunumunde, sayfa
    // gorunurken).
    _live = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _offset != 0 || !_visible) return;
      _refreshStatus();
      _load();
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _workoutTick?.cancel();
    if (widget.embedded) {
      RootNav.tab.removeListener(_onTab);
      RootNav.startWorkout.removeListener(_onStartRequest);
    }
    WidgetsBinding.instance.removeObserver(this);
    _map.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) {
      RouteService.refresh().then((_) => _refreshStatus());
      _refreshWorkout();
      _loadPastWorkouts();
      if (_offset == 0) _load();
    }
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  PeriodRange get _range => Aggregate.range(_period, _offset);

  Future<void> _initCenter() async {
    final c = await RouteService.savedCenter();
    if (!mounted) return;
    setState(() {
      _startCenter = c;
      _centerReady = true;
    });
  }

  void _setMe(LatLng p) {
    final first = _me == null;
    setState(() => _me = p);
    RouteService.saveCenter(p);
    if (first) _fit();
  }

  Future<void> _locateMe() async {
    final p = await RouteService.lastKnown();
    if (!mounted || p == null) return;
    _setMe(p);
  }

  Future<void> _refreshStatus() async {
    final s = await RouteService.status();
    if (!mounted) return;
    setState(() => _status = s);
    if (s.lastFix != null) _setMe(s.lastFix!);
    // Otomatik rota acik ama telefonun Konum anahtari kapali: tek dokunuslu
    // sistem penceresi (uygulama anahtari kendisi acamaz).
    if (s.enabled && s.fine && !s.locationOn && !_askedLocation && _visible) {
      _askedLocation = true;
      await _turnLocationOn();
    }
  }

  Future<void> _turnLocationOn() async {
    final ok = await RouteService.requestLocationOn();
    if (!ok) {
      await RouteService.openLocationSettings();
      return;
    }
    await RouteService.refresh();
    if (!mounted) return;
    final s = await RouteService.status();
    if (mounted) setState(() => _status = s);
    _locateMe();
  }

  Future<void> _load({bool fit = false}) async {
    final token = ++_loadToken;
    final r = _range;
    if (fit) setState(() => _loading = true);
    final data = await RouteService.load(r.start, r.end);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _data = data;
      _loading = false;
    });
    if (fit) {
      Future.microtask(() => _fit());
      // Sayfa acilisinda bugunun rotasi (degistiyse) buluta yedeklenir.
      if (_offset == 0) RouteService.syncRecent();
    }
  }

  /// Rota + (bugun gorunumunde) bulundugun yer birlikte ekrana sigdirilir.
  void _fit() {
    if (!_mapReady) return;
    final pts = [
      ..._data.allPoints,
      if (_todayView && _me != null) _me!,
    ];
    try {
      final validPts = pts.where((p) => p.latitude != 0 && p.longitude != 0).toList();
      if (validPts.isEmpty) {
        if (_initialFitDone) return;
        final c = _startCenter;
        _map.move(c ?? _fallbackCenter, c == null ? 6 : 16);
        _initialFitDone = true;
      } else if (validPts.length == 1) {
        _map.move(validPts.first, 16);
        _initialFitDone = true;
      } else {
        final bounds = LatLngBounds.fromPoints(validPts);
        _map.fitCamera(CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(60, 80, 60, 60),
          maxZoom: 16,
        ));
        _initialFitDone = true;
      }
    } catch (e) {
      debugPrint('Harita konumlanamadi: $e');
    }
  }

  void _setPeriod(Period p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _offset = 0;
    });
    _load(fit: true);
  }

  void _shift(int delta) {
    if (delta == 0) return;
    setState(() => _offset += delta);
    _load(fit: true);
  }

  void _goToDay(DateTime d) {
    final diff = Metrics.daysBetween(_today(), d);
    setState(() {
      _period = Period.day;
      _offset = diff > 0 ? 0 : diff;
    });
    _load(fit: true);
  }

  Future<void> _pickDay() async {
    final today = _today();
    final current = _period == Period.day ? _range.start : today;
    final first = DateTime(today.year - 3, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: first,
      lastDate: today,
      helpText: 'Rotası gösterilecek gün',
      fieldLabelText: 'Tarih',
      fieldHintText: 'gg.aa.yyyy',
      errorFormatText: 'Geçersiz tarih biçimi',
      errorInvalidText: 'Aralık dışında',
      cancelText: 'Vazgeç',
      confirmText: 'Göster',
    );
    if (picked != null && mounted) _goToDay(picked);
  }

  /// Uyari bandindaki eylem: izin yoksa izin, otomatik rota aciksa arka plan.
  Future<void> _enable() async {
    final ok = await RouteService.requestPermissions(background: _status.enabled);
    if (!ok) {
      RootNav.openSettings();
      return;
    }
    await RouteService.refresh();
    await _refreshStatus();
  }

  void _goToMe() {
    if (_workout.active) setState(() => _follow = true);
    if (_me != null) {
      _map.move(_me!, 16);
    } else if (_data.allPoints.isNotEmpty) {
      _map.move(_data.allPoints.last, 16);
    }
  }

  Future<void> _openPastWorkouts() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PastWorkoutsSheet(
        workouts: _pastWorkouts,
        onChanged: () {
          _load();
          _loadPastWorkouts();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Antrenman'),
        actions: [
          if (_todayView && _data.segments.isNotEmpty)
            _isSharing
                ? const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    tooltip: 'Paylaş',
                    onPressed: _shareRoute,
                    icon: Icon(Icons.share, color: AppColors.accent),
                  ),
          IconButton(
            tooltip: 'Güne git',
            onPressed: _pickDay,
            icon: Icon(Icons.edit_calendar_outlined, color: AppColors.accent),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              tooltip: 'Ayarlar',
              onPressed: () => RootNav.openSettings(),
              icon: Icon(Icons.settings_outlined, color: AppColors.textDim),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: PeriodSelector(selected: _period, onChanged: _setPeriod),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: RangeBar(
                title: range.title,
                onPrev: () => _shift(-1),
                onNext: _offset < 0 ? () => _shift(1) : null,
                onTitleTap: _pickDay,
              ),
            ),
            if (!_status.fine ||
                (_status.enabled && (!_status.background || !_status.locationOn)))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _SetupBanner(
                  status: _status,
                  onEnable: _enable,
                  onSettings: RouteService.openAppSettings,
                  onLocation: _turnLocationOn,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _PeriodStatsStrip(data: _data, loading: _loading),
            ),
            Expanded(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.divider),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Stack(
                        children: [
                          if (_centerReady && _shown)
                            _buildMap(context)
                          else
                            Positioned.fill(
                              child: Shimmer.fromColors(
                                baseColor: AppColors.surfaceAlt,
                                highlightColor: AppColors.divider,
                                child: Container(
                                  color: AppColors.surfaceAlt,
                                  child: Center(
                                    child: Icon(Icons.map, size: 64, color: AppColors.surface),
                                  ),
                                ),
                              ),
                            ),
                          if (_loading)
                            const Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.transparent),
                            ),
                          if (!_loading && _data.isEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: _EmptyNote(
                                period: _period,
                                today: _todayView,
                                auto: _status.enabled,
                              ),
                            ),
                          // Canli GPS durumu: neden acik/kapali, dogruluk, nokta.
                          if (_todayView && _status.fine && _status.locationOn)
                            Positioned(
                              top: 10,
                              left: 10,
                              right: 60,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _GpsChip(status: _status),
                              ),
                            ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: _MapButton(
                              icon: Icons.center_focus_strong_outlined,
                              tooltip: 'Rotaya odaklan',
                              onTap: _fit,
                            ),
                          ),
                          Positioned(
                            top: 60,
                            right: 10,
                            child: _MapButton(
                              icon: _workout.active
                                  ? (_follow ? Icons.navigation : Icons.navigation_outlined)
                                  : Icons.my_location,
                              tooltip: _workout.active ? 'Beni takip et' : 'Beni bul',
                              active: _workout.active && _follow,
                              onTap: _goToMe,
                            ),
                          ),
                          if (_data.segments.isNotEmpty)
                            Positioned(
                              bottom: 10,
                              left: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: AppColors.cardShadow,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _LegendDot(color: Colors.blue, label: 'Normal'),
                                    SizedBox(width: 8),
                                    _LegendDot(color: Colors.orange, label: 'Tempolu'),
                                    SizedBox(width: 8),
                                    _LegendDot(color: Colors.red, label: 'Koşu'),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _workout.active
                  ? _WorkoutPanel(
                      status: _workout,
                      muted: _muted,
                      onMute: _toggleMute,
                      onStop: _stopWorkout,
                      onPauseToggle: () async {
                        HapticFeedback.selectionClick();
                        await RouteService.pauseWorkout(!_workout.paused);
                        _pollWorkout();
                      },
                    )
                  : _buildBottomActions(),
            ),
          ],
        ),
      ),
    );
  }

  /// Antrenman yokken alt bolum: hedef secimi + baslat (yalniz bugun) ve
  /// gecmis antrenmanlar butonu (yalniz Gun sekmesinde).
  void _openHeatmap() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HeatmapScreen()),
      );

  /// "Ayak Izi Haritam" girisi: renkli, her sekmede gorunur.
  Widget _heatmapButton({bool compact = false}) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openHeatmap,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    compact ? 'Ayak İzi Haritam' : 'Ayak İzi Haritam · yürüdüğün tüm yollar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    if (_period != Period.day) return _heatmapButton();
    final count = _pastWorkouts.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_offset == 0) ...[
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final g in _Goal.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(g.label),
                      avatar: Icon(g.icon, size: 16),
                      selected: g == _goal,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _goal = g),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Tooltip(
                message: _muted ? 'Sesi aç' : 'Sesi kapat',
                child: Material(
                  color: _muted
                      ? AppColors.error.withValues(alpha: 0.12)
                      : AppColors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: _muted ? AppColors.error.withValues(alpha: 0.5) : AppColors.divider,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _toggleMute,
                    child: SizedBox(
                      width: 52,
                      height: 50,
                      child: Icon(
                        _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: _muted ? AppColors.error : AppColors.text,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _startWorkout,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded),
                        const SizedBox(width: 8),
                        Text(
                          _goal == _Goal.free
                              ? 'Antrenmanı Başlat'
                              : 'Başlat · ${_goal.label}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openPastWorkouts,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.history_rounded, size: 20),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(count > 0 ? 'Geçmiş ($count)' : 'Geçmiş'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _heatmapButton(compact: true)),
          ],
        ),
      ],
    );
  }

  static const _normalColor = Colors.blue;
  static const _briskColor = Colors.orange;
  static const _runColor = Colors.red;

  Color _tempoColor(double cadence) {
    if (cadence >= Intensity.runMinCadence) return _runColor;
    if (cadence >= Intensity.briskMinCadence) return _briskColor;
    return _normalColor;
  }

  /// Iz tempo renkleriyle: her parca ~1 dk'lik dilimlere bolunur, dilimin
  /// kadansi 3 dk'lik pencereyle hesaplanir (adim sayacinin toplu/gecikmeli
  /// teslimi tek dilimi "kosu" gostermesin). Adim bilgisi yoksa (bulut
  /// kaydi, eski kayit) parca normal yuruyus renginde cizilir. Parcalar
  /// ayri cizgidir; aralarinda sahte baglanti cizilmez.
  List<Polyline> _tempoPolylines(List<RouteSegment> segs, bool dark) {
    final out = <Polyline>[];
    final border = dark ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.9);
    void add(List<LatLng> pts, Color c) {
      if (pts.length < 2) return;
      out.add(Polyline(
        points: pts,
        color: c,
        strokeWidth: 4.5,
        borderColor: border,
        borderStrokeWidth: 1.5,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
    }

    for (final s in segs) {
      final n = s.points.length;
      final hasDetail = s.times.length == n && s.stepsAt.length == n && n >= 2 &&
          s.stepsAt.first >= 0 && s.stepsAt.last >= s.stepsAt.first;
      if (!hasDetail) {
        final mins = s.durationMs / 60000;
        final c = (s.steps >= 0 && mins >= 1) ? _tempoColor(s.steps / mins) : _normalColor;
        add(s.points, c);
        continue;
      }
      // Pencere icin: t zamanindaki adim (dogrusal ara deger).
      int stepsAt(int t) {
        if (t <= s.times.first) return s.stepsAt.first;
        if (t >= s.times.last) return s.stepsAt.last;
        var lo = 0, hi = n - 1;
        while (hi - lo > 1) {
          final mid = (lo + hi) >> 1;
          if (s.times[mid] <= t) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        final dt = s.times[hi] - s.times[lo];
        if (dt <= 0) return s.stepsAt[lo];
        return s.stepsAt[lo] + ((s.stepsAt[hi] - s.stepsAt[lo]) * (t - s.times[lo]) ~/ dt);
      }

      var cur = <LatLng>[s.points.first];
      Color? curColor;
      var a = 0;
      for (var i = 1; i < n; i++) {
        final last = i == n - 1;
        if (!last && s.times[i] - s.times[a] < 60000) continue;
        final mid = (s.times[a] + s.times[i]) ~/ 2;
        final from = mid - 90000 < s.times.first ? s.times.first : mid - 90000;
        final to = mid + 90000 > s.times.last ? s.times.last : mid + 90000;
        final minutes = (to - from) / 60000;
        final ds = stepsAt(to) - stepsAt(from);
        final c = (minutes >= 0.5 && ds >= 0) ? _tempoColor(ds / minutes) : _normalColor;
        final chunk = s.points.sublist(a + 1, i + 1);
        if (curColor == null || c == curColor) {
          cur.addAll(chunk);
        } else {
          add(cur, curColor);
          cur = [s.points[a], ...chunk];
        }
        curColor = c;
        a = i;
      }
      add(cur, curColor ?? _normalColor);
    }
    return out;
  }

  Widget _buildMap(BuildContext context) {
    final dark = !AppColors.isLight;
    final segs = _data.segments.where((s) => s.points.isNotEmpty).toList();
    final all = _data.allPoints;
    final showDots = _period == Period.day && all.length <= _dotLimit;

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _me ?? _startCenter ?? _fallbackCenter,
            initialZoom: (_me ?? _startCenter) == null ? 6 : 16,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: AppColors.surfaceAlt,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onPositionChanged: (camera, hasGesture) {
              // Antrenmanda haritayi elle kaydirinca takip durur.
              if (hasGesture && _follow && _workout.active) {
                setState(() => _follow = false);
              }
            },
            onMapReady: () {
              _mapReady = true;
              _fit();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ismail.adim_sayar',
              maxNativeZoom: 19,
              retinaMode: true,
              keepBuffer: 3,
              tileBuilder: dark ? darkModeTileBuilder : modernTileBuilder,
            ),
            if (segs.isNotEmpty)
              PolylineLayer(polylines: _tempoPolylines(segs, dark)),
            if (showDots)
              CircleLayer(
                circles: [
                  for (final p in all)
                    CircleMarker(
                      point: p,
                      radius: 1.5,
                      color: dark
                          ? Colors.white.withValues(alpha: 0.75)
                          : Colors.black.withValues(alpha: 0.45),
                      borderColor: Colors.transparent,
                      borderStrokeWidth: 0.0,
                    ),
                ],
              ),
            if (_me != null && _todayView)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _me!,
                    width: 22,
                    height: 22,
                    child: const _MeDot(),
                  ),
                ],
              ),
            if (all.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (var i = 0; i < segs.length; i++) ...[
                    if (_period == Period.day && i > 0)
                      Marker(
                        point: segs[i].points.first,
                        width: 22,
                        height: 22,
                        child: _SegBadge(index: i + 1),
                      ),
                  ],
                  Marker(
                    point: all.first,
                    width: 30,
                    height: 30,
                    child: const _EndPin(start: true),
                  ),
                  Marker(
                    point: all.last,
                    width: 30,
                    height: 30,
                    child: const _EndPin(start: false),
                  ),
                ],
              ),
            const RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [
                TextSourceAttribution('OpenStreetMap katkıcıları'),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Baslat butonunun ustundeki hedef secenekleri.
enum _Goal {
  free('Serbest', Icons.all_inclusive_rounded, 0, 0),
  km2('2 km', Icons.flag_outlined, 2000, 0),
  km5('5 km', Icons.flag_rounded, 5000, 0),
  min30('30 dk', Icons.timer_outlined, 0, 1800),
  min45('45 dk', Icons.timer_rounded, 0, 2700),
  interval('Aralıklı', Icons.swap_vert_rounded, 0, 0);

  final String label;
  final IconData icon;
  final int meters;
  final int seconds;
  const _Goal(this.label, this.icon, this.meters, this.seconds);
}

/// Haritanin ustunde secili donemin ozeti: km, sure, adim, tempo.
class _PeriodStatsStrip extends StatelessWidget {
  final RouteData data;
  final bool loading;
  const _PeriodStatsStrip({required this.data, required this.loading});

  @override
  Widget build(BuildContext context) {
    final km = data.distanceM / 1000;
    final sec = data.durationMs ~/ 1000;
    var steps = 0;
    for (final s in data.segments) {
      if (s.steps > 0) steps += s.steps;
    }
    final pace = km >= 0.2 ? (sec / km).round() : null;
    final empty = data.isEmpty;
    String v(String s) => empty ? '–' : s;
    return Row(
      children: [
        Expanded(
          child: _StripItem(
            icon: Icons.route_rounded,
            color: MetricColors.km,
            value: v('${km.toStringAsFixed(2).replaceAll('.', ',')} km'),
            label: 'mesafe',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StripItem(
            icon: Icons.timer_outlined,
            color: MetricColors.time,
            value: v(Metrics.duration(sec ~/ 60)),
            label: 'süre',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StripItem(
            icon: Icons.directions_walk_rounded,
            color: MetricColors.steps,
            value: v(steps > 0 ? Metrics.thousands(steps) : '–'),
            label: 'adım',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _StripItem(
            icon: Icons.speed_rounded,
            color: MetricColors.kcal,
            value: v(paceText(pace).replaceAll(' /km', '')),
            label: 'dk/km',
          ),
        ),
      ],
    );
  }
}

class _StripItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StripItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isLight ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textDim, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gecmis antrenmanlar: alttan acilan, yukari cekilerek buyuyen panel.
/// Satirda sil butonu; kisisel rekorlar rozetle isaretlenir.
class _PastWorkoutsSheet extends StatefulWidget {
  final List<Workout> workouts;
  final VoidCallback onChanged;
  const _PastWorkoutsSheet({required this.workouts, required this.onChanged});

  @override
  State<_PastWorkoutsSheet> createState() => _PastWorkoutsSheetState();
}

class _PastWorkoutsSheetState extends State<_PastWorkoutsSheet> {
  late List<Workout> _list = [...widget.workouts];

  Future<void> _delete(Workout w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Antrenman silinsin mi?'),
        content: Text(
          '${Metrics.numericDate(w.start)} · ${(w.distanceM / 1000).toStringAsFixed(2).replaceAll('.', ',')} km',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RouteService.deleteWorkout(w.startMs, w.day);
    if (!mounted) return;
    setState(() => _list.removeWhere((e) => e.startMs == w.startMs));
    widget.onChanged();
  }

  Future<void> _open(Workout w) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => _WorkoutSummaryDialog(workout: w),
    );
    if (res == true && mounted) {
      final all = await RouteService.workouts();
      if (!mounted) return;
      setState(() => _list = all);
      widget.onChanged();
    } else if (mounted) {
      setState(() {}); // yeniden adlandirma
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kisisel rekorlar: en uzun mesafe ve (1 km ustu) en hizli tempo.
    Workout? longest;
    Workout? fastest;
    for (final w in _list) {
      if (w.distanceM >= 200 && (longest == null || w.distanceM > longest.distanceM)) longest = w;
      final p = w.paceSecPerKm;
      if (w.distanceM >= 1000 && p != null && (fastest == null || p < fastest.paceSecPerKm!)) {
        fastest = w;
      }
    }
    final totalKm = _list.fold<double>(0, (a, w) => a + w.distanceM) / 1000;

    return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Geçmiş Antrenmanlar',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${_list.length} kayıt · ${totalKm.toStringAsFixed(1).replaceAll('.', ',')} km',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.divider),
              Expanded(
                child: _list.isEmpty
                    ? ListView(
                        controller: controller,
                        children: [
                          const SizedBox(height: 40),
                          Icon(Icons.directions_walk_rounded, size: 44, color: AppColors.textDim),
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              'Henüz kayıtlı antrenman yok.',
                              style: TextStyle(color: AppColors.textDim, fontSize: 13.5),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 24),
                        itemCount: _list.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final w = _list[i];
                          return _WorkoutRow(
                            workout: w,
                            longest: identical(w, longest),
                            fastest: identical(w, fastest),
                            onTap: () => _open(w),
                            onDelete: () => _delete(w),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  final Workout workout;
  final bool longest;
  final bool fastest;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _WorkoutRow({
    required this.workout,
    required this.longest,
    required this.fastest,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final d = w.start;
    final title = w.customName != null && w.customName!.isNotEmpty
        ? w.customName!
        : '${Metrics.longLabel(d)} ${w.interval ? 'aralıklı' : 'antrenmanı'}';
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  w.interval ? Icons.swap_vert_rounded : Icons.directions_walk_rounded,
                  color: AppColors.accent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Metrics.numericDate(d)} $time · ${(w.distanceM / 1000).toStringAsFixed(2).replaceAll('.', ',')} km · '
                      '${clockText(w.durationSec)} · ${paceText(w.paceSecPerKm)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textDim, fontSize: 12),
                    ),
                    if (longest || fastest) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (longest)
                            _PrChip(icon: Icons.emoji_events_rounded, text: 'En uzun', color: AppColors.best),
                          if (fastest)
                            _PrChip(icon: Icons.bolt_rounded, text: 'En hızlı', color: MetricColors.kcal),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sil',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: AppColors.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _PrChip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Parcalar
// ----------------------------------------------------------------------



/// Haritanin sol ustunde canli GPS durumu.
class _GpsChip extends StatelessWidget {
  final RouteStatus status;
  const _GpsChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final acc = status.lastAccuracy;
    final age = status.lastFixAgoSec;
    final fresh = age != null && age < 90;
    final String text;
    final Color color;
    if (!status.active) {
      text = status.reason.isNotEmpty
          ? 'GPS kapalı · ${status.reason}'
          : 'GPS kapalı · antrenman başlatınca açılır';
      color = AppColors.textDim;
    } else if (acc == null || !fresh) {
      text = 'GPS açık · konum aranıyor…';
      color = AppColors.best;
    } else if (acc > RouteStatus.maxAccuracyM) {
      text = 'Sinyal zayıf ±${acc.round()} m · kayıt için ≤50 m gerekli'
          '${status.rejected > 0 ? ' (${status.rejected} elendi)' : ''}';
      color = AppColors.best;
    } else {
      text = 'Kaydediliyor ±${acc.round()} m · ${status.accepted} nokta';
      color = AppColors.accent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  final RouteStatus status;
  final VoidCallback onEnable;
  final VoidCallback onSettings;
  final VoidCallback onLocation;
  const _SetupBanner({
    required this.status,
    required this.onEnable,
    required this.onSettings,
    required this.onLocation,
  });

  @override
  Widget build(BuildContext context) {
    final String text;
    final String action;
    final VoidCallback onTap;
    if (!status.fine) {
      text = 'Antrenman rotası için konum izni gerekli.';
      action = 'İzin ver';
      onTap = onEnable;
    } else if (!status.locationOn) {
      text = 'Telefonun Konum özelliği kapalı; GPS veri vermiyor.';
      action = 'Aç';
      onTap = onLocation;
    } else {
      text = 'Otomatik rota açık ama uygulama kapalıyken çalışması için konum "Her zaman izin ver" olmalı.';
      action = 'Ayarlar';
      onTap = onSettings;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.best.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: AppColors.best),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.text, fontSize: 12.5),
            ),
          ),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final Period period;
  final bool today;
  final bool auto;
  const _EmptyNote({
    required this.period,
    this.today = false,
    this.auto = false,
  });

  @override
  Widget build(BuildContext context) {
    final what = switch (period) {
      Period.day => 'Bu gün',
      Period.week => 'Bu hafta',
      Period.month => 'Bu ay',
      Period.year => 'Bu yıl',
    };
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          today
              ? (auto
                  ? 'Bugün henüz rota yok. 2 dk yürüyünce ya da antrenman başlatınca iz burada oluşur.'
                  : 'Bugün henüz rota yok. Antrenman başlatınca iz burada oluşur.')
              : '$what için rota kaydı yok.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      ),
    );
  }
}

/// Bulundugun yer: mavi nokta.
class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.95),
        shape: CircleBorder(side: BorderSide(color: AppColors.divider)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: active ? AppColors.accent : AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _EndPin extends StatelessWidget {
  final bool start;
  const _EndPin({required this.start});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: start ? AppColors.accent : const Color(0xFFEF4444),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Icon(
        start ? Icons.play_arrow_rounded : Icons.flag_rounded,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}

class _SegBadge extends StatelessWidget {
  final int index;
  const _SegBadge({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFEF4444), width: 2),
      ),
      child: Text(
        '$index',
        style: const TextStyle(
          color: Color(0xFFEF4444),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}


// ----------------------------------------------------------------------
// Yuruyus kaydi parcalari
// ----------------------------------------------------------------------

/// Suren yuruyus: sure, mesafe, tempo, adim; aralikli modda evre sayaci.
class _WorkoutPanel extends StatelessWidget {
  final WorkoutStatus status;
  final bool muted;
  final VoidCallback onMute;
  final VoidCallback onStop;
  final VoidCallback onPauseToggle;

  const _WorkoutPanel({
    required this.status,
    required this.muted,
    required this.onMute,
    required this.onStop,
    required this.onPauseToggle,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = status;
    final km = s.distanceM / 1000;
    final pace = km >= 0.2 ? (s.activeSec / km).round() : null;
    final pauseColor = AppColors.pick(const Color(0xFFFFA726), const Color(0xFFF57C00));
    final fastColor = AppColors.pick(const Color(0xFFFFA726), const Color(0xFFF57C00));
    final phaseColor = s.fast ? fastColor : AppColors.accent;

    final elapsedMin = s.elapsedSec / 60.0;
    final cadence = elapsedMin > 0 ? (s.steps / elapsedMin) : 0.0;
    
    int briskS = s.briskSteps;
    int briskM = s.briskMin;
    int runS = s.runSteps;
    int runM = s.runMin;
    
    if (briskS == 0 && runS == 0 && s.steps > 0) {
      if (cadence >= 130) {
        runS = s.steps;
        runM = elapsedMin.round();
      } else if (cadence >= 100) {
        briskS = s.steps;
        briskM = elapsedMin.round();
      }
    }

    final breakdown = ActivityBreakdown.compute(
      totalSteps: s.steps,
      briskSteps: briskS,
      briskMin: briskM,
      runSteps: runS,
      runMin: runM,
      hasData: true,
      heightCm: settings.heightCm,
      weightKg: settings.weightKg,
      activeMin: s.elapsedSec ~/ 60,
    );

    Widget stat(String v, String l) => Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  v,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(l, style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                s.paused ? Icons.pause_circle_filled_rounded : Icons.directions_walk,
                size: 18,
                color: s.paused ? pauseColor : AppColors.accent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  s.paused ? 'Duraklatıldı' : (s.interval ? 'Aralıklı yürüyüş' : 'Antrenman'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: s.paused ? pauseColor : AppColors.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (s.autoPause && !s.paused) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Otomatik duraklatma açık',
                  child: Icon(Icons.motion_photos_auto_outlined, size: 15, color: AppColors.textDim),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: onMute,
                icon: Icon(
                  muted ? Icons.volume_off : Icons.volume_up,
                  color: muted ? AppColors.error : AppColors.textDim,
                ),
                tooltip: muted ? 'Sesi Aç' : 'Sesi Kapat',
              ),
              const SizedBox(width: 4),
              Text(
                clockText(s.activeSec),
                style: TextStyle(
                  color: s.paused ? pauseColor : AppColors.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (s.paused)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: pauseColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                s.manualPaused
                    ? 'Kayıt duraklatıldı · devam etmek için Devam\'a bas (toplam ${clockText(s.elapsedSec)})'
                    : 'Hareket yok · kayıt duraklatıldı, yürümeye başlayınca devam eder '
                        '(toplam ${clockText(s.elapsedSec)})',
                style: TextStyle(color: pauseColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          if (s.hasGoal) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  s.goalDone ? Icons.emoji_events_rounded : Icons.flag_outlined,
                  size: 16,
                  color: s.goalDone ? AppColors.best : AppColors.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: s.goalProgress,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceAlt,
                      color: s.goalDone ? AppColors.best : AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  s.goalDone
                      ? 'Hedef tamam!'
                      : s.goalM > 0
                          ? '${(s.goalM / 1000).toStringAsFixed(s.goalM % 1000 == 0 ? 0 : 1)} km hedef'
                          : '${s.goalSec ~/ 60} dk hedef',
                  style: TextStyle(
                    color: s.goalDone ? AppColors.best : AppColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (s.interval) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (s.intervalDone ? AppColors.textDim : phaseColor)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    s.intervalDone
                        ? 'Turlar tamamlandı'
                        : s.fast
                            ? 'HIZLI TEMPO'
                            : 'Rahat tempo',
                    style: TextStyle(
                      color: s.intervalDone ? AppColors.textDim : phaseColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (!s.intervalDone)
                    Text(
                      '${clockText(s.phaseLeftSec)} · tur ${s.round}/${s.rounds}',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              stat('${km.toStringAsFixed(2).replaceAll('.', ',')} km', 'mesafe'),
              stat(paceText(pace), 'ort. tempo'),
              stat(Metrics.thousands(s.steps), 'adım'),
              stat('${breakdown.kcal.toStringAsFixed(0)} kcal', 'kalori'),
            ],
          ),
          if (s.elevGain >= 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.north_east_rounded, size: 15, color: AppColors.accent),
                const SizedBox(width: 3),
                Text('${s.elevGain.round()} m tırmanış',
                    style: TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 14),
                Icon(Icons.south_east_rounded, size: 15, color: MetricColors.km),
                const SizedBox(width: 3),
                Text('${s.elevLoss.round()} m iniş',
                    style: TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (breakdown.minutes > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (breakdown.normal.minutes > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_walk, size: 14, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text('${breakdown.normal.minutes}dk', style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                if (breakdown.brisk.minutes > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_walk, size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text('${breakdown.brisk.minutes}dk', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                if (breakdown.run.minutes > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_run, size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          Text('${breakdown.run.minutes}dk', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPauseToggle,
                  icon: Icon(s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label: Text(s.paused ? 'Devam' : 'Duraklat'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Bitir'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aralikli yuruyus ayari: tur sayisi ve evre suresi.
class _IntervalSheet extends StatefulWidget {
  const _IntervalSheet();

  @override
  State<_IntervalSheet> createState() => _IntervalSheetState();
}

class _IntervalSheetState extends State<_IntervalSheet> {
  int _rounds = 5;
  int _minutes = 3;

  @override
  Widget build(BuildContext context) {
    Widget chips(List<int> values, int selected, String Function(int) label,
            ValueChanged<int> onPick) =>
        Wrap(
          spacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                showCheckmark: false,
                onSelected: (_) => onPick(v),
              ),
          ],
        );

    final total = _rounds * _minutes * 2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aralıklı yürüyüş',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hızlı ve rahat tempo sırayla. Geçişlerde telefon titrer ve '
              'sesli söyler; ekranı açman gerekmez.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Row(
                children: [
                  _LegendDot(color: Color(0xFF3B82F6), label: 'Normal'),
                  Spacer(),
                  _LegendDot(color: Color(0xFFF57C00), label: 'Tempolu'),
                  Spacer(),
                  _LegendDot(color: Color(0xFFE53935), label: 'Koşu'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Tur sayısı', style: TextStyle(color: AppColors.text, fontSize: 13.5)),
            const SizedBox(height: 6),
            chips([3, 5, 8], _rounds, (v) => '$v tur', (v) => setState(() => _rounds = v)),
            const SizedBox(height: 12),
            Text('Her evre', style: TextStyle(color: AppColors.text, fontSize: 13.5)),
            const SizedBox(height: 6),
            chips([2, 3], _minutes, (v) => '$v dk hızlı / $v dk rahat',
                (v) => setState(() => _minutes = v)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop((_rounds, _minutes)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Başla · toplam $total dk'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bitis ozeti: mesafe, sure, tempo, adim ve km ara sureleri.
class _WorkoutSummaryDialog extends StatefulWidget {
  final Workout workout;

  /// Antrenman az once bitti: konfeti patlar.
  final bool justFinished;
  const _WorkoutSummaryDialog({required this.workout, this.justFinished = false});

  @override
  State<_WorkoutSummaryDialog> createState() => _WorkoutSummaryDialogState();
}

class _WorkoutSummaryDialogState extends State<_WorkoutSummaryDialog> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    if (widget.justFinished) _confettiController.play();
    _same = RouteService.sameRoute(widget.workout);
  }

  late final Future<SameRouteResult?> _same;

  bool _sharing = false;
  bool _exporting = false;

  /// GPX olarak disa aktarir (Strava, Garmin Connect, Komoot'a yuklenebilir).
  Future<void> _exportGpx() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final w = widget.workout;
      final track = await RouteService.workoutTrack(w);
      if (track.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu antrenmanın rota kaydı yok.')),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final d = w.start;
      final name = 'yuruyus_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
          '_${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}.gpx';
      final file = File('${dir.path}/$name');
      await file.writeAsString(RouteService.buildGpx(w, track));
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/gpx+xml')]);
    } catch (e) {
      debugPrint('GPX olusturulamadi: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Antrenmani rota cizimiyle paylasim karti olarak paylasir.
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final w = widget.workout;
      final b = _calculateBreakdown();
      final pts = await RouteService.workoutPoints(w);
      if (!mounted) return;
      final highlights = <String>[
        if (w.goalDone) 'Hedef tamam',
        if (w.distanceM >= 5000) '5 km+',
        if (w.elevGain >= 10) '↑ ${w.elevGain.round()} m tırmanış',
        if (b.run.minutes > 0) '${b.run.minutes} dk koşu',
      ];
      final bytes = await ScreenshotController().captureFromWidget(
        WorkoutShareCard(
          points: pts,
          title: w.customName?.isNotEmpty == true
              ? w.customName!
              : (w.interval ? 'Aralıklı antrenman' : 'Antrenman'),
          date: w.start,
          km: w.distanceM / 1000,
          durationSec: w.durationSec,
          pace: paceText(w.paceSecPerKm).replaceAll(' /km', ''),
          steps: w.steps,
          kcal: b.kcal.round(),
          highlights: highlights,
        ),
        context: context,
        pixelRatio: 1,
        targetSize: const Size(1080, 1350),
        delay: const Duration(milliseconds: 80),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/workout_${w.startMs}.png');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${(w.distanceM / 1000).toStringAsFixed(2).replaceAll('.', ',')} km yürüdüm! #YürüyüşDefteri',
      );
    } catch (e) {
      debugPrint('Antrenman paylasilamadi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşım sırasında bir hata oluştu.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  /// Sonuçları hesaplarken Formula kullanıyoruz.
  ActivityBreakdown _calculateBreakdown() {
    return ActivityBreakdown.compute(
      totalSteps: widget.workout.steps,
      briskSteps: widget.workout.briskSteps,
      briskMin: widget.workout.briskMin,
      runSteps: widget.workout.runSteps,
      runMin: widget.workout.runMin,
      hasData: true,
      heightCm: context.read<SettingsProvider>().heightCm,
      weightKg: context.read<SettingsProvider>().weightKg,
      activeMin: (widget.workout.durationSec / 60.0).round(),
    );
  }

  void _delete() async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Antrenmanı Sil', style: TextStyle(color: AppColors.text)),
        content: Text('Bu antrenmanı silmek istediğinize emin misiniz? Hem cihazdan hem de (varsa) bulut yedeklerinden kaldırılacaktır.', style: TextStyle(color: AppColors.textDim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('İptal', style: TextStyle(color: AppColors.accent))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (conf != true) return;
    await RouteService.deleteWorkout(widget.workout.startMs, widget.workout.day);
    if (mounted) Navigator.pop(context, true);
  }

  void _rename() async {
    final tc = TextEditingController(text: widget.workout.customName ?? (widget.workout.interval ? 'Aralıklı Antrenman' : 'Antrenman'));
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Yeniden Adlandır', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: tc,
          autofocus: true,
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Antrenman adı',
            hintStyle: TextStyle(color: AppColors.textDim),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('İptal', style: TextStyle(color: AppColors.accent))),
          FilledButton(onPressed: () => Navigator.pop(ctx, tc.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != widget.workout.customName) {
      await RouteService.renameWorkout(widget.workout.startMs, newName);
      if (mounted) {
        setState(() {
          widget.workout.customName = newName;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.workout;
    final breakdown = _calculateBreakdown();
    
    final rows = <Widget>[];
    var prev = 0;
    for (var i = 0; i < w.splits.length; i++) {
      final split = w.splits[i] - prev;
      prev = w.splits[i];
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text('${i + 1}. km', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const Spacer(),
            Text(paceText(split),
                style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ));
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.best],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.best.withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          w.interval ? Icons.timer_outlined : Icons.emoji_events_rounded,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      ConfettiWidget(
                        confettiController: _confettiController,
                        blastDirectionality: BlastDirectionality.explosive,
                        emissionFrequency: 0.05,
                        numberOfParticles: 20,
                        gravity: 0.1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          w.customName ?? (w.interval ? 'Aralıklı Antrenman' : 'Tebrikler, Antrenman Bitti!'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        color: AppColors.textDim,
                        tooltip: 'Adlandır',
                        onPressed: _rename,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatBox(icon: Icons.map_rounded, label: 'Mesafe', value: '${breakdown.km.toStringAsFixed(2).replaceAll('.', ',')} km', color: Colors.blue),
                      _StatBox(icon: Icons.local_fire_department_rounded, label: 'Kalori', value: '${breakdown.kcal.toStringAsFixed(0)} kcal', color: Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatBox(icon: Icons.timer_rounded, label: w.pausedSec > 0 ? 'Hareket süresi' : 'Süre', value: clockText(w.durationSec), color: Colors.green),
                      _StatBox(icon: Icons.speed_rounded, label: 'Ort. Tempo', value: paceText(w.paceSecPerKm), color: Colors.purple),
                    ],
                  ),
                  FutureBuilder<SameRouteResult?>(
                    future: _same,
                    builder: (_, snap) {
                      final r = snap.data;
                      if (r == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _SameRouteCard(result: r),
                      );
                    },
                  ),
                  if (w.pausedSec >= 10) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pause_circle_outline_rounded, size: 15, color: AppColors.textDim),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${clockText(w.pausedSec)} otomatik duraklama · toplam ${clockText(w.totalSec)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textDim, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (breakdown.minutes > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text('Tempo Dağılımı', style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (breakdown.normal.minutes > 0) _TempoPill('Yürüyüş', breakdown.normal.minutes, Colors.blue),
                              if (breakdown.brisk.minutes > 0) _TempoPill('Hızlı', breakdown.brisk.minutes, Colors.orange),
                              if (breakdown.run.minutes > 0) _TempoPill('Koşu', breakdown.run.minutes, Colors.red),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (w.hasElevation) ...[
                    const SizedBox(height: 16),
                    _ElevationCard(workout: w),
                  ],
                  if (rows.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ExpansionTile(
                      title: Text('Kilometre Süreleri', style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
                      collapsedIconColor: AppColors.accent,
                      iconColor: AppColors.accent,
                      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: rows,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _sharing ? null : _share,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: _sharing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Kapat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    tooltip: 'Sil',
                    onPressed: _delete,
                  ),
                  IconButton(
                    tooltip: 'GPX dışa aktar (Strava, Garmin)',
                    onPressed: _exporting ? null : _exportGpx,
                    icon: _exporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.file_download_outlined, color: AppColors.accent),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textDim,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ayni rotadaki onceki antrenmanlarla tempo kiyasi.
class _SameRouteCard extends StatelessWidget {
  final SameRouteResult result;
  const _SameRouteCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final diff = r.myPace - r.bestPace; // + : en iyiden yavas
    final vsLast = r.myPace - r.lastPace;
    final color = r.isRecord ? AppColors.best : AppColors.accent;
    String sec(int v) => '${v.abs()} sn/km';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(r.isRecord ? Icons.emoji_events_rounded : Icons.repeat_rounded, color: color, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.isRecord
                      ? 'Bu rotada yeni rekor! (${sec(diff)} daha hızlı)'
                      : 'Bu rotayı daha önce ${r.count} kez yürüdün',
                  style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'En iyi: ${paceText(r.bestPace)} (${Metrics.numericDate(r.bestDate)}) · '
                  'geçen seferden ${sec(vsLast)} ${vsLast <= 0 ? 'hızlı' : 'yavaş'}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rakim profili: tirmanis/inis ve baslangica gore yukseklik grafigi.
class _ElevationCard extends StatelessWidget {
  final Workout workout;
  const _ElevationCard({required this.workout});

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final minE = w.elev.reduce((a, b) => a < b ? a : b);
    final maxE = w.elev.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terrain_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('Rakım', style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Icon(Icons.north_east_rounded, size: 14, color: AppColors.accent),
              Text(' ${w.elevGain.round()} m',
                  style: TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Icon(Icons.south_east_rounded, size: 14, color: MetricColors.km),
              Text(' ${w.elevLoss.round()} m',
                  style: TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            width: double.infinity,
            child: CustomPaint(
              painter: _ElevationPainter(
                w.elev,
                line: AppColors.accent,
                grid: AppColors.divider,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Başlangıç', style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
              const Spacer(),
              Text('fark ${(maxE - minE).round()} m',
                  style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
              const Spacer(),
              Text('Bitiş', style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<double> values;
  final Color line;
  final Color grid;
  _ElevationPainter(this.values, {required this.line, required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minV = values.first, maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    // Duz rotada cizgi abartilmasin: en az 10 m olcek.
    final span = (maxV - minV) < 10 ? 10.0 : (maxV - minV);
    final mid = (maxV + minV) / 2;
    final lo = mid - span / 2;
    Offset pt(int i) => Offset(
          size.width * i / (values.length - 1),
          size.height - (values[i] - lo) / span * size.height,
        );
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height),
        Paint()..color = grid..strokeWidth = 1);
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.35), line.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) => old.values != values;
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatBox({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _TempoPill extends StatelessWidget {
  final String label;
  final int minutes;
  final Color color;

  const _TempoPill(this.label, this.minutes, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(label == 'Koşu' ? Icons.directions_run : Icons.directions_walk, size: 14, color: color),
            const SizedBox(width: 4),
            Text('${minutes}dk', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}


class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CountdownDialog extends StatefulWidget {
  final bool muted;
  final ValueChanged<bool> onMuteChanged;
  const _CountdownDialog({required this.muted, required this.onMuteChanged});

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int _count = 5;
  Timer? _timer;
  late bool _muted = widget.muted;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_count <= 1) {
        timer.cancel();
        Navigator.pop(context, true);
      } else {
        setState(() => _count--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Hazırlan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.accent, blurRadius: 20, spreadRadius: 5)
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      final m = !_muted;
                      setState(() => _muted = m);
                      widget.onMuteChanged(m);
                    },
                    icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                    label: Text(_muted ? 'Ses kapalı' : 'Ses açık'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _muted ? AppColors.error : AppColors.surface,
                      foregroundColor: _muted ? Colors.white : AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      _timer?.cancel();
                      Navigator.pop(context, false);
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('İptal'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.text,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
