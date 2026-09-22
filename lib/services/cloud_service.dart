import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/intensity.dart';

/// Buluttan cekilen verinin cozulmus hali.
class CloudSnapshot {
  final Map<String, int> history;
  final Map<String, int> waterHistory;
  final Map<String, List<int>> hourly;
  final Map<String, List<int>> intensity;
  final int? goal;
  final int? heightCm;
  final double? weightKg;

  /// Kilo kaydi { "2026-09-22": 92.4 } (kullanici dokumaninda).
  final Map<String, double> weightLog;

  const CloudSnapshot({
    required this.history,
    this.waterHistory = const {},
    required this.hourly,
    this.intensity = const {},
    this.goal,
    this.heightCm,
    this.weightKg,
    this.weightLog = const {},
  });

  bool get isEmpty => history.isEmpty && hourly.isEmpty && waterHistory.isEmpty && goal == null && weightLog.isEmpty;
}

/// Firestore senkronu.
///
/// Veri modeli:
///   users/{uid}               -> profil + ayarlar
///   users/{uid}/years/{yyyy}  -> { days: { "2026-09-20": 8421, ... } }
///   users/{uid}/data/steps    -> { hourly: { "2026-09-20": [24 deger] },
///                                  intensity: { "2026-09-20": [5 deger] } }
///
/// Gecmis yillara bolunur: tek dokumanin 1 MiB siniri boylece hic devreye
/// girmez ve her senkronda yalnizca degisen yil yazilir (tipik olarak 1
/// yazma). Saatlik dagilim 60 gunle sinirli oldugundan tek dokumanda kalir.
///
/// Adim olaylari saniyede bir gelebildigi icin yazmalar [_debounce]
/// suresiyle birlestirilir.
class CloudService {
  final String uid;
  CloudService(this.uid);

  static const Duration _debounce = Duration(seconds: 45);

  Timer? _timer;
  bool _disposed = false;
  bool _pushing = false;

  Map<String, int>? _pendingHistory;
  Map<String, int>? _pendingWaterHistory;
  Map<String, List<int>>? _pendingHourly;
  Map<String, List<int>>? _pendingIntensity;
  int? _pendingGoal;
  int? _pendingHeight;
  double? _pendingWeight;

  /// Yil -> en son yazilan icerigin imzasi. Degismeyen yil tekrar yazilmaz.
  final Map<String, String> _pushedYears = {};

  /// Eski surumde gecmis data/steps icinde tutuluyordu; bir kez tasinir.
  bool _legacyHistoryFound = false;

  /// Bu oturumda buluttaki veri okunup yerel veriyle birlestirildi mi.
  /// Birlestirilmeden yazilirsa telefondaki eksik veri buluttakini ezer
  /// (ornegin yavas baglantida giris yapildiginda).
  bool _pulled = false;

  /// Ayni anda birden fazla okuma baslamasin.
  Future<bool>? _pullInFlight;

  /// Buluttan okunan veriyi yerel veriyle birlestiren geri cagri.
  /// Giris kapisi (_CloudGate) tarafindan atanir.
  Future<void> Function(CloudSnapshot snapshot)? onRemoteLoaded;

  String? lastError;
  DateTime? lastSyncedAt;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> get _stepsDoc =>
      _userDoc.collection('data').doc('steps');

  CollectionReference<Map<String, dynamic>> get _yearsCol =>
      _userDoc.collection('years');

