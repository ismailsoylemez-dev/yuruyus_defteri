import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/route_service.dart';
import '../theme/app_theme.dart';
import '../utils/aggregate.dart';
import '../utils/metrics.dart';
import '../utils/root_nav.dart';
import '../widgets/period_selector.dart';
import '../widgets/route_settings_panel.dart';

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

  final _map = MapController();
  Period _period = Period.day;
  int _offset = 0;
  RouteData _data = RouteData.empty;
  RouteStatus _status = const RouteStatus();
  bool _loading = true;
  bool _mapReady = false;
  int _loadToken = 0;
  Timer? _live;

  /// Cihazin bilinen son konumu: rota yokken harita buraya odaklanir.
  LatLng? _me;

  /// Haritanin acilis merkezi (en son bilinen konum). Okunana kadar harita
  /// cizilmez; boylece acilista Turkiye/dunya geneli hic gorunmez.
  LatLng? _startCenter;
  bool _centerReady = false;

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

  Future<void> _openWorkouts() async {
    final list = await RouteService.workouts();
    if (!mounted) return;
    final day = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WorkoutListSheet(workouts: list),
    );
    if (day != null) _goToDay(day);
  }

  /// Sayfa gorunur oldu: durum, rota ve konum tazelenir.
  void _activate() {
    if (!_shown) setState(() => _shown = true);
    _refreshWorkout();
    _refreshStatus();
    _load(fit: true);
    _locateMe();
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
      _fit();
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
      if (pts.isEmpty) {
        final c = _startCenter;
        _map.move(c ?? _fallbackCenter, c == null ? 6 : 16);
      } else if (pts.length == 1) {
        _map.move(pts.first, 16);
      } else {
        _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.fromLTRB(36, 56, 36, 36),
          maxZoom: 17,
        ));
      }
    } catch (e) {
      debugPrint('Harita konumlanamadi: $e');
    }
  }

  void _setPeriod(Period p) {
    setState(() {
      _period = p;
      _offset = 0;
    });
    _load(fit: true);
  }

  void _shift(int delta) {
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

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: RouteSettingsPanel(
            onChanged: _refreshStatus,
            onCleared: () => _load(fit: true),
          ),
        ),
      ),
    ).then((_) => _refreshStatus());
  }

  Future<void> _enable() async {
    final ok = await RouteService.requestPermissions();
    if (!ok) {
      _openSettings();
      return;
    }
    await RouteService.setEnabled(true);
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota'),
        actions: [
          IconButton(
            tooltip: 'Yürüyüşlerim',
            onPressed: _openWorkouts,
            icon: Icon(Icons.history, color: AppColors.textDim),
          ),
          IconButton(
            tooltip: 'Güne git',
            onPressed: _pickDay,
            icon: Icon(Icons.edit_calendar_outlined, color: AppColors.accent),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              tooltip: 'Rota ayarları',
              onPressed: _openSettings,
              icon: Icon(Icons.tune, color: AppColors.textDim),
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
                          const SizedBox.expand(),
                        if (_loading)
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: LinearProgressIndicator(minHeight: 3),
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
                      children: [
                        if (_offset == 0 && _period == Period.day) ...[
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _startWorkout(interval: false),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Yürüyüşe başla'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _startWorkout(interval: true),
                                  icon: const Icon(Icons.timer_outlined),
                                  label: const Text('Aralıklı'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        _SummaryBar(data: _data, period: _period),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final dark = !AppColors.isLight;
    final segs = _data.segments.where((s) => s.points.isNotEmpty).toList();
    final all = _data.allPoints;
    final showDots = _period == Period.day && all.length <= _dotLimit;

    return FlutterMap(
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
        // OpenStreetMap karolari (anahtarsiz). Koyu temada karolar koyu
        // tona cevrilir; CARTO artik API anahtari istiyor.
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ismail.adim_sayar',
          maxNativeZoom: 19,
          tileBuilder: dark ? darkModeTileBuilder : null,
        ),
        PolylineLayer(
          polylines: [
            for (final s in segs)
              if (s.points.length >= 2)
                Polyline(
                  points: s.points,
                  color: _routeColor,
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
    );
  }
}

// ----------------------------------------------------------------------
// Parcalar
// ----------------------------------------------------------------------

class _SummaryBar extends StatelessWidget {
  final RouteData data;
  final Period period;
  const _SummaryBar({required this.data, required this.period});

  @override
  Widget build(BuildContext context) {
    final km = data.distanceM / 1000;
    final minutes = (data.durationMs / 60000).round();
    String pace = '-';
    if (km >= 0.2 && minutes > 0) {
      final secPerKm = (data.durationMs / 1000) / km;
      final m = secPerKm ~/ 60;
      final s = (secPerKm % 60).round().toString().padLeft(2, '0');
      pace = m > 59 ? '-' : '$m:$s';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          _Stat(
            icon: Icons.straighten,
            color: MetricColors.km,
            value: '${km.toStringAsFixed(2).replaceAll('.', ',')} km',
            label: 'GPS mesafe',
          ),
          _Stat(
            icon: Icons.timer_outlined,
            color: MetricColors.time,
            value: Metrics.duration(minutes),
            label: 'hareket',
          ),
          _Stat(
            icon: Icons.speed,
            color: MetricColors.kcal,
            value: pace == '-' ? '-' : '$pace /km',
            label: 'tempo',
          ),
          _Stat(
            icon: period == Period.day ? Icons.route : Icons.calendar_month_outlined,
            color: AppColors.accent,
            value: period == Period.day
                ? '${data.segments.length}'
                : '${data.dayCount}',
            label: period == Period.day ? 'parça' : 'gün',
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

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
class _WorkoutPanel extends StatelessWidget {
  final WorkoutStatus status;
  final VoidCallback onStop;
  const _WorkoutPanel({required this.status, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final s = status;
    final km = s.distanceM / 1000;
    final pace = km >= 0.2 ? (s.elapsedSec / km).round() : null;
    final fastColor = AppColors.pick(const Color(0xFFFFA726), const Color(0xFFF57C00));
    final phaseColor = s.fast ? fastColor : AppColors.accent;

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
                s.interval ? 'Aralıklı yürüyüş' : 'Yürüyüş',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
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
              stat('${s.splits.length}', 'km bitti'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
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
class _WorkoutSummaryDialog extends StatelessWidget {
  final Workout workout;
  const _WorkoutSummaryDialog({required this.workout});

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final km = w.distanceM / 1000;
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
    Widget line(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(l, style: TextStyle(color: AppColors.textDim, fontSize: 13.5)),
              const Spacer(),
              Text(v,
                  style: TextStyle(
                      color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(w.interval ? 'Aralıklı yürüyüş bitti' : 'Yürüyüş bitti'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            line('Mesafe', '${km.toStringAsFixed(2).replaceAll('.', ',')} km'),
            line('Süre', clockText(w.durationSec)),
            line('Ortalama tempo', paceText(w.paceSecPerKm)),
            line('Adım', Metrics.thousands(w.steps)),
            if (rows.isNotEmpty) ...[
              const Divider(height: 20),
              ...rows,
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    );
  }
}

/// Yuruyuslerim: dokununca o gunun rotasi acilir.
class _WorkoutListSheet extends StatelessWidget {
  final List<Workout> workouts;
  const _WorkoutListSheet({required this.workouts});

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Yürüyüşlerim',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (workouts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  'Henüz kayıtlı yürüyüş yok. Rota sayfasındaki '
                  '"Yürüyüşe başla" ile ilkini kaydet.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: workouts.length,
                  itemBuilder: (_, i) {
                    final w = workouts[i];
                    final d = w.start;
                    final km = w.distanceM / 1000;
                    return ListTile(
                      onTap: () => Navigator.of(context)
                          .pop(DateTime(d.year, d.month, d.day)),
                      leading: Icon(
                        w.interval ? Icons.timer_outlined : Icons.directions_walk,
                        color: AppColors.accent,
                      ),
                      title: Text(
                        '${km.toStringAsFixed(2).replaceAll('.', ',')} km · ${clockText(w.durationSec)}',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${Metrics.numericDate(d)} ${Metrics.longLabel(d)} · '
                        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
                        ' · ${paceText(w.paceSecPerKm)}'
                        '${w.interval ? ' · aralıklı' : ''}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                      trailing: Icon(Icons.chevron_right, color: AppColors.textDim),
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
