import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/metrics.dart';
import 'auth_service.dart';

/// Kesintisiz yurunen bir parca (5 dk'dan uzun duraklama yeni parca acar).
class RouteSegment {
  final String day;
  final List<LatLng> points;
  final int startMs;
  final int endMs;

  /// Parca basinda / sonunda gunluk adim sayaci (-1: bilinmiyor; eski kayit
  /// ya da buluttan gelen gun). Adim boyu olcumunde kullanilir.
  final int startSteps;
  final int endSteps;

  const RouteSegment({
    required this.day,
    required this.points,
    required this.startMs,
    required this.endMs,
    this.startSteps = -1,
    this.endSteps = -1,
  });

  int get steps =>
      startSteps >= 0 && endSteps >= startSteps ? endSteps - startSteps : -1;

  double get distanceM {
    var d = 0.0;
    for (var i = 1; i < points.length; i++) {
      d += RouteService.haversine(points[i - 1], points[i]);
    }
    return d;
  }

  int get durationMs => endMs > startMs ? endMs - startMs : 0;
}

/// Secili donemin rotasi.
class RouteData {
  final List<RouteSegment> segments;
  const RouteData(this.segments);

  static const empty = RouteData([]);

  bool get isEmpty => segments.every((s) => s.points.isEmpty);

  double get distanceM => segments.fold(0.0, (a, s) => a + s.distanceM);

  int get durationMs => segments.fold(0, (a, s) => a + s.durationMs);

  int get dayCount => segments.map((s) => s.day).toSet().length;

  List<LatLng> get allPoints => [for (final s in segments) ...s.points];
}

/// Native tarafin rota durumu.
class RouteStatus {
  final bool enabled;
  final bool fine;
  final bool background;
  final bool active;
  final bool serviceRunning;

  /// Telefonun Konum anahtari acik mi.
  final bool locationOn;

  /// Son gelen GPS konumunun dogrulugu (m; bilinmiyorsa null) ve yasi (sn).
  final double? lastAccuracy;
  final int? lastFixAgoSec;
  final LatLng? lastFix;

  /// Bugun kaydedilen ve dogruluk yetersizligi yuzunden elenen nokta sayisi.
  final int accepted;
  final int rejected;

  const RouteStatus({
    this.enabled = false,
    this.fine = false,
    this.background = false,
    this.active = false,
    this.serviceRunning = false,
    this.locationOn = true,
    this.lastAccuracy,
    this.lastFixAgoSec,
    this.lastFix,
    this.accepted = 0,
    this.rejected = 0,
  });

  /// Kayit icin gereken dogruluk siniri (RouteTracker.MAX_ACCURACY_M).
  static const maxAccuracyM = 50.0;

  /// Kayit acik ve konum izni var.
  bool get ready => enabled && fine;

  /// Uygulama kapaliyken de kayit yapabilir ("Her zaman izin ver").
  bool get fullyReady => ready && background;
}

/// Rota kaydinin Flutter tarafi: native RouteTracker (StepService icinde)
/// konumlari cihazda gunluk dosyalara yazar; burada okunur, haritaya
/// hazirlanir ve Firestore'a gunluk tek dokuman olarak yedeklenir.
///
/// Bulut modeli: users/{uid}/routes/{yyyy-MM-dd}
///   { day, segs: [encodedPolyline, ...], times: [bas0, bit0, bas1, bit1, ...] }
class RouteService {
  RouteService._();

  static const _channel = MethodChannel('adim_sayar/service');
  static const _syncKey = 'route_sync_json';
  static const _syncDays = 30;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // ------------------------------------------------------------------
  // Durum ve izinler
  // ------------------------------------------------------------------