  /// Ilk giriste veya yeniden baglanmada buluttaki veriyi getirir.
  /// Baglanti yoksa Firestore onbellekten doner; o da yoksa null.
  Future<CloudSnapshot?> pull() async {
    try {
      // Uc istek paralel gider; giris ekraninda bekleme kisalir.
      final stepsFuture = _stepsDoc.get();
      final profileFuture = _userDoc.get();
      final yearsFuture = _yearsCol.get();

      final steps = await stepsFuture;
      final profile = await profileFuture;
      final years = await yearsFuture;

      final history = <String, int>{};
      final waterHistory = <String, int>{};

      // Eski surumden kalan kayitlar.
      final legacy = steps.data()?['history'];
      if (legacy is Map && legacy.isNotEmpty) {
        _legacyHistoryFound = true;
        _mergeDays(history, legacy);
      }

      for (final doc in years.docs) {
        final data = doc.data();
        final days = data['days'];
        if (days is Map) _mergeDays(history, days);
        
        final waterDays = data['waterDays'];
        if (waterDays is Map) _mergeDays(waterHistory, waterDays);
      }

      final hourly = <String, List<int>>{};
      final rawHourly = steps.data()?['hourly'];
      if (rawHourly is Map) {
        rawHourly.forEach((k, v) {
          final key = k.toString();
          if (!_validKey(key) || v is! List || v.length != 24) return;
          hourly[key] = v.map((e) => (e as num).toInt()).toList();
        });
      }

      final intensity = Intensity.decodeMap(steps.data()?['intensity']);

      final p = profile.data();
      lastError = null;
      return CloudSnapshot(
        history: history,
        waterHistory: waterHistory,
        hourly: hourly,
        intensity: intensity,
        goal: (p?['goal'] as num?)?.toInt(),
        heightCm: (p?['heightCm'] as num?)?.toInt(),
        weightKg: (p?['weightKg'] as num?)?.toDouble(),
        weightLog: _decodeWeights(p?['weightLog']),
      );
    } catch (e) {
      lastError = _describe(e);
      debugPrint('CloudService.pull hatasi: $e');
      return null;
    }
  }

  /// Buluttaki veriyi okur, [onRemoteLoaded] ile birlestirir ve yazma
  /// kilidini acar. Okuma basarisizsa false doner ve yazma yapilmaz.
  Future<bool> pullAndApply() =>
      _pullInFlight ??= _pullAndApply().whenComplete(() {
        _pullInFlight = null;
      });

  Future<bool> _pullAndApply() async {
    final snapshot = await pull();
    if (snapshot == null) return false;
    final apply = onRemoteLoaded;
    if (apply != null && !_disposed) await apply(snapshot);
    _pulled = true;
    return true;
  }

  static void _mergeDays(Map<String, int> into, Map raw) {
    raw.forEach((k, v) {
      final key = k.toString();
      final value = v is num ? v.toInt() : int.tryParse(v.toString());
      if (value == null || value < 0 || !_validKey(key)) return;
      final current = into[key] ?? 0;
      if (value > current) into[key] = value;
    });
  }

  /// Yazmayi kuyruga alir; [_debounce] sonunda tek istekte gonderir.
  void schedulePush({
    required Map<String, int> history,
    Map<String, int>? waterHistory,
    required Map<String, List<int>> hourly,
    Map<String, List<int>>? intensity,
    required int goal,
    required int heightCm,
    required double weightKg,
  }) {
    if (_disposed) return;
    _pendingHistory = Map<String, int>.from(history);
    if (waterHistory != null) {
      _pendingWaterHistory = Map<String, int>.from(waterHistory);
    }
    _pendingHourly = hourly.map((k, v) => MapEntry(k, List<int>.from(v)));
    if (intensity != null) {
      _pendingIntensity =
          intensity.map((k, v) => MapEntry(k, List<int>.from(v)));
    }
    _pendingGoal = goal;
    _pendingHeight = heightCm;
    _pendingWeight = weightKg;

    _scheduleRetry();
  }

  /// Sadece su verisini kuyruga ekler ve push planlar.
  void scheduleWaterPush(Map<String, int> waterHistory) {
    if (_disposed) return;
    _pendingWaterHistory = Map<String, int>.from(waterHistory);
    _scheduleRetry();
  }

