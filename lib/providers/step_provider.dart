import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/backup_service.dart';
import '../services/cloud_service.dart';
import '../services/prefs_service.dart';
import '../services/route_service.dart';
import '../services/foreground_service.dart';
import '../services/notification_service.dart';
import '../services/step_detector_service.dart';
import '../services/widget_service.dart';
import '../utils/aggregate.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';
import '../utils/achievements.dart';

enum SensorState { idle, running, denied, unavailable, demo }

/// Android TYPE_STEP_COUNTER cihaz acilisindan beri toplam adim verir.
/// Gunluk deger = bugun birikeni + (guncel sayac - oturum baslangic degeri).
class StepProvider extends ChangeNotifier {
  final PrefsService prefs;
  StepProvider(this.prefs) {
    _restore();
    _overridden = prefs.overriddenDays;
    // Gun gecisi ve servis senkronu yalnizca gercek cihazda anlamli;
    // web/masaustu demo modunda bosuna timer calismasin.
    if (isMobile) {
      _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _checkDayRollover();
        _syncFromBackground();
      });
    }
  }

  StreamSubscription<int>? _counterSub;
  StreamSubscription<StepCount>? _stepSub;
  Timer? _idleTimer;
  Timer? _dayTimer;
  Timer? _demoTimer;
  Timer? _persistTimer;

  /// start() yeniden girilebilir olmamali; ust uste cagrilirsa eski
  /// abonelikler sizar ve ayni adim birden fazla sayilir.
  bool _starting = false;

  /// Her start() cagrisinda artar; gecikmeli calisan servis denemesi
  /// kendi turunun hala gecerli oldugunu bu jetonla anlar.
  int _startToken = 0;

  /// Tek bir sayac olayinda bugune eklenebilecek en fazla adim.
  /// Uzun sure acilmamis uygulamada birikmis fark bugune yazilmasin.
  /// Tek gunde makul ust sinir; 40000 cok gevsekti ve birkac gunun
  /// toplami bu esigi asmadigi icin bugune yaziliyordu.
  static const int _maxCatchUp = 15000;

  /// Saatlik kayit bir donemin adimlarinin en az bu oranini kapsamiyorsa
  /// "gercek sure" olarak kullanilmaz, tahmine dusulur. Servisten veya
  /// buluttan gelen adimlar saate yazilmadigi ve saatlik kayit 60 gunle
  /// sinirli oldugu icin kismi veri sure/kalori hesabini bozuyordu.
  static const double _coverageRatio = 0.8;

  /// Saatlik kaydin tutuldugu gun sayisi.
  static const int _hourlyKeepDays = 365;

  /// Tek sayac olayinda saatlik kayda yazilabilecek en fazla artis. On
  /// plandayken olaylar adim adim gelir; bundan buyuk bir artis uygulama
  /// arka plandayken birikmis adimlardir ve acilis saatine yigilmamalidir.
  static const int _maxLiveHourlyDelta = 300;

  /// dispose() sonrasi gec gelen async geri cagrilar notifyListeners
  /// tetiklemesin.
  bool _disposed = false;

  /// Web / masaustunde sensor eklentisi yok -> demo verisi kullanilir.
  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  int _todaySteps = 0;
  int _savedToday = 0;
  int _baseline = -1;
  String _date = '';
  String _walkStatus = 'Bilinmiyor';
  String? _lastError;
  String _permissionLabel = 'bilinmiyor';
  int _eventCount = 0;
  int _lastRawSensor = -1;
  SensorState _state = SensorState.idle;
  Map<String, int> _history = {};
  Map<String, List<int>> _hourly = {};

  /// Tempo kirilimi (native servis dakika kadansindan uretir).
  Map<String, List<int>> _intensity = {};

  /// Kullanicinin elle duzelttigi gecmis gunler. Servisten ve buluttan
  /// gelen degerler bu gunlerin uzerine yazilmaz.
  Set<String> _overridden = {};

  int get todaySteps => _todaySteps;

  /// Gecikmesiz donanim kanali kullaniliyor mu (tanilama icin).
  bool get fastSensor => _counterSub != null;
  String get walkStatus => _walkStatus;
  SensorState get state => _state;
  String? get lastError => _lastError;
  String get permissionLabel => _permissionLabel;
  int get eventCount => _eventCount;
  int get lastRawSensor => _lastRawSensor;

  Map<String, int> get history => _history;

  /// Kalici bildirim servisi gercekten calisiyor mu.
  bool get backgroundRunning => ForegroundService.running;

  CloudService? _cloud;

  /// Bagli bulut servisi (kilo kaydi gibi tekil yazmalar icin).
  CloudService? get cloud => _cloud;

  /// Bulut senkronu acik mi (giris yapilmis mi).
  bool get cloudEnabled => _cloud != null;
  String? get cloudError => _cloud?.lastError;
  DateTime? get cloudLastSyncedAt => _cloud?.lastSyncedAt;

  /// Giriste baglanir, cikista null ile cozulur.
  void attachCloud(CloudService? cloud) {
    _cloud = cloud;
    notifyListeners();
  }

  /// Yalnizca hala bagli olan servis buysa cozer. Oturum degisiminde eski
  /// kapinin dispose'u, yeni kapinin bagladigi servisi koparmasin.
  void detachCloud(CloudService cloud) {
    if (!identical(_cloud, cloud)) return;
    _cloud = null;
    notifyListeners();
  }

  /// Mevcut veriyi bulut kuyruguna alir; gercek yazma gecikmeli yapilir.
  void pushToCloud() {
    _cloud?.schedulePush(
      history: _history,
      hourly: _hourly,
      intensity: _intensity,
      goal: prefs.goal,
      heightCm: prefs.heightCm,
      weightKg: prefs.weightKg,
    );
  }

  /// Bekleyen bulut yazmasini hemen gonderir.
  Future<void> flushCloud() async {
    if (_cloud == null) return;
    pushToCloud();
    await _cloud!.flush();
  }

  /// Secili gunun 24 saatlik dagilimi.
  /// Cagiran taraf (HourChart) diziyi 24 kez indeksledigi icin uzunluk
  /// her kosulda garanti edilir.
  List<int> hourlyFor(DateTime day) {
    final hours = _hourly[Metrics.dayKey(day)];
    if (hours == null || hours.length != 24) return List<int>.filled(24, 0);
    return hours;
  }

  /// Tarih araligindaki gunlerin saatlik kayitlarindan gercek aktif sure.
  ///
  /// Saatlik kayit yalnizca son [_hourlyKeepDays] gun icin ve yalnizca
  /// uygulama on plandayken tutuluyor. Kismi veriyi "gercek sure" saymak
  /// ozellikle Ay/Yil donemlerinde sureyi absurt kisa, kaloriyi absurt
  /// yuksek gosteriyordu. Bu yuzden hem gun hem adim kapsamasi kontrol
  /// edilir; yetersizse null donulur ve cagiran taraf tahmine duser.
  int? activeMinutesBetween(DateTime from, DateTime to) {
    var total = 0;
    var days = 0;
    var coveredDays = 0;
    var stepsInRange = 0;
    var stepsCovered = 0;

    _history.forEach((k, v) {
      if (v <= 0) return;
      final d = Metrics.tryParseKey(k);
      if (d == null || d.isBefore(from) || d.isAfter(to)) return;
      days++;
      stepsInRange += v;

      final hours = _hourly[k];
      if (hours == null || hours.length != 24) return;
      coveredDays++;
      stepsCovered += hours.fold<int>(0, (a, b) => a + b);
      total += Metrics.activeMinutesFromHours(hours);
    });

    if (days == 0 || total <= 0) return null;
    if (coveredDays / days < _coverageRatio) return null;
    if (stepsInRange > 0 && stepsCovered < stepsInRange * _coverageRatio) {
      return null;
    }
    return total;
  }

  /// Saatlik kayit varsa gercek aktif sure, yoksa null (tahmine dusulur).
  /// Kayit gunun adimlarinin cogunu kapsamiyorsa da null doner: servisten
  /// veya buluttan gelen adimlar saatlik kayda yazilmadigi icin sure
  /// oldugundan kisa, kalori oldugundan yuksek cikiyordu.
  int? activeMinutesFor(DateTime day) {
    final key = Metrics.dayKey(day);
    final hours = _hourly[key];
    if (hours == null || hours.length != 24) return null;

    final steps = _history[key] ?? 0;
    final covered = hours.fold<int>(0, (a, b) => a + b);
    if (steps > 0 && covered < steps * _coverageRatio) return null;

    final minutes = Metrics.activeMinutesFromHours(hours);
    return minutes > 0 ? minutes : null;
  }

  /// Tum kayitli gunler icin gercek aktif sure; kapsama yetersizse null.
  /// Istatistik ekranindaki "Tum zamanlar" karti bunu kullanir, boylece
  /// ayni adim sayisi icin Bugun karti ile ayni kalori cikar.
  int? get activeMinutesAllTime {
    DateTime? first;
    DateTime? last;
    _history.forEach((k, v) {
      if (v <= 0) return;
      final d = Metrics.tryParseKey(k);
      if (d == null) return;
      if (first == null || d.isBefore(first!)) first = d;
      if (last == null || d.isAfter(last!)) last = d;
    });
    if (first == null || last == null) return null;
    return activeMinutesBetween(first!, last!);
  }

  void _restore() {
    _history = prefs.history;
    _hourly = prefs.hourly;
    _intensity = prefs.intensity;
    _savedToday = prefs.savedToday;
    _baseline = prefs.baseline;
    _date = prefs.lastDate;

    final now = DateTime.now();
    final today = Metrics.dayKey(now);
    if (_date != today) {
      // KRITIK: gun degistiginde taban HER ZAMAN sifirlanir.
      //
      // _baseline "son olaydan beri" degil, "son taban sifirlamasindan
      // beri" referanstir ve gun icinde sabit kalir (kural:
      // _todaySteps == _savedToday + (raw - _baseline)). Dolayisiyla gun
      // sinirinda tabani korumak "gece yarisi civarindaki birkac adimi"
      // degil DUNUN TAMAMINI bugune devreder: dun 8732 adim atildiysa
      // gece yarisindan sonraki ilk olayda bugun 8732 ile basliyordu.
      //
      // -1 birakilinca bir sonraki sayac olayi tabani o ana cakar ve gun
      // sifirdan baslar. Servis calisiyorsa gece yarisi civarindaki
      // adimlar zaten onun kaydinda; syncFromService -> importHistory ile
      // geri gelir, ayrica burada devretmeye gerek yoktur.
      _baseline = -1;
      _date = today;
      // Arka plan servisi gece yarisini yakalamis olabilir; bugunun
      // kayitli degeri varsa esas alinir.
      _todaySteps = _history[today] ?? 0;
      // Degismez kural: _todaySteps == _savedToday + (raw - _baseline)
      _savedToday = _todaySteps;
      return;
    }

    // Gunun kayitli toplami esas alinir. Cihaz yeniden baslatilmissa
    // donanim sayaci sifirdan baslar; _savedToday'e dusulurse o gun
    // icinde atilan adimlar silinirdi.
    _todaySteps = _history[_date] ?? _savedToday;
  }

  Future<void> start() async {
    if (!isMobile) {
      _startDemo();
      return;
    }
    if (_starting) return;
    _starting = true;
    try {
      await _start();
    } finally {
      _starting = false;
    }
  }

  Future<void> _start() async {
    // Widget, sensorden bagimsiz calisabilmeli.
    WidgetService.enabled = true;
    _lastError = null;
    _permissionLabel = 'sorgulaniyor';
    notifyListeners();

    try {
      var status = await Permission.activityRecognition.status;
      _permissionLabel = status.name;

      if (!status.isGranted) {
        status = await Permission.activityRecognition.request();
        _permissionLabel = status.name;
      }

      if (status.isPermanentlyDenied || status.isRestricted) {
        // Ayarlar kendiliginden acilmaz (her acilista aciliyordu); Bugun
        // sayfasindaki izin bandinda "Ayarlar" dugmesi var.
        _permissionLabel = 'Kalıcı Red - Ayarlardan Açın';
        _state = SensorState.denied;
        notifyListeners();
        return;
      }

      if (!status.isGranted) {
        _state = SensorState.denied;
        notifyListeners();
        return;
      }

      final token = ++_startToken;

      await _counterSub?.cancel();
      await _stepSub?.cancel();
      _counterSub = null;
      _stepSub = null;

      // Servis durumu erkenden okunur: _syncFromBackground ve tanilama
      // satiri bunu kullaniyor. Taban karari artik servis durumuna bagli
      // degil (bkz. _restore / _checkDayRollover).
      await ForegroundService.syncRunningState();

      _state = SensorState.running;
      refreshWidget(force: true);

      // Sayim hemen baslasin: servis denemesi saniyeler surebiliyor.
      _listenCounter();
      notifyListeners();

      // Arka plan servisi sessizce baslatilir. Arayuz kendi sayimini
      // surdurur; servis yalnizca uygulama kapaliyken (ozellikle gece
      // yarisi gecisinde) kayit tutar ve acilista birlestirilir.
      unawaited(_ensureService(token));
      unawaited(_ensureNotificationPermission());
    } catch (e, s) {
      _state = SensorState.unavailable;
      _lastError = '$e';
      debugPrint('StepProvider.start hatasi: $e\n$s');
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    if (!isMobile) return;
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('Ayarlar acilamadi: $e');
    }
  }

  /// Arayuz gelistirme icin sahte veri: 30 gunluk gecmis + canli artan adim.
  void _startDemo() {
    _demoTimer?.cancel();

    if (_history.isEmpty) {
      final now = DateTime.now();
      for (var i = 1; i <= 400; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: i));
        if (i % 11 == 0) continue; // arada kayitsiz gunler
        _history[Metrics.dayKey(d)] = 2800 + (i * 1373) % 8200;
      }
    }

    if (_todaySteps == 0) _todaySteps = 5240;
    _history[_date] = _todaySteps;

    _walkStatus = 'Demo modu';
    _state = SensorState.demo;
    notifyListeners();

    _demoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _todaySteps += 17;
      _history[_date] = _todaySteps;
      notifyListeners();
    });
  }

  /// Dakikada bir: servis calisiyorsa kayitlarini arayuze tasi.
  Future<void> _syncFromBackground() async {
    if (!ForegroundService.running) return;
    await syncFromService();
  }

  /// Once gecikmesiz donanim kanali; calismazsa pedometer eklentisine
  /// dusulur (o da toplu raporlama yapar ama sayim durmaz).
  void _listenCounter() {
    if (!StepSensorService.supported) {
      _listenPedometer();
      return;
    }
    _counterSub = StepSensorService.counterStream.listen(
      _onCounter,
      onError: (e) {
        debugPrint('Hizli sayac kanali: $e');
        _counterSub?.cancel();
        _counterSub = null;
        _listenPedometer();
      },
      cancelOnError: true,
    );
  }

  /// Android 13+ bildirim izni.
  ///
  /// "Hedef tamamlandi" bildirimi varsayilan olarak acik, ama POST_NOTIFICATIONS
  /// izni yalnizca Ayarlar'daki anahtara dokunulunca isteniyordu; kullanici
  /// Ayarlar'a hic girmezse bildirim sessizce hic gelmiyordu. Ilk sensor
  /// baslatmada bir kez istenir.
  Future<void> _ensureNotificationPermission() async {
    try {
      if (prefs.notificationAsked) return;
      if (!prefs.notifyGoal && !prefs.notifyEvening && !prefs.notifyWeekly) {
        return;
      }
      // Once bayrak yazilir: istek iptal edilse de her acilista sorulmasin.
      await prefs.setNotificationAsked(true);
      await NotificationService.requestPermission();
    } catch (e) {
      debugPrint('Bildirim izni istenemedi: $e');
    }
  }

  /// Servisi ayakta tutar ve kayitlarini arayuzle birlestirir.
  Future<void> _ensureService(int token) async {
    try {
      await ForegroundService.syncRunningState();
      if (!ForegroundService.running) {
        await ForegroundService.start(
          goal: prefs.goal,
          heightCm: prefs.heightCm,
          weightKg: prefs.weightKg,
        );
      }
      if (token != _startToken) return;
      await syncFromService();
    } catch (e) {
      debugPrint('Arka plan servisi: $e');
    }
  }

  /// Servisin uygulama kapaliyken tuttugu kayitlari birlestirir.
  /// Gun basina buyuk olan deger kazanir; boylece gece yarisini servis
  /// yakalamissa dogru bolunmus degerler arayuze gecer.
  Future<void> syncFromService() async {
    // Once gun kontrolu: _date bayatsa importHistory bugunun degerini
    // dunun satirina yazardi.
    _checkDayRollover();
    final snap = await ForegroundService.pull();
    if (snap == null || snap.history.isEmpty) return;
    await importHistory(
      withoutOverrides(snap.history),
      hourly: hourlyWithoutOverrides(snap.hourly),
      intensity: hourlyWithoutOverrides(snap.intensity),
    );
  }

  /// Hizli kanal yoksa eklentinin akisina dusulur.
  void _listenPedometer() {
    _stepSub = Pedometer.stepCountStream.listen(
      (e) => _onCounter(e.steps),
      onError: (e) {
        _state = SensorState.unavailable;
        _lastError = 'Adim akisi: $e';
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  /// Kumulatif donanim sayaci. Tek dogru kaynak budur; arayuz ayri bir
  /// tahmin yurutmez, bu sayede ekranda gorunen deger her zaman diske
  /// yazilan degerdir.
  void _onCounter(int raw) {
    _eventCount++;
    _lastRawSensor = raw;
    final today = Metrics.dayKey(DateTime.now());

    var dayChanged = false;
    if (today != _date) {
      _history[_date] = _todaySteps;
      _date = today;
      // Servis gece yarisini yakalamissa bugunun degeri kayitta olabilir.
      _todaySteps = _history[today] ?? 0;
      _savedToday = _todaySteps;
      _baseline = raw;
      dayChanged = true;
    }

    // Ilk calisma veya cihaz yeniden baslatildi (sayac sifirlandi).
    if (_baseline < 0 || raw < _baseline) {
      _savedToday = _todaySteps;
      _baseline = raw;
    }

    final previous = _todaySteps;
    var computed = _savedToday + (raw - _baseline);

    // Uygulama gunlerce acilmamissa tum fark bugune yazilmamali.
    if (computed - previous > _maxCatchUp) {
      _savedToday = previous;
      _baseline = raw;
      computed = previous;
    }

    // Gunluk deger geri gidemez. Servis/bulut birlesmesi daha buyuk bir
    // deger benimsetmisse taban o degere cakilir, aksi halde ekrandaki
    // sayi bir sonraki olayda dusuyordu.
    if (computed < previous) {
      _savedToday = previous;
      _baseline = raw;
      computed = previous;
    }
    _todaySteps = computed;
    _history[_date] = _todaySteps;

    // Saatlik dagilim (adim hesabini etkilemez):
    //  - Servis calisiyorsa saatlik kaydi o tutar: her olayi gercek olcum
    //    saatine yazar ve syncFromService ile gelir.
    //  - Buyuk tek seferlik artislar arka planda birikmis adimlardir; acilis
    //    saatine yigilmasin diye saatlik kayda yazilmaz.
    final delta = _todaySteps - previous;
    if (delta > 0 &&
        delta <= _maxLiveHourlyDelta) {
      _addHourly(delta);
    }

    // Tempo: servis calisiyorsa dakikalari o siniflandirir. Servis kapaliysa
    // (arka plan izni yok / kapatildi) uygulama acikken burada yapilir;
    // yoksa tum adimlar "normal" sayiliyordu.
    if (delta > 0 && !ForegroundService.running) _tempoAdd(delta);

    if (delta > 0) {
      _walkStatus = 'Yürüyor';
      _idleTimer?.cancel();
      _idleTimer = Timer(const Duration(seconds: 6), () {
        _walkStatus = 'Duruyor';
        notifyListeners();
      });
    }

    // Her adimda diske yazmamak icin gecikmeli kayit; gun degisiminde
    // ve uygulama arka plana alinirken hemen yazilir.
    if (dayChanged) {
      _persist();
    } else {
      _persistSoon();
    }

    refreshWidget(force: dayChanged);
    _syncServiceToday(force: dayChanged);
    _maybeNotifyGoal();
    _maybeCelebrate();
    notifyListeners();
  }

  /// En fazla 5 saniyede bir diske yazar.
  void _persistSoon() {
    _persistTimer ??= Timer(const Duration(seconds: 5), () {
      _persistTimer = null;
      _persist();
    });
  }

  /// Uygulama arka plana alinirken bekleyen kaydi hemen yazar.
  Future<void> flushPersist() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persist();
  }

  void _addHourly(int delta) {
    final hour = DateTime.now().hour;
    var list = _hourly[_date];
    // Diskten/buluttan bozuk uzunlukta liste gelmis olabilir.
    if (list == null || list.length != 24) list = List<int>.filled(24, 0);
    list[hour] = list[hour] + delta;
    _hourly[_date] = list;
    _trimHourly();
  }

  // ------------------------------------------------------------------
  // Uygulama icinde tempo siniflandirma (yalnizca servis kapaliyken).
  // StepService.kt ile ayni kurallar: tamamlanan her dakikanin adim sayisi
  // kadanstir; 30 alti sayilmaz, 100-139 tempolu, 140+ kosu; tek olayda
  // 40'tan buyuk artis (toplu teslim) o dakikayi guvenilmez yapar.
  // ------------------------------------------------------------------
  int _tMinute = -1;
  String _tDay = '';
  int _tSteps = 0;
  bool _tTainted = false;

  void _tempoAdd(int delta) {
    final now = DateTime.now();
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    if (minute != _tMinute) {
      if (_tMinute >= 0 && minute < _tMinute) return;
      _tempoClose();
      _tMinute = minute;
      _tDay = Metrics.dayKey(now);
      _tSteps = 0;
      _tTainted = false;
    }
    _tSteps += delta;
    if (delta > 40) _tTainted = true;
  }

  void _tempoCloseIfEnded() {
    if (_tMinute < 0) return;
    if (DateTime.now().millisecondsSinceEpoch ~/ 60000 > _tMinute) {
      _tempoClose();
    }
  }

  void _tempoClose() {
    final steps = _tSteps;
    final day = _tDay;
    final tainted = _tTainted;
    _tMinute = -1;
    _tDay = '';
    _tSteps = 0;
    _tTainted = false;
    if (tainted || day.isEmpty || steps < 30 || steps > 230) return;
    final current = _intensity[day];
    final arr = current != null && current.length == Intensity.length
        ? List<int>.from(current)
        : List<int>.filled(Intensity.length, 0);
    if (steps >= Intensity.runMinCadence) {
      arr[Intensity.runSteps] += steps;
      arr[Intensity.runMin] += 1;
    } else if (steps >= Intensity.briskMinCadence) {
      arr[Intensity.briskSteps] += steps;
      arr[Intensity.briskMin] += 1;
    } else {
      arr[Intensity.walkMin] += 1;
    }
    _intensity[day] = arr;
    _trimIntensity();
  }

  /// Tempo kaydi gecmisle ayni sinirda tutulur (servis: 800 gun).
  void _trimIntensity() {
    const keep = 800;
    if (_intensity.length <= keep) return;
    final keys = _intensity.keys.toList()..sort();
    for (final k in keys.take(_intensity.length - keep)) {
      _intensity.remove(k);
    }
  }

  // ------------------------------------------------------------------
  // Tempo kirilimi (normal / tempolu / kosu)
  // ------------------------------------------------------------------

  /// Tarih araligi icin kirilim. Toplam adim gecmisten gelir; tempolu ve
  /// kosu adimlari her gun o gunun toplamina kirpilir (elle duzeltilen veya
  /// farkli cihazdan birlesen gunlerde toplam asilmasin).
  ActivityBreakdown breakdownBetween(DateTime from, DateTime to) =>
      _breakdown(from, to, activeMinutesBetween(from, to));

  /// Tek gun; Bugun karti ile ayni sure kaynagi ([activeMinutesFor]).
  ActivityBreakdown breakdownForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _breakdown(d, d, activeMinutesFor(d));
  }

  /// Tum kayitlar.
  ActivityBreakdown get breakdownAllTime {
    DateTime? first;
    DateTime? last;
    _history.forEach((k, v) {
      if (v <= 0) return;
      final d = Metrics.tryParseKey(k);
      if (d == null) return;
      if (first == null || d.isBefore(first!)) first = d;
      if (last == null || d.isAfter(last!)) last = d;
    });
    if (first == null || last == null) {
      return _breakdown(DateTime(2000), DateTime(2000), null);
    }
    return breakdownBetween(first!, last!);
  }

  ActivityBreakdown _breakdown(DateTime from, DateTime to, int? activeMin) {
    var total = 0;
    var bS = 0, bM = 0, rS = 0, rM = 0;
    var has = false;
    _history.forEach((k, v) {
      if (v <= 0) return;
      final d = Metrics.tryParseKey(k);
      if (d == null || d.isBefore(from) || d.isAfter(to)) return;
      total += v;
      final a = _intensity[k];
      if (a == null || a.length != Intensity.length) return;
      has = true;
      final run = a[Intensity.runSteps].clamp(0, v);
      final brisk = a[Intensity.briskSteps].clamp(0, v - run);
      rS += run;
      bS += brisk;
      if (run > 0) rM += a[Intensity.runMin];
      if (brisk > 0) bM += a[Intensity.briskMin];
    });
    return ActivityBreakdown.compute(
      totalSteps: total,
      briskSteps: bS,
      briskMin: bM,
      runSteps: rS,
      runMin: rM,
      hasData: has,
      heightCm: prefs.heightCm,
      weightKg: prefs.weightKg,
      activeMin: activeMin,
    );
  }

  /// Sadece son [_hourlyKeepDays] gunun saatlik kaydi tutulur.
  void _trimHourly() {
    if (_hourly.length <= _hourlyKeepDays) return;
    final keys = _hourly.keys.toList()..sort();
    for (final k in keys.take(_hourly.length - _hourlyKeepDays)) {
      _hourly.remove(k);
    }
  }

  String _goalNotifiedFor = '';

  /// Hedefe ulasildigi an artar (gunde bir kez); RootScreen kutlama gosterir.
  final goalReached = ValueNotifier<int>(0);
  String _celebratedFor = '';

  void _maybeCelebrate() {
    if (prefs.goal <= 0 || _todaySteps < prefs.goal) return;
    if (_celebratedFor == _date || prefs.goalCelebratedOn == _date) return;
    _celebratedFor = _date;
    prefs.setGoalCelebratedOn(_date);
    goalReached.value++;
  }

  void _maybeNotifyGoal() {
    if (!prefs.notifyGoal) return;
    if (prefs.goal <= 0 || _todaySteps < prefs.goal) return;
    if (_goalNotifiedFor == _date || prefs.goalNotifiedOn == _date) return;
    // Bellekte de isaretlenir; prefs yazimi beklenirken ikinci olay
    // gelirse tekrar bildirim gonderilmesin.
    _goalNotifiedFor = _date;
    prefs.setGoalNotifiedOn(_date);
    NotificationService.showGoalReached(_todaySteps);
  }

  /// Ana ekran widget'ini gunceller (Android disinda etkisiz).
  Future<void> refreshWidget({bool force = false}) {
    // Web/masaustunde home_widget eklentisi yok; force ile cagrilirsa
    // her seferinde MissingPluginException uretir.
    if (!isMobile) return Future.value();
    WidgetService.enabled = true;
    // Yenileme araligi dolmadiysa haftalik seriyi ve gecmis kopyasini
    // bosuna hazirlamayalim; bu metot her adimda cagrilabiliyor.
    if (!WidgetService.canUpdate(force: force)) return Future.value();
    // Bugun karti ile ayni kaynak: tempo kirilimli km / kcal / sure.
    final bd = breakdownForDay(DateTime.now());
    return WidgetService.update(
      // Anlik katki dahil: widget ile ekran ayni sayiyi gosterir.
      // Guncelleme WidgetService.minGap ile sinirlidir.
      steps: _todaySteps,
      km: bd.km,
      kcal: bd.kcal,
      minutes: bd.minutes,
      week: currentWeek().map((e) => e.value).toList(),
      goal: prefs.goal,
      waterMl: prefs.waterEnabled
          ? prefs.water[Metrics.dayKey(DateTime.now())] ?? 0
          : null,
      force: force,
    );
  }

  void _checkDayRollover() {
    final today = Metrics.dayKey(DateTime.now());
    if (today == _date) return;

    // Gun gecisi servis calissa da calismasa da arayuzde yapilmali:
    // eskiden servis acikken buradan cikiliyordu ve gece yarisindan sonra
    // ilk adim olayina kadar ekran dunun sayisini gosteriyordu; dahasi
    // importHistory bayat _date uzerinden dunun satirini tekrar yaziyordu.
    _history[_date] = _todaySteps;
    _date = today;
    // Servis gece yarisini yakalamissa bugunun degeri zaten kayittadir.
    _todaySteps = _history[today] ?? 0;
    _savedToday = _todaySteps;
    // Taban her zaman sifirlanir: korunursa DUNUN TAMAMI bugune devreder
    // (ayrinti icin _restore icindeki acikama). Servis calisiyorsa gece
    // yarisi civarindaki adimlar onun kaydindan importHistory ile gelir.
    _baseline = -1;
    _persist();
    // Gece yarisi gecisinde widget ve kalici bildirim dunun degerinde
    // kalmasin diye zorla yenilenir.
    refreshAll(force: true);
    notifyListeners();
  }

  /// Widget ve kalici bildirimi birlikte yeniler.
  /// Hedef, boy veya kilo degistiginde de cagrilmalidir.
  Future<void> refreshAll({bool force = false}) async {
    // Hedef degismis olabilir; kalici bildirim eski hedefte kalmasin.
    await ForegroundService.updateGoal(
      prefs.goal,
      heightCm: prefs.heightCm,
      weightKg: prefs.weightKg,
    );
    await refreshWidget(force: force);
    _syncServiceToday(force: true);
    notifyListeners();
  }

  /// Uygulama one geldiginde: native servisin diske yazdigi degerleri
  /// tazele, gunu kontrol et, servisin kayitlarini al.
  Future<void> onResume() async {
    try {
      // Native servis ayni SharedPreferences dosyasina yaziyor; bellekteki
      // kopya tazelenmezse arayuz eski degerleri okur.
      await prefs.reload();
    } catch (e) {
      debugPrint('Prefs tazelenemedi: $e');
    }
    await ForegroundService.syncRunningState();
    await syncFromService();
    _syncServiceToday(force: true);
  }

  Future<void> _persist() async {
    _tempoCloseIfEnded();
    await prefs.saveCounterState(
      savedToday: _savedToday,
      baseline: _baseline,
      date: _date,
    );
    await prefs.setHistory(_history);
    await prefs.setHourly(_hourly);
    await prefs.setIntensity(_intensity);
    
    _checkAchievements();
    
    // Adim olaylari sik geldigi icin bulut yazmasi kuyruga alinir.
    pushToCloud();
  }

  /// Yeni acilan rozetleri kaydeder; en son acilan Bugun sayfasinda
  /// "Son kazanilan rozet" olarak gosterilir.
  ///
  /// Rozetler basliga gore degil [Achievements.idOf] ile tutulur: ayni
  /// baslik ("7 GUN", "100B") birden fazla kategoride var.
  void _checkAchievements() {
    if (_history.isEmpty) return;
    final all = breakdownAllTime;
    final stats = AchievementStats.from(
      history: _history,
      goal: prefs.goal,
      heightCm: prefs.heightCm,
      totalKcal: all.kcal,
      totalKm: all.km,
    );

    final unlockedItems = Achievements.evaluate(stats)
        .where((p) => p.unlocked)
        .map((p) => p.item)
        .toList();
    final unlocked = unlockedItems.map(Achievements.idOf).toList();
    final previously = prefs.unlockedBadges;

    // Ilk calisma (ya da eski surumun baslik tabanli kaydi): daha once
    // kazanilmis rozetlerin hepsi "yeni" sayilmasin. Hepsi sessizce
    // kaydedilir; "son rozet" olarak kategorisinde en ileri basamakta
    // olan secilir (ornegin 5 mesafe rozetinin 4.'su, 2 seri rozetinin
    // 1.'inden daha ileri sayilir).
    final firstRun =
        previously.isEmpty || !previously.any((id) => id.contains(':'));
    if (firstRun) {
      if (unlocked.isEmpty) return;
      prefs.setUnlockedBadges(unlocked.toSet());
      if (prefs.lastBadge.isEmpty) {
        prefs.setLastBadge(Achievements.idOf(_mostAdvanced(unlockedItems)));
      }
      return;
    }

    final newly = unlocked.where((id) => !previously.contains(id)).toList();
    if (newly.isEmpty) return;

    prefs.setUnlockedBadges(unlocked.toSet());
    // Ayni anda birden fazla acildiysa listedeki son (kategorisinin en
    // buyuk esigi) en son kazanilan sayilir.
    prefs.setLastBadge(newly.last);
  }

  /// Kategorisindeki basamak orani en yuksek rozet (esitlikte ilk gelen).
  static Achievement _mostAdvanced(List<Achievement> items) {
    Achievement best = items.first;
    var bestRatio = -1.0;
    for (final a in items) {
      final same = Achievements.all.where((x) => x.kind == a.kind).toList();
      final ratio = (same.indexOf(a) + 1) / same.length;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = a;
      }
    }
    return best;
  }

  /// Bugun sayfasindaki "Son kazanilan rozet" icin kayitli kimlik.
  String get lastBadgeId => prefs.lastBadge;

  // ------------------------------------------------------------------
  // Bildirim / widget senkronu
  // ------------------------------------------------------------------

  DateTime _lastServiceSync = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastServiceSynced = -1;

  /// Uygulamadaki bugunku degeri native servise bildirir. Servis kendi
  /// sayacindan kucukse bu degeri benimser; kalici bildirim ve widget
  /// uygulamayla ayni sayiyi gosterir. Adim algoritmasi degismez: servis,
  /// Dart'in [importHistory]'de yaptigi gibi taban degerini bir sonraki
  /// sensor olayina cakar.
  void _syncServiceToday({bool force = false}) {
    if (!ForegroundService.running) return;
    final now = DateTime.now();
    if (!force &&
        (_todaySteps == _lastServiceSynced ||
            now.difference(_lastServiceSync) < const Duration(seconds: 3))) {
      return;
    }
    _lastServiceSync = now;
    _lastServiceSynced = _todaySteps;
    ForegroundService.syncToday(_date, _todaySteps);
  }

  /// Tum kayitlarin toplami.
  int get totalSteps => history.values.fold<int>(0, (a, b) => a + b);

  int get currentStreak => Aggregate.currentStreak(history, prefs.goal);

  int get bestStreak => Aggregate.bestStreak(history, prefs.goal);

  int get bestDaySteps =>
      history.isEmpty ? 0 : history.values.reduce((a, b) => a > b ? a : b);

  /// Kayit bulunan gun sayisi.
  int get recordedDays => history.values.where((v) => v > 0).length;

  /// Icinde bulunulan hafta (Pazartesi -> Pazar).
  List<MapEntry<DateTime, int>> currentWeek() {
    final start = Metrics.weekStart(DateTime.now());
    final live = history;
    return List.generate(7, (i) {
      final d = start.add(Duration(days: i));
      return MapEntry(d, live[Metrics.dayKey(d)] ?? 0);
    });
  }

  int get thisWeekSteps {
    final start = Metrics.weekStart(DateTime.now());
    return Aggregate.totalBetween(
      history,
      start,
      start.add(const Duration(days: 6)),
    );
  }

  /// Son [days] gun icin tarih -> adim listesi (eskiden yeniye).
  List<MapEntry<DateTime, int>> lastDays(int days) {
    final now = DateTime.now();
    final live = history;
    return List.generate(days, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
      return MapEntry(d, live[Metrics.dayKey(d)] ?? 0);
    });
  }

  /// Yedekten gelen gecmisi birlestirir: ayni gunde buyuk olan deger kalir.
  /// [replace] true ise mevcut gecmis tamamen silinip yedek yazilir.
  Future<int> importHistory(
    Map<String, int> incoming, {
    bool replace = false,
    Map<String, List<int>>? hourly,
    Map<String, List<int>>? intensity,
  }) async {
    if (replace) {
      _history = Map<String, int>.from(incoming);
      // Gecmis tamamen degistiginde eski saatlik kayit artik bu gecmise ait
      // degil; birakilirsa kapsama hesabi yanlis calisirdi.
      _hourly = <String, List<int>>{};
      _intensity = <String, List<int>>{};
    } else {
      incoming.forEach((k, v) {
        final current = _history[k] ?? 0;
        if (v > current) _history[k] = v;
      });
    }

    if (hourly != null && hourly.isNotEmpty) {
      // Eskiden yalnizca "yerelde hic yoksa" yaziliyordu; bugunun anahtari
      // her zaman yerelde oldugu icin buluttaki saatlik veri hic
      // birlesmiyordu. Artik gun toplami buyuk olan taraf kazanir.
      hourly.forEach((k, v) {
        if (v.length != 24 || !Metrics.isValidKey(k)) return;
        final current = _hourly[k];
        if (current == null || current.length != 24) {
          _hourly[k] = List<int>.from(v);
          return;
        }
        final currentTotal = current.fold<int>(0, (a, b) => a + b);
        final incomingTotal = v.fold<int>(0, (a, b) => a + b);
        if (incomingTotal > currentTotal) _hourly[k] = List<int>.from(v);
      });
      _trimHourly();
    }

    if (intensity != null && intensity.isNotEmpty) {
      intensity.forEach((k, v) {
        if (v.length != Intensity.length || !Metrics.isValidKey(k)) return;
        final current = _intensity[k];
        _intensity[k] = current == null || current.length != Intensity.length
            ? List<int>.from(v)
            : Intensity.mergeMax(current, v);
      });
      _trimIntensity();
    }

    // Bugunun degeri buyuduyse benimsenir ve sayac tabani yeniden cakilir.
    //
    // KRITIK: burada eskiden `_savedToday += fark` yapiliyordu. Donanim
    // sayaci kumulatif oldugu icin `raw - _baseline` o farki ZATEN
    // iceriyordu; ayni adimlar bir kez de _savedToday'e eklenince her
    // birlestirmede cift sayim olusuyordu. _baseline = -1 birakilinca bir
    // sonraki sayac olayi tabani o ana cakiyor ve toplam dogru kaliyor.
    final todayValue = _history[_date] ?? 0;
    if (todayValue > _todaySteps) {
      _todaySteps = todayValue;
      _savedToday = todayValue;
      _baseline = -1;
    } else {
      _history[_date] = _todaySteps;
    }

    await _persist();
    _syncServiceToday(force: true);
    notifyListeners();
    return incoming.length;
  }

  /// Elle duzeltilen gunleri disarida birakir (servis/bulut birlestirmesi).
  Map<String, int> withoutOverrides(Map<String, int> incoming) {
    if (_overridden.isEmpty) return incoming;
    return Map<String, int>.fromEntries(
      incoming.entries.where((e) => !_overridden.contains(e.key)),
    );
  }

  Map<String, List<int>> hourlyWithoutOverrides(
    Map<String, List<int>> incoming,
  ) {
    if (_overridden.isEmpty) return incoming;
    return Map<String, List<int>>.fromEntries(
      incoming.entries.where((e) => !_overridden.contains(e.key)),
    );
  }

  /// Gecmis bir gunun degerini elle duzeltir.
  ///
  /// "Buyuk olan kazanir" birlestirmesi yuzunden hatali bir deger normal
  /// yoldan dusurulemiyordu. Deger dogrudan yazilir, gun korumaya alinir
  /// (servis ve buluttan gelen degerler artik bu gunu degistirmez) ve
  /// buluttaki kopya da guncellenir. Bugun ve gelecek gunler duzenlenemez:
  /// bugunun degeri canli sayactan gelir.
  Future<bool> overrideDay(DateTime day, int steps) async {
    final key = Metrics.dayKey(day);
    if (key.compareTo(_date) >= 0) return false;
    final value = steps.clamp(0, 200000);
    _history[key] = value;
    // Saatlik kayit artik bu degerle uyusmaz; silinir, sure tahmine duser.
    _hourly.remove(key);
    _intensity.remove(key);
    _overridden = {..._overridden, key};
    await prefs.setOverriddenDays(_overridden);
    await _persist();
    await _cloud?.setDay(key, value);
    await refreshWidget(force: true);
    notifyListeners();
    return true;
  }

  BackupData buildBackup() => BackupData(
        goal: prefs.goal,
        heightCm: prefs.heightCm,
        weightKg: prefs.weightKg,
        history: Map<String, int>.from(_history),
        hourly: _hourly.map((k, v) => MapEntry(k, List<int>.from(v))),
      );

  Future<void> resetData() async {
    await prefs.clearAll();
    _history = {};
    _hourly = {};
    _intensity = {};
    _savedToday = 0;
    _todaySteps = 0;
    _baseline = -1;
    _date = Metrics.dayKey(DateTime.now());
    // prefs.clearAll() goalNotifiedOn'u siliyor; bellekteki isaret de
    // temizlenmezse bugun hedef bildirimi bir daha gonderilmez.
    _goalNotifiedFor = '';
    _overridden = {};
    // Buluttaki kopya da bosaltilir, aksi halde ilk senkronda geri gelir.
    // Servisin kendi kopyasi ve buluttaki yil dokumanlari da silinir;
    // yoksa sonraki acilista/giriste veriler geri gelir.
    await ForegroundService.clear();
    await _cloud?.clearRemote();
    // Rota kayitlari da silinir: cihazdaki gunluk dosyalar ve buluttaki
    // users/{uid}/routes dokumanlari (yoksa bir sonraki acilista geri gelir).
    await RouteService.clear();
    await RouteService.clearCloud();
    // Widget ve kalici bildirim eski degerde kalmasin.
    await refreshAll(force: true);
    notifyListeners();
  }

  /// dispose() sonrasi gec gelen timer/stream/async geri cagrilari
  /// "used after disposed" istisnasi atmasin.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _counterSub?.cancel();
    _stepSub?.cancel();
    _dayTimer?.cancel();
    _demoTimer?.cancel();
    _idleTimer?.cancel();
    _persistTimer?.cancel();
    super.dispose();
  }
}