  static Future<RouteStatus> status() async {
    if (!supported) return const RouteStatus();
    try {
      final raw = await _channel.invokeMethod<String>('routeStatus');
      if (raw == null) return const RouteStatus();
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return RouteStatus(
        enabled: m['enabled'] == true,
        fine: m['fine'] == true,
        background: m['background'] == true,
        active: m['active'] == true,
        serviceRunning: m['serviceRunning'] == true,
        locationOn: m['locationOn'] != false,
        lastAccuracy: (m['lastAccuracy'] is num && (m['lastAccuracy'] as num) >= 0)
            ? (m['lastAccuracy'] as num).toDouble()
            : null,
        lastFixAgoSec: (m['lastFixAgoSec'] is num && (m['lastFixAgoSec'] as num) >= 0)
            ? (m['lastFixAgoSec'] as num).toInt()
            : null,
        lastFix: (m['lastLat'] is num && m['lastLng'] is num)
            ? LatLng((m['lastLat'] as num).toDouble(), (m['lastLng'] as num).toDouble())
            : null,
        accepted: (m['accepted'] as num?)?.toInt() ?? 0,
        rejected: (m['rejected'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('Rota durumu okunamadi: $e');
      return const RouteStatus();
    }
  }

  /// Once "Uygulamayi kullanirken", ardindan "Her zaman" izni istenir.
  /// Android 11+ ikincisi icin sistem uygulamanin konum ayarini acar.
  /// Donus: hassas konum izni verildi mi.
  static Future<bool> requestPermissions() async {
    if (!supported) return false;
    try {
      final fg = await Permission.locationWhenInUse.request();
      if (!fg.isGranted) return false;
      final bg = await Permission.locationAlways.status;
      if (!bg.isGranted) await Permission.locationAlways.request();
      return true;
    } catch (e) {
      debugPrint('Konum izni istenemedi: $e');
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('setRouteEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('Rota ayari yazilamadi: $e');
    }
  }

  static Future<bool> isVoiceMuted() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isVoiceMuted') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setVoiceMuted(bool muted) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('setVoiceMuted', {'muted': muted});
    } catch (_) {}
  }

  /// Izin ayar ekranindan donuldugunde servis tipini tazeler.
  static Future<void> refresh() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('refreshRoute');
    } catch (_) {}
  }

