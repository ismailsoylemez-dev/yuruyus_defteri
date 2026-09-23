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
import 'package:latlong2/latlong.dart';
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
  static const _routeColor = Color(0xFFEF4444);
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

  bool get _visible =>
      !widget.embedded || RootNav.tab.value == RootNav.route;

  void _onTab() {
    if (!mounted || !_visible) return;
    _activate();
  }

  // ---- Yuruyus kaydi ----
  WorkoutStatus _workout = const WorkoutStatus();
  Timer? _workoutTick;

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
      final before = _workout.splits.length;
      setState(() => _workout = w);
      if (!w.active) {
        _workoutTick?.cancel();
        _workoutTick = null;
      } else if (w.splits.length != before) {
        _load();
      }
    } finally {
      _polling = false;
    }
  }

  Future<bool> _ensureGps() async {
    if (!_status.ready) {
      final ok = await RouteService.requestPermissions();
      if (!ok) {
        _snack('Yürüyüş kaydı için konum izni gerekli.');
        return false;
      }
      await RouteService.setEnabled(true);
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
      
      // Get the map image
      final mapImage = await boundary.toImage(pixelRatio: 2.0);
      final mapByteData = await mapImage.toByteData(format: ui.ImageByteFormat.png);
      if (mapByteData == null) return;
      if (!mounted) return;
      
      // Render Nike Run Club style offscreen card
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

  Future<void> _startWorkout({required bool interval}) async {
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
    final ok = await RouteService.startWorkout(
      interval: interval,
      rounds: rounds,
      fastSec: phaseMin * 60,
      slowSec: phaseMin * 60,
    );
    if (!ok) {
      _snack('Yürüyüş başlatılamadı: arka plan servisi çalışmıyor.');
      return;
    }
    HapticFeedback.mediumImpact();
    if (_offset != 0 || _period != Period.day) {
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
        title: const Text('Yürüyüş bitirilsin mi?'),
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
    if (w != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => _WorkoutSummaryDialog(workout: w),
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
    if (widget.embedded) RootNav.tab.addListener(_onTab);
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
    if (widget.embedded) RootNav.tab.removeListener(_onTab);
    WidgetsBinding.instance.removeObserver(this);
    _map.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) {
      RouteService.refresh().then((_) => _refreshStatus());
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
    // Rota acik ama telefonun Konum anahtari kapali: tek dokunuslu sistem
    // penceresi (uygulama anahtari kendisi acamaz).
    if (s.ready && !s.locationOn && !_askedLocation && _visible) {
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
      // Sekme geçişi vb. durumlarda haritanın boyutlanması için kısa bir süre bekle
      Future.microtask(() => _fit());
      // Sayfa acilisinda bugunun rotasi (degistiyse) buluta yedeklenir.
      if (_offset == 0) RouteService.syncRecent();
    }
  }

  /// Rota + (bugun gorunumunde) bulundugun yer birlikte ekrana sigdirilir.
  void _fit() {
    if (!_mapReady) return;
    final today = _offset == 0 && _period == Period.day;
    final pts = [
      ..._data.allPoints,
      if (today && _me != null) _me!,
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



  Future<void> _enable() async {
    final ok = await RouteService.requestPermissions();
    if (!ok) {
      RootNav.openSettings();
      return;
    }
    await RouteService.setEnabled(true);
    await _refreshStatus();
  }

  void _goToMe() {
    if (_me != null) {
      _map.move(_me!, 16);
    } else {
      // Fallback
      if (_data.allPoints.isNotEmpty) {
        _map.move(_data.allPoints.last, 16);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota ve Yürüyüş'),
        actions: [
          if (_offset == 0 && _period == Period.day && _data.segments.isNotEmpty)
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
            if (!_status.fullyReady || !_status.locationOn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _SetupBanner(
                  status: _status,
                  onEnable: _enable,
                  onSettings: RouteService.openAppSettings,
                  onLocation: _turnLocationOn,
                ),
              ),
            Expanded(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Column(
                  children: [
                    Expanded(
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
                                      today: _offset == 0 && _period == Period.day,
                                      ready: _status.ready,
                                    ),
                                  ),
                                // Canli GPS durumu: aktif mi, dogruluk, kaydedilen nokta.
                                if (_offset == 0 &&
                                    _period == Period.day &&
                                    _status.ready &&
                                    _status.locationOn)
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
                                    icon: Icons.my_location,
                                    tooltip: 'Beni bul',
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
                                          _LegendDot(color: Colors.blue, label: 'Yavaş'),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: _workout.active
                          ? _WorkoutPanel(status: _workout, onStop: _stopWorkout)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_offset == 0 && _period == Period.day) ...[
                                  FilledButton(
                                    onPressed: () => _startWorkout(interval: false),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.directions_walk_rounded),
                                        SizedBox(width: 4),
                                        Text('/'),
                                        SizedBox(width: 4),
                                        Icon(Icons.directions_run_rounded),
                                        SizedBox(width: 10),
                                        Text('Antrenmanı Başlat'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Text(
                                  'Geçmiş Antrenmanlar',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_pastWorkouts.isEmpty)
                                  Text(
                                    'Henüz kayıtlı yürüyüş yok.',
                                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                                  )
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _pastWorkouts.length > 3 ? 3 : _pastWorkouts.length,
                                    itemBuilder: (_, i) {
                                      final w = _pastWorkouts[i];
                                      final d = w.start;
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        onTap: () {
                                          showDialog<void>(
                                            context: context,
                                            builder: (_) => _WorkoutSummaryDialog(workout: w),
                                          );
                                        },
                                        leading: Icon(
                                          w.interval ? Icons.timer_outlined : Icons.directions_walk,
                                          color: AppColors.accent,
                                        ),
                                        title: Text(
                                          '${Metrics.numericDate(d)} ${Metrics.longLabel(d)}',
                                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                        subtitle: Text(
                                          '${(w.distanceM / 1000).toStringAsFixed(2)} km · ${clockText(w.durationSec)} · ${paceText((w.distanceM < 200) ? null : (w.durationSec / (w.distanceM / 1000)).round())}',
                                          style: TextStyle(color: AppColors.textDim, fontSize: 12),
                                        ),
                                        trailing: Icon(Icons.chevron_right, color: AppColors.divider),
                                      );
                                    },
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSegmentColor(RouteSegment s) {
    if (s.durationMs == 0) return _routeColor;
    final mins = s.durationMs / 60000;
    if (mins < 1) return _routeColor;
    final cadence = s.steps / mins;
    if (cadence >= Intensity.runMinCadence) {
      return Colors.red;
    } else if (cadence >= Intensity.briskMinCadence) {
      return Colors.orange;
    } else {
      return Colors.blue;
    }
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
        onMapReady: () {
          _mapReady = true;
          _fit();
        },
      ),
      children: [
        // Ücretsiz OpenStreetMap karoları (CartoDB limitlerine takılmamak için).
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ismail.adim_sayar',
          maxNativeZoom: 19,
          retinaMode: true,
          keepBuffer: 3,
          tileBuilder: dark ? darkModeTileBuilder : modernTileBuilder,
        ),
        if (segs.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final s in segs) ...s.points],
                gradientColors: [
                  for (final s in segs)
                    for (int i = 0; i < s.points.length; i++)
                      _getSegmentColor(s)
                ],
                strokeWidth: 4.5,
                borderColor: dark
                    ? Colors.black.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.9),
                borderStrokeWidth: 1.5,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        // Gun gorunumunde kaydedilen her nokta kucuk kirmizi isaret.
        if (showDots)
          CircleLayer(
            circles: [
              for (final p in all)
                CircleMarker(
                  point: p,
                  radius: 2.6,
                  color: _routeColor,
                  borderColor: Colors.white,
                  borderStrokeWidth: 0.8,
                ),
            ],
          ),
        // Bulundugun yer (yalnizca bugun gorunumunde).
        if (_me != null && _period == Period.day && _offset == 0)
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
                // 1. parcanin basinda zaten baslangic isareti var.
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
    if (!_loading && all.isEmpty) _buildEmptyState(),
    ],
    );
  }

  Widget _buildEmptyState() {
    return Positioned.fill(
      child: Container(
        color: AppColors.surfaceAlt.withValues(alpha: 0.8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Icon(Icons.explore_outlined,
                      size: 48, color: AppColors.accent),
                ),
                const SizedBox(height: 24),
                Text(
                  'Kayıtlı Rota Bulunamadı',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Seçili zaman aralığı için henüz harita\nüzerinde bir izin tespit edilemedi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
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
      text = 'GPS bekliyor · yürümeye başlayınca açılır';
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
    if (!status.locationOn) {
      text = 'Telefonun Konum özelliği kapalı; GPS veri vermiyor.';
      action = 'Aç';
      onTap = onLocation;
    } else if (!status.enabled || !status.fine) {
      text = status.enabled
          ? 'Rota için konum izni gerekli.'
          : 'Rota kaydı kapalı. Açınca yürüdüğün yerler haritada iz olarak birikir.';
      action = status.enabled ? 'İzin ver' : 'Aç';
      onTap = onEnable;
    } else {
      text = 'Uygulama kapalıyken de kaydetmek için konumu "Her zaman izin ver" yap.';
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
  final bool ready;
  const _EmptyNote({
    required this.period,
    this.today = false,
    this.ready = false,
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
          today && ready
              ? 'Bugün henüz rota yok. Yürümeye başlayınca iz burada oluşur.'
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
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
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
            child: Icon(icon, size: 20, color: AppColors.text),
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
class _WorkoutPanel extends StatefulWidget {
  final WorkoutStatus status;
  final VoidCallback onStop;

  const _WorkoutPanel({required this.status, required this.onStop});

  @override
  State<_WorkoutPanel> createState() => _WorkoutPanelState();
}

class _WorkoutPanelState extends State<_WorkoutPanel> {
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _fetchMuteState();
  }

  Future<void> _fetchMuteState() async {
    final m = await RouteService.isVoiceMuted();
    if (mounted) setState(() => _muted = m);
  }

  Future<void> _toggleMute() async {
    final n = !_muted;
    await RouteService.setVoiceMuted(n);
    if (mounted) setState(() => _muted = n);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = widget.status;
    final km = s.distanceM / 1000;
    final pace = km >= 0.2 ? (s.elapsedSec / km).round() : null;
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
              Icon(Icons.directions_walk, size: 18, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                s.interval ? 'Aralıklı yürüyüş' : 'Antrenman',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _toggleMute,
                icon: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: _muted ? AppColors.error : AppColors.textDim,
                ),
                tooltip: _muted ? 'Sesi Aç' : 'Sesi Kapat',
              ),
              const SizedBox(width: 4),
              Text(
                clockText(s.elapsedSec),
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.onStop,
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
  const _WorkoutSummaryDialog({required this.workout});

  @override
  State<_WorkoutSummaryDialog> createState() => _WorkoutSummaryDialogState();
}

class _WorkoutSummaryDialogState extends State<_WorkoutSummaryDialog> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _confettiController.play();
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
      heightCm: 170, // Ortalama deger kullanildi, aslinda provider'dan alinabilir
      weightKg: 70.0,
      activeMin: (widget.workout.durationSec / 60.0).round(),
    );
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
            Padding(
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
                  Text(
                    w.interval ? 'Aralıklı Antrenman Bitti!' : 'Tebrikler, Antrenman Bitti!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
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
                      _StatBox(icon: Icons.timer_rounded, label: 'Süre', value: clockText(w.durationSec), color: Colors.green),
                      _StatBox(icon: Icons.speed_rounded, label: 'Ort. Tempo', value: paceText(w.paceSecPerKm), color: Colors.purple),
                    ],
                  ),
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
                  SizedBox(
                    width: double.infinity,
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