  /// Bekleyen yazmayi [_debounce] sonra (yeniden) dener.
  void _scheduleRetry() {
    if (_disposed || _timer != null) return;
    _timer = Timer(_debounce, () {
      _timer = null;
      flush();
    });
  }

  /// Bekleyen yazmayi hemen gonderir (uygulama arka plana alininca cagrilir).
  Future<void> flush() async {
    if (_disposed) return;
    // Onceki yazma surerken cagrilirsa kuyruk askida kalmasin: timer
    // iptal edilmis olabilecegi icin yeniden kurulur.
    if (_pushing) {
      _scheduleRetry();
      return;
    }
    // Buluttaki veri bu oturumda henuz okunup birlestirilmediyse once o
    // yapilir; okunamazsa yazma ertelenir. Aksi halde telefondaki eksik
    // veri buluttaki daha buyuk degerleri ezerdi.
    if (!_pulled) {
      var ok = false;
      try {
        ok = await pullAndApply();
      } catch (e) {
        debugPrint('CloudService okuma/birlestirme hatasi: $e');
      }
      if (!ok) {
        if (_pendingHistory != null) _scheduleRetry();
        return;
      }
      if (_disposed) return;
      if (_pushing) {
        _scheduleRetry();
        return;
      }
    }
    final history = _pendingHistory;
    final waterHistory = _pendingWaterHistory;
    final hourly = _pendingHourly;
    final intensity = _pendingIntensity;
    
    // Eger sadece su gecmisi bekliyorsa ve adim saatlik verisi yoksa 
    // su'yu yollayabiliriz. Onceden hourly == null check vardi. 
    if (history == null && waterHistory == null) return;
    if (history != null && hourly == null) return; // Adim gecmisi varsa hourly de olmali

    _timer?.cancel();
    _timer = null;
    _pushing = true;
    try {
      final byYear = <String, Map<String, int>>{};
      history?.forEach((day, steps) {
        if (!_validKey(day)) return;
        byYear.putIfAbsent(day.substring(0, 4), () => {})[day] = steps;
      });

      final waterByYear = <String, Map<String, int>>{};
      waterHistory?.forEach((day, ml) {
        if (!_validKey(day)) return;
        waterByYear.putIfAbsent(day.substring(0, 4), () => {})[day] = ml;
      });

      final batch = FirebaseFirestore.instance.batch();

      final yearsToUpdate = {...byYear.keys, ...waterByYear.keys};

      for (final year in yearsToUpdate) {
        final days = byYear[year];
        final waterDays = waterByYear[year];
        
        // Sadece degisenleri yazmak icin imza. Basitlestirmek adina
        // eger history ya da waterHistory'den herhangi biri geldiyse yazariz.
        final signature = jsonEncode({'days': days, 'waterDays': waterDays});
        if (_pushedYears[year] == signature) continue;
        
        batch.set(
          _yearsCol.doc(year),
          {
            if (days != null) 'days': days,
            if (waterDays != null) 'waterDays': waterDays,
            'updatedAt': FieldValue.serverTimestamp()
          },
          SetOptions(merge: true),
        );
        _pushedYears[year] = signature;
      }

      if (hourly != null) {
        batch.set(
          _stepsDoc,
          {
            'hourly': hourly,
            if (intensity != null) 'intensity': intensity,
            'updatedAt': FieldValue.serverTimestamp(),
            // Gecmis artik yil dokumanlarinda; eski alan bir kez temizlenir.
            // Batch atomik oldugundan yil dokumanlari yazilmadan silinmez.
            if (_legacyHistoryFound && byYear.isNotEmpty)
              'history': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
      }

      batch.set(
        _userDoc,
        {
          if (_pendingGoal != null) 'goal': _pendingGoal,
          if (_pendingHeight != null) 'heightCm': _pendingHeight,
          if (_pendingWeight != null) 'weightKg': _pendingWeight,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (byYear.isNotEmpty) _legacyHistoryFound = false;
      _pendingHistory = null;
      _pendingWaterHistory = null;
      _pendingHourly = null;
      _pendingIntensity = null;
      lastError = null;
      lastSyncedAt = DateTime.now();
    } catch (e) {
      // Yazilmis sayilan yillar geri alinir, sonraki denemede tekrar gonderilir.
      _pushedYears.clear();
      lastError = _describe(e);
      debugPrint('CloudService.flush hatasi: $e');
    } finally {
      _pushing = false;
      // Yazma sirasinda yeni veri kuyruga girdiyse ya da hata olup kayit
      // duruyorsa bekleyen yazma askida kalmasin.
      if (_pendingHistory != null) _scheduleRetry();
    }
  }

  /// "Tum kayitlari sil" icin: buluttaki gecmisi tamamen kaldirir.
  /// Yil dokumanlari silinmezse bir sonraki giriste veri geri gelir.
  Future<void> clearRemote() async {
    _timer?.cancel();
    _timer = null;
    _pendingHistory = null;
    _pendingWaterHistory = null;
    _pendingHourly = null;
    _pendingIntensity = null;
    try {
      final years = await _yearsCol.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in years.docs) {
        batch.delete(doc.reference);
      }
      batch.set(
        _stepsDoc,
        {
          'hourly': <String, dynamic>{},
          'intensity': FieldValue.delete(),
          'history': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      _pushedYears.clear();
      _legacyHistoryFound = false;
      // Bulut artik bos; yerel veri tek kaynak, okumaya gerek yok.
      _pulled = true;
      lastError = null;
      lastSyncedAt = DateTime.now();
    } catch (e) {
      lastError = _describe(e);
      debugPrint('CloudService.clearRemote hatasi: $e');
    }
  }

  /// Elle duzeltilen tek bir gunu buluta yazar. "Buyuk olan kazanir"
  /// birlestirmesini atlar: deger dogrudan yazilir, o gunun saatlik
  /// kaydi silinir.
  Future<void> setDay(String day, int steps) async {
    if (_disposed || !_validKey(day)) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        _yearsCol.doc(day.substring(0, 4)),
        {
          'days': {day: steps},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      batch.set(
        _stepsDoc,
        {
          'hourly': {day: FieldValue.delete()},
          'intensity': {day: FieldValue.delete()},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      _pushedYears.remove(day.substring(0, 4));
      lastError = null;
      lastSyncedAt = DateTime.now();
    } catch (e) {
      lastError = _describe(e);
      debugPrint('CloudService.setDay hatasi: $e');
    }
  }

  /// Giristen hemen sonra profil bilgisini yazar.
  Future<void> saveProfile({String? email, String? displayName}) async {
    try {
      await _userDoc.set({
        if (email != null) 'email': email,
        if (displayName != null) 'displayName': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      lastError = _describe(e);
      debugPrint('CloudService.saveProfile hatasi: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  static Map<String, double> _decodeWeights(Object? raw) {
    final out = <String, double>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final key = k.toString();
      if (_validKey(key) && v is num && v >= 30 && v <= 250) {
        out[key] = v.toDouble();
      }
    });
    return out;
  }

  /// Tek bir kilo kaydini yazar ya da siler (kg == null).
  Future<void> setWeight(String day, double? kg) async {
    if (_disposed || !_validKey(day)) return;
    try {
      await _userDoc.set({
        'weightLog': {day: kg ?? FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      lastError = _describe(e);
      debugPrint('CloudService.setWeight hatasi: $e');
    }
  }

  static bool _validKey(String k) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k);

  static String _describe(Object e) {
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' => 'Firestore kurallari erisime izin vermiyor.',
        'unavailable' => 'Baglanti yok, veriler cihazda bekliyor.',
        'failed-precondition' => 'Firestore veritabani olusturulmamis.',
        _ => 'Bulut hatasi: ${e.code}',
      };
    }
    return 'Bulut hatasi: $e';
  }
}