  /// Cihazin bilinen son konumu (izin yoksa ya da bilinmiyorsa null).
  static Future<LatLng?> lastKnown() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<String>('lastLocation');
      if (raw == null) return null;
      final p = raw.split(',');
      if (p.length != 2) return null;
      final lat = double.tryParse(p[0]);
      final lng = double.tryParse(p[1]);
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  /// Telefonun Konum anahtari kapaliysa sistemin tek dokunuslu "Konumu ac"
  /// penceresini gosterir. Donus: konum acik mi.
  static Future<bool> requestLocationOn() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestLocationOn') ?? false;
    } catch (e) {
      debugPrint('Konum acma penceresi gosterilemedi: $e');
      return false;
    }
  }

  static const _centerKey = 'route_last_center';

  /// Haritanin acilis merkezi: en son bilinen konum (uygulama yeniden
  /// acildiginda harita Turkiye geneli yerine buradan baslar).
  static Future<LatLng?> savedCenter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_centerKey);
      if (raw == null) return null;
      final p = raw.split(',');
      final lat = double.tryParse(p[0]);
      final lng = p.length > 1 ? double.tryParse(p[1]) : null;
      return lat == null || lng == null ? null : LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCenter(LatLng p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_centerKey, '${p.latitude},${p.longitude}');
    } catch (_) {}
  }

  static Future<void> openLocationSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('openLocationSettings');
    } catch (e) {
      debugPrint('Konum ayarlari acilamadi: $e');
    }
  }

  static Future<void> openAppSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
    } catch (e) {
      debugPrint('Uygulama ayarlari acilamadi: $e');
    }
  }

  /// Cihazdaki rota dosyalarini siler.
  static Future<void> clear() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('clearRoutes');
    } catch (e) {
      debugPrint('Rotalar silinemedi: $e');
    }
  }

  /// Buluttaki users/{uid}/routes dokumanlarini ve yerel senkron kaydini
  /// siler ("Tum kayitlari sil"). Giris yoksa yalnizca yerel kayit temizlenir.
  static Future<void> clearCloud() async {
    _cloudCache.clear();
    _cloudRangesFetched.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_syncKey);
    } catch (_) {}
    final col = _col;
    if (col == null) return;
    try {
      // Batch en fazla 500 islem alir; parca parca silinir.
      while (true) {
        final snap = await col.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (snap.docs.length < 400) break;
      }
    } catch (e) {
      debugPrint('Buluttaki rotalar silinemedi: $e');
    }
  }

  // ------------------------------------------------------------------
  // Okuma
  // ------------------------------------------------------------------

  /// Donem uzunluguna gore seyreltme: gun 3 m, yil 40 m.
  static double gapFor(DateTime from, DateTime to) {
    final days = Metrics.daysBetween(from, to) + 1;
    if (days <= 1) return 3;
    if (days <= 7) return 10;
    if (days <= 31) return 20;
    return 40;
  }

  /// [from]..[to] (dahil) rotalari. Cihazda olmayan gunler buluttan tamamlanir.
  static Future<RouteData> load(DateTime from, DateTime to) async {
    final gap = gapFor(from, to);
    final local = await _loadLocal(from, to, gap);
    Map<String, List<RouteSegment>> cloud = const {};
    try {
      cloud = await _loadCloud(from, to).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Bulut rotalari okunamadi: $e');
    }
    final days = {...local.keys, ...cloud.keys}.toList()..sort();
    return RouteData([
      for (final d in days) ...(local[d] ?? cloud[d] ?? const <RouteSegment>[]),
    ]);
  }

  static Future<Map<String, List<RouteSegment>>> _loadLocal(
    DateTime from,
    DateTime to,
    double gap,
  ) async {
    if (!supported) return {};
    try {
      final raw = await _channel.invokeMethod<String>('getRoutes', {
        'from': Metrics.dayKey(from),
        'to': Metrics.dayKey(to),
        'minGap': gap,
      });
      if (raw == null) return {};
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      final out = <String, List<RouteSegment>>{};
      map.forEach((k, v) {
        final day = k.toString();
        if (!Metrics.isValidKey(day) || v is! List) return;
        final segs = <int, List<List<num>>>{};
        for (final e in v) {
          if (e is! List || e.length < 4) continue;
          final seg = (e[0] as num).toInt();
          segs.putIfAbsent(seg, () => []).add([
            e[1] as num,
            e[2] as num,
            e[3] as num,
            e.length > 4 && e[4] is num ? e[4] as num : -1,
          ]);
        }
        final keys = segs.keys.toList()..sort();
        out[day] = [
          for (final s in keys)
            RouteSegment(
              day: day,
              points: [
                for (final p in segs[s]!) LatLng(p[1].toDouble(), p[2].toDouble()),
              ],
              startMs: segs[s]!.first[0].toInt(),
              endMs: segs[s]!.last[0].toInt(),
              startSteps: segs[s]!.first[3].toInt(),
              endSteps: segs[s]!.last[3].toInt(),
            ),
        ];
      });
      return out;
    } catch (e) {
      debugPrint('Rotalar okunamadi: $e');
      return {};
    }
  }

  /// Oturum boyunca buluttan okunan gunler (tekrar okuma olmasin).
  static final Map<String, List<RouteSegment>> _cloudCache = {};
  static final Set<String> _cloudRangesFetched = {};

  static CollectionReference<Map<String, dynamic>>? get _col {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('routes');
  }

  static Future<Map<String, List<RouteSegment>>> _loadCloud(
    DateTime from,
    DateTime to,
  ) async {
    final col = _col;
    if (col == null) return {};
    final a = Metrics.dayKey(from);
    final b = Metrics.dayKey(to);
    final rangeKey = '$a|$b';
    if (!_cloudRangesFetched.contains(rangeKey)) {
      final snap = await col
          .where('day', isGreaterThanOrEqualTo: a)
          .where('day', isLessThanOrEqualTo: b)
          .get();
      for (final doc in snap.docs) {
        final segs = _decodeDoc(doc.id, doc.data());
        if (segs.isNotEmpty) _cloudCache[doc.id] = segs;
      }
      _cloudRangesFetched.add(rangeKey);
    }
    return {
      for (final e in _cloudCache.entries)
        if (e.key.compareTo(a) >= 0 && e.key.compareTo(b) <= 0) e.key: e.value,
    };
  }

  static List<RouteSegment> _decodeDoc(String day, Map<String, dynamic> data) {
    final segs = data['segs'];
    final times = data['times'];
    if (segs is! List) return const [];
    final out = <RouteSegment>[];
    for (var i = 0; i < segs.length; i++) {
      final pts = decodePolyline(segs[i].toString());
      if (pts.isEmpty) continue;
      int t(int j) =>
          (times is List && j < times.length && times[j] is num) ? (times[j] as num).toInt() : 0;
      out.add(RouteSegment(
        day: day,
        points: pts,
        startMs: t(i * 2),
        endMs: t(i * 2 + 1),
      ));
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Bulut yedegi
  // ------------------------------------------------------------------

  static bool _syncing = false;

  /// Son [_syncDays] gunun degisen ya da hic gonderilmemis rotasini buluta
  /// yazar (gun basina tek dokuman). Uygulama gunlerce acilmasa da aradaki
  /// gunler ilk acilista gider; degismeyen gun tekrar yazilmaz.
  static Future<void> syncRecent() async {
    if (!supported || _syncing) return;
    final col = _col;
    if (col == null) return;
    _syncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> sent = {};
      try {
        sent = jsonDecode(prefs.getString(_syncKey) ?? '{}') as Map<String, dynamic>;
      } catch (_) {}

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final from = Metrics.addDays(today, -(_syncDays - 1));
      final local = await _loadLocal(from, today, 6);
      var changed = false;
      for (final e in local.entries) {
        final segs = e.value.where((s) => s.points.length >= 2).toList();
        if (segs.isEmpty) continue;
        final count = segs.fold<int>(0, (a, s) => a + s.points.length);
        final sig = '${segs.length}_${count}_${segs.last.endMs}';
        if (sent[e.key] == sig) continue;
        await col.doc(e.key).set({
          'day': e.key,
          'segs': [for (final s in segs) encodePolyline(s.points)],
          'times': [for (final s in segs) ...[s.startMs, s.endMs]],
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _cloudCache[e.key] = segs;
        sent[e.key] = sig;
        changed = true;
      }
      if (changed) {
        final keep = Metrics.dayKey(Metrics.addDays(today, -(_syncDays + 5)));
        sent.removeWhere((k, _) => k.compareTo(keep) < 0);
        await prefs.setString(_syncKey, jsonEncode(sent));
      }
    } catch (e) {
      debugPrint('Rota yedegi yazilamadi: $e');
    } finally {
      _syncing = false;
    }
  }

  // ------------------------------------------------------------------
  // GPS ile adim boyu olcumu
  // ------------------------------------------------------------------

  /// Son 60 gunun rota parcalarindan adim boyu (m) ve ornek sayisi.
  ///
  /// Ornek sayilan parca: en az 250 m ve 300 adim, en az 3 dk, dakikada
  /// 80-135 adim (yuruyus; kosu ve dur-kalk disarida), adim boyu 45-100 cm.
  /// Sonuc son 20 ornegin medyani (tek bir kotu GPS olcumu sonucu bozmaz).
  static Future<(double, int)?> measureStride() async {
    if (!supported) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final local = await _loadLocal(Metrics.addDays(today, -59), today, 3);
    final samples = <(int, double)>[];
    for (final segs in local.values) {
      for (final s in segs) {
        final steps = s.steps;
        if (steps < 300) continue;
        final minutes = s.durationMs / 60000;
        if (minutes < 3) continue;
        final cadence = steps / minutes;
        if (cadence < 80 || cadence > 135) continue;
        final dist = s.distanceM;
        if (dist < 250) continue;
        final stride = dist / steps;
        if (stride < 0.45 || stride > 1.0) continue;
        samples.add((s.startMs, stride));
      }
    }
    if (samples.isEmpty) return null;
    samples.sort((a, b) => b.$1.compareTo(a.$1));
    final recent = samples.take(20).map((e) => e.$2).toList()..sort();
    final mid = recent.length ~/ 2;
    final median = recent.length.isOdd
        ? recent[mid]
        : (recent[mid - 1] + recent[mid]) / 2;
    return (double.parse(median.toStringAsFixed(3)), samples.length);
  }

  // ------------------------------------------------------------------
  // Yuruyus kaydi (baslat / bitir) ve aralikli yuruyus
  // ------------------------------------------------------------------

  static Future<bool> startWorkout({
    bool interval = false,
    int rounds = 5,
    int fastSec = 180,
    int slowSec = 180,
  }) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('workoutStart', {
            'interval': interval,
            'rounds': rounds,
            'fastSec': fastSec,
            'slowSec': slowSec,
          }) ??
          false;
    } catch (e) {
      debugPrint('Yuruyus baslatilamadi: $e');
      return false;
    }
  }

  static Future<Workout?> stopWorkout() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<String>('workoutStop');
      if (raw == null) return null;
      return Workout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Yuruyus bitirilemedi: $e');
      return null;
    }
  }

  static Future<WorkoutStatus> workoutStatus() async {
    if (!supported) return const WorkoutStatus();
    try {
      final raw = await _channel.invokeMethod<String>('workoutStatus');
      if (raw == null) return const WorkoutStatus();
      return WorkoutStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const WorkoutStatus();
    }
  }

  /// Kayitli yuruyusler (yeniden eskiye).
  static Future<List<Workout>> workouts() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('workouts');
      final list = jsonDecode(raw ?? '[]');
      if (list is! List) return const [];
      return [
        for (final e in list.reversed)
          if (e is Map<String, dynamic>) Workout.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------------
  // Yardimcilar
  // ------------------------------------------------------------------

  static double haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _rad(double d) => d * math.pi / 180;

  /// Google encoded polyline (1e5 hassasiyet, ~1 m).
  static String encodePolyline(List<LatLng> points) {
    final b = StringBuffer();
    var pLat = 0;
    var pLng = 0;
    void enc(int v) {
      var n = v < 0 ? ~(v << 1) : (v << 1);
      while (n >= 0x20) {
        b.writeCharCode((0x20 | (n & 0x1f)) + 63);
        n >>= 5;
      }
      b.writeCharCode(n + 63);
    }

    for (final p in points) {
      final lat = (p.latitude * 1e5).round();
      final lng = (p.longitude * 1e5).round();
      enc(lat - pLat);
      enc(lng - pLng);
      pLat = lat;
      pLng = lng;
    }
    return b.toString();
  }

  static List<LatLng> decodePolyline(String s) {
    final out = <LatLng>[];
    var i = 0;
    var lat = 0;
    var lng = 0;
    int? next() {
      var shift = 0;
      var result = 0;
      int c;
      do {
        if (i >= s.length) return null;
        c = s.codeUnitAt(i++) - 63;
        result |= (c & 0x1f) << shift;
        shift += 5;
      } while (c >= 0x20);
      return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    }

    while (i < s.length) {
      final dLat = next();
      final dLng = next();
      if (dLat == null || dLng == null) break;
      lat += dLat;
      lng += dLng;
      out.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return out;
  }
}

/// Suren yuruyusun canli durumu.
class WorkoutStatus {
  final bool active;
  final int startMs;
  final int elapsedSec;
  final double distanceM;
  final int steps;
  final List<int> splits;
  final bool interval;
  final int round;
  final int rounds;
  final bool fast;
  final bool intervalDone;
  final int phaseLeftSec;

  const WorkoutStatus({
    this.active = false,
    this.startMs = 0,
    this.elapsedSec = 0,
    this.distanceM = 0,
    this.steps = 0,
    this.splits = const [],
    this.interval = false,
    this.round = 0,
    this.rounds = 0,
    this.fast = true,
    this.intervalDone = false,
    this.phaseLeftSec = 0,
  });

  factory WorkoutStatus.fromJson(Map<String, dynamic> m) => WorkoutStatus(
        active: m['active'] == true,
        startMs: (m['start'] as num?)?.toInt() ?? 0,
        elapsedSec: (m['elapsedSec'] as num?)?.toInt() ?? 0,
        distanceM: (m['distanceM'] as num?)?.toDouble() ?? 0,
        steps: (m['steps'] as num?)?.toInt() ?? 0,
        splits: [
          for (final e in (m['splits'] as List? ?? const []))
            if (e is num) e.toInt(),
        ],
        interval: m['interval'] == true,
        round: (m['round'] as num?)?.toInt() ?? 0,
        rounds: (m['rounds'] as num?)?.toInt() ?? 0,
        fast: m['fast'] != false,
        intervalDone: m['intervalDone'] == true,
        phaseLeftSec: (m['phaseLeftSec'] as num?)?.toInt() ?? 0,
      );
}

/// Bitmis bir yuruyusun ozeti.
class Workout {
  final int startMs;
  final int endMs;
  final int durationSec;
  final double distanceM;
  final int steps;
  final List<int> splits;
  final bool interval;
  final int rounds;
  final String day;

  const Workout({
    required this.startMs,
    required this.endMs,
    required this.durationSec,
    required this.distanceM,
    required this.steps,
    required this.splits,
    required this.interval,
    required this.rounds,
    required this.day,
  });

  factory Workout.fromJson(Map<String, dynamic> m) => Workout(
        startMs: (m['start'] as num?)?.toInt() ?? 0,
        endMs: (m['end'] as num?)?.toInt() ?? 0,
        durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
        distanceM: (m['distanceM'] as num?)?.toDouble() ?? 0,
        steps: (m['steps'] as num?)?.toInt() ?? 0,
        splits: [
          for (final e in (m['splits'] as List? ?? const []))
            if (e is num) e.toInt(),
        ],
        interval: m['interval'] == true,
        rounds: (m['rounds'] as num?)?.toInt() ?? 0,
        day: m['day']?.toString() ?? '',
      );

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs);

  /// Ortalama tempo (sn/km); 200 m altinda anlamsiz.
  int? get paceSecPerKm =>
      distanceM < 200 ? null : (durationSec / (distanceM / 1000)).round();
}

/// 754 sn -> "12:34", 3700 -> "1:01:40".
String clockText(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Tempo metni: 612 -> "10:12 /km".
String paceText(int? secPerKm) =>
    secPerKm == null || secPerKm <= 0 || secPerKm > 3600
        ? '-'
        : '${secPerKm ~/ 60}:${(secPerKm % 60).toString().padLeft(2, '0')} /km';
