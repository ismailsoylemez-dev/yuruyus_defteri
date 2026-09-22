package com.ismail.adim_sayar

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.Calendar
import java.util.Locale

/**
 * Adim sayimini uygulama kapaliyken de surduren native foreground service.
 *
 * Neden eklenti yerine kendi servisimiz:
 * flutter_foreground_task, servisin icinde ikinci bir Dart isolate baslatip
 * onunla el sikismayi bekler. Bazi cihazlarda (MIUI/HyperOS, agresif pil
 * yonetimi) bu isolate hic ayaga kalkmaz ve eklenti ServiceTimeoutException
 * atar. Burada Dart yok: dogrudan SensorManager dinlenir, veriler kendi
 * SharedPreferences dosyamiza yazilir. Baslatilacak bir isolate olmadigi icin
 * beklenecek bir cevap da yoktur.
 *
 * Servisin isleri:
 *  - gunun toplamini ve gecmisi kaydetmek, gece yarisi gecisini kacirmamak,
 *  - saatlik dagilimi olcum anina gore tutmak (uygulama kapaliyken de),
 *  - uygulama kapaliyken ana ekran widget'ini guncel tutmak,
 *  - acikken rota kaydini yurutmek (RouteTracker; GPS'i adimlar acar/kapatir).
 * Arayuz kendi sayimini surdurur; acildiginda buradaki kayitlarla birlestirir.
 */
class StepService : Service(), SensorEventListener {

    companion object {
        const val PREFS = "adim_sayar_bg"
        const val K_TODAY = "todaySteps"
        const val K_SAVED = "savedToday"
        const val K_BASELINE = "baseline"
        const val K_DATE = "date"
        const val K_HISTORY = "history"
        const val K_HOURLY = "hourly"
        const val K_INTENSITY = "intensity"
        const val K_GOAL = "goal"
        const val K_HEIGHT = "heightCm"
        const val K_WEIGHT = "weightKg"
        /** GPS ile olculen adim boyu (m); yoksa -1 (boydan tahmin). */
        const val K_STRIDE = "strideM"
        const val K_ENABLED = "enabled"
        const val ACTION_MIDNIGHT = "com.ismail.adim_sayar.MIDNIGHT"
        const val ACTION_EVENING = "com.ismail.adim_sayar.EVENING"
        const val ACTION_WEEKLY = "com.ismail.adim_sayar.WEEKLY"
        private const val WEEKLY_NOTIF_ID = 1003

        /** Flutter tarafinin SharedPreferences dosyasindaki bool (flutter. onekli). */
        fun flutterBool(c: Context, key: String, def: Boolean): Boolean =
            try {
                c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getBoolean("flutter.$key", def)
            } catch (e: Exception) {
                def
            }

        /** Su takibi acik mi (Ayarlar > Su takibi). Kapaliyken su her yerden gizlenir. */
        fun waterEnabled(c: Context): Boolean = flutterBool(c, "water_enabled", true)

        /** Aksam hatirlatmasi: Flutter'daki NotificationService ile ayni kanal ve kimlik. */
        private const val REMINDER_CHANNEL_ID = "adim_sayar_reminders"
        private const val EVENING_NOTIF_ID = 1002
        private const val EVENING_HOUR = 20

        private const val CHANNEL_ID = "adim_sayar_service"
        private const val NOTIF_ID = 4711
        private const val HISTORY_LIMIT = 800
        private const val HOURLY_LIMIT = 365

        /** Olagan artislar diske en fazla bu aralikla yazilir. */
        private const val PERSIST_INTERVAL_MS = 30_000L

        /** Uygulama kapaliyken widget en fazla bu aralikla yeniden cizilir. */
        private const val WIDGET_INTERVAL_MS = 60_000L

        /** Tek olayda saatlik kayda yazilabilecek en fazla artis. */
        private const val MAX_HOURLY_DELTA = 20_000

        // ---- Tempo siniflandirmasi (adim sayimindan bagimsiz) ----
        // Her tamamlanan takvim dakikasinin adim sayisi = kadans (adim/dk).
        // CADENCE-Adults (Tudor-Locke ve ark. 2019): ~100 adim/dk orta
        // (3 MET), ~130 adim/dk yuksek (6 MET) yogunluk esigi. 140+ adim/dk
        // yurume icin pek mumkun degil: kosu kabul edilir.
        /** Bu kadansin altindaki dakikalar yurume sayilmaz (dur-kalk). */
        private const val WALK_MIN_CADENCE = 30
        const val BRISK_MIN_CADENCE = Formulas.BRISK_MIN_CADENCE
        const val RUN_MIN_CADENCE = Formulas.RUN_MIN_CADENCE
        /** Bundan buyuk "dakika" toplu teslim artefaktidir: siniflandirilmaz. */
        private const val MAX_CADENCE = 230
        /**
         * Tek olayda bundan buyuk artis, adimlarin gecikmeli/toplu geldigini
         * gosterir (ornegin FIFO tasmasi). O dakikanin kadansi guvenilmez:
         * iki dakikalik tempolu yuruyus tek dakikaya yigilip kosu sanilmasin.
         */
        private const val MAX_EVENT_DELTA = 40

        // intensity[gun] = [normalDk, tempoluAdim, tempoluDk, kosuAdim, kosuDk]
        const val I_WALK_MIN = 0
        const val I_BRISK_STEPS = 1
        const val I_BRISK_MIN = 2
        const val I_RUN_STEPS = 3
        const val I_RUN_MIN = 4
        private const val I_LEN = 5

        /** home_widget eklentisinin resim yolunu tuttugu anahtar (WidgetService ile ayni). */
        private const val WIDGET_IMAGE_KEY = "stepWidgetImage"
        private const val WIDGET_FILE = "step_widget_native.png"

        /** Servis surecte ayakta mi. */
        @Volatile
        var running: Boolean = false
            private set

        /** Uygulama on planda mi (MainActivity yazar). On plandayken widget'i Flutter cizer. */
        @Volatile
        var appInForeground: Boolean = false

        /** Surecteki servis ornegi; MainActivity pull/clear/updateGoal icin kullanir. */
        @Volatile
        var instance: StepService? = null
            private set

        fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun dayKey(millis: Long = System.currentTimeMillis()): String {
            val c = Calendar.getInstance()
            c.timeInMillis = millis
            return String.format(
                Locale.US,
                "%04d-%02d-%02d",
                c.get(Calendar.YEAR),
                c.get(Calendar.MONTH) + 1,
                c.get(Calendar.DAY_OF_MONTH)
            )
        }
    }

    private var sensorManager: SensorManager? = null
    private var todaySteps = 0
    private var savedToday = 0
    private var baseline = -1L
    private var date = ""
    private var goal = 8000
    private var heightCm = 172
    private var weightKg = 93.0
    private var lastNotify = 0L
    private var lastPersist = 0L
    private var lastWidget = 0L

    /** Bellekte olup henuz diske yazilmamis degisiklik var mi. */
    private var dirty = false

    /** Widget son cizimden beri eskidi mi. */
    private var widgetDirty = false

    // Gecmis ve saatlik dagilim bellekte tutulur. Eskiden her adim olayinda
    // (yururken saniyede ~2) 800 gunluk JSON diskten okunup ayristiriliyor ve
    // tamami yeniden yaziliyordu.
    private var history = JSONObject()
    private var hourly = JSONObject()
    private var intensity = JSONObject()

    /** Acik dakika kovasi: epoch dakikasi, gunu ve icindeki adim. */
    private var minuteEpoch = -1L
    private var minuteDay = ""
    private var minuteSteps = 0
    private var minuteTainted = false

    private val handler = Handler(Looper.getMainLooper())

    /** Rota kaydi (GPS). Ayar kapaliysa hic konum istemez. */
    var route: RouteTracker? = null
        private set

    /** Son adimdan sonra: bekleyen kaydi yaz, widget'i son haline getir. */
    private val idleTick = Runnable {
        closeMinuteIfEnded()
        persist(force = true)
        if (widgetDirty) maybeRenderWidget(force = true)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val p = prefs(this)
        todaySteps = p.getInt(K_TODAY, 0)
        savedToday = p.getInt(K_SAVED, 0)
        baseline = p.getLong(K_BASELINE, -1L)
        date = p.getString(K_DATE, "") ?: ""
        goal = p.getInt(K_GOAL, 8000)
        heightCm = p.getInt(K_HEIGHT, 172)
        p.getFloat(K_STRIDE, -1f).let { Formulas.strideOverrideM = if (it > 0f) it.toDouble() else null }
        weightKg = p.getFloat(K_WEIGHT, 93f).toDouble()
        history = readJson(p, K_HISTORY)
        hourly = readJson(p, K_HOURLY)
        intensity = readJson(p, K_INTENSITY)

        val today = dayKey()
        if (date != today) {
            // Onceki gunun toplami kapatilir; baseline sifirlanir.
            if (date.isNotEmpty()) putHistory(date, todaySteps)
            date = today
            savedToday = 0
            todaySteps = 0
            baseline = -1L
            dirty = true
            persist(force = true)
        }

        instance = this
        createChannel()
        workout = WorkoutManager(this, { todaySteps }) { throttledNotify() }
        route = RouteTracker(
            this,
            onStateChanged = { notifyNow() },
            stepsNow = { todaySteps },
            onDistance = { d -> workout?.onDistance(d) }
        )
        startForegroundTyped()
        running = true
        scheduleMidnight()
        scheduleEvening()
        scheduleWeekly()

        val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sm == null || sensor == null) {
            stopSelf()
            return
        }
        sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL, 0)
        sensorManager = sm
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_MIDNIGHT) {
            onMidnight()
            return START_STICKY
        }
        if (intent?.action == ACTION_EVENING) {
            onEvening()
            return START_STICKY
        }
        if (intent?.action == ACTION_WEEKLY) {
            onWeekly()
            return START_STICKY
        }
        if (intent != null) {
            applyProfile(
                intent.getIntExtra("goal", -1),
                intent.getIntExtra("heightCm", -1),
                intent.getDoubleExtra("weightKg", -1.0)
            )
        }
        prefs(this).edit().putInt(K_GOAL, goal).putBoolean(K_ENABLED, true).apply()
        // Sistem sureci oldurursen servisi yeniden kur.
        return START_STICKY
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        val raw = event.values.firstOrNull()?.toLong() ?: return

        // ---- Adim algoritmasi (degistirilmedi) ----
        val today = dayKey()
        var reset = false
        if (today != date) {
            // Gece yarisi gecisi: bu servisin var olma sebebi.
            putHistory(date, todaySteps)
            date = today
            savedToday = 0
            todaySteps = 0
            baseline = raw
            reset = true
        }

        // Ilk calisma veya cihaz yeniden baslatildi (donanim sayaci sifirlandi).
        if (baseline < 0 || raw < baseline) {
            savedToday = todaySteps
            baseline = raw
            reset = true
        }

        val previous = todaySteps
        todaySteps = (savedToday + (raw - baseline)).toInt()
        // ---- algoritma sonu ----

        // Saatlik dagilim: yalnizca artis, olayin gercek olcum saatine yazilir.
        val delta = todaySteps - previous
        if (delta in 1..MAX_HOURLY_DELTA) {
            addHourly(date, hourOf(event), delta)
            addToMinute(eventMillis(event), delta)
            // Toplu/gecikmeli teslim edilen eski adimlar GPS'i acmasin.
            if (!reset && System.currentTimeMillis() - eventMillis(event) < 60_000L) {
                route?.onSteps(delta)
            }
        }
        putHistory(date, todaySteps)
        dirty = true
        widgetDirty = true

        // Taban/gun degisimi hemen, olagan artislar en fazla 30 sn'de bir diske.
        persist(force = reset)
        handler.removeCallbacks(idleTick)
        handler.postDelayed(idleTick, WIDGET_INTERVAL_MS)

        val now = System.currentTimeMillis()
        if (now - lastNotify > 30_000L) {
            lastNotify = now
            notificationManager()?.notify(NOTIF_ID, buildNotification())
        }
        maybeRenderWidget()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        sensorManager?.unregisterListener(this)
        workout?.shutdown()
        route?.shutdown()
        handler.removeCallbacks(idleTick)
        closeMinuteIfEnded()
        persist(force = true)
        try {
            (getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.cancel(midnightIntent())
            (getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.cancel(eveningIntent())
            (getSystemService(Context.ALARM_SERVICE) as? AlarmManager)?.cancel(weeklyIntent())
        } catch (e: Exception) {
        }
        running = false
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    // MainActivity tarafindan cagrilanlar
    // ------------------------------------------------------------------

    /** "pull" oncesi: bellekteki en guncel durumu diske yazar. */
    fun flushNow() {
        closeMinuteIfEnded()
        persist(force = true)
    }

    /**
     * "Tum kayitlari sil": bellekteki kopya da temizlenmeli. Eskiden yalnizca
     * diskteki anahtarlar siliniyordu; calisan servis bir sonraki adimda
     * bellekteki bugunku degeri geri yaziyordu.
     */
    fun resetState() {
        history = JSONObject()
        hourly = JSONObject()
        intensity = JSONObject()
        minuteEpoch = -1L
        minuteDay = ""
        minuteSteps = 0
        minuteTainted = false
        date = dayKey()
        savedToday = 0
        todaySteps = 0
        baseline = -1L
        dirty = true
        persist(force = true)
        notifyNow()
        widgetDirty = true
        maybeRenderWidget(force = true)
    }

    // ------------------------------------------------------------------
    // Yuruyus kaydi / aralikli yuruyus
    // ------------------------------------------------------------------

    var workout: WorkoutManager? = null
        private set

    private var lastWorkoutNotify = 0L

    /** Yuruyus sirasinda bildirim en fazla 5 sn'de bir guncellenir. */
    private fun throttledNotify() {
        val now = System.currentTimeMillis()
        if (now - lastWorkoutNotify < 4_500L) return
        lastWorkoutNotify = now
        notifyNow()
    }

    /** Uygulama on plandayken cagrilir (konum servis tipi eklenebilsin). */
    fun startWorkout(interval: Boolean, rounds: Int, fastSec: Int, slowSec: Int): Boolean {
        val w = workout ?: return false
        if (w.active) return true
        prefs(this).edit().putBoolean(RouteTracker.K_ROUTE_ENABLED, true).apply()
        onRouteSettingsChanged()
        w.start(interval, rounds, fastSec, slowSec)
        route?.setForced(true)
        notifyNow()
        return true
    }

    fun stopWorkout(): JSONObject? {
        val summary = workout?.stop()
        route?.setForced(false)
        route?.flush()
        notifyNow()
        return summary
    }

    /** GPS ile olculen adim boyu degisti (Flutter). */
    fun onStrideChanged() {
        notifyNow()
        widgetDirty = true
        maybeRenderWidget(force = true)
    }

    /** Widget'tan su eklendi ya da su ayari degisti. */
    fun onWaterChanged() {
        notifyNow()
        widgetDirty = true
        maybeRenderWidget(force = true)
    }

    /** Hedef/boy/kilo degisince bildirim ve widget hemen tazelenir. */
    fun applyProfile(newGoal: Int, newHeight: Int, newWeight: Double) {
        var changed = false
        if (newGoal > 0 && newGoal != goal) {
            goal = newGoal
            changed = true
        }
        if (newHeight > 0 && newHeight != heightCm) {
            heightCm = newHeight
            changed = true
        }
        if (newWeight > 0 && newWeight != weightKg) {
            weightKg = newWeight
            changed = true
        }
        prefs(this).edit()
            .putInt(K_GOAL, goal)
            .putInt(K_HEIGHT, heightCm)
            .putFloat(K_WEIGHT, weightKg.toFloat())
            .apply()
        if (changed) {
            notifyNow()
            widgetDirty = true
            maybeRenderWidget(force = true)
        }
    }

    /**
     * Uygulamadaki bugunku deger servisten buyukse benimsenir; kalici
     * bildirim ve widget uygulamayla ayni sayiyi gosterir.
     *
     * Adim algoritmasi degismez: Dart'taki importHistory ile ayni yontem.
     * todaySteps/savedToday yeni degere cekilir, baseline = -1 birakilir;
     * bir sonraki sensor olayinda "baseline < 0" dali tabani o ana cakar
     * ve sayim kaldigi yerden (yeni degerin ustune) devam eder.
     * Kucuk ya da baska gune ait deger yok sayilir (geri gitmez).
     *
     * GUVENLIK: Baska gune ait deger ile servisin gunu DEGISTIRILMEZ
     * (uygulamanin gunu gecikmeli olabilir; gece yarisindan sonra dunun
     * tarihi gelirse bugun dune yazilirdi). Kucuk deger de benimsenmez:
     * uygulama kapaliyken servisin saydigi adimlar silinmesin. Tum
     * kayitlari silme ayri yoldan (clear/resetState) yapilir.
     */
    fun adoptToday(day: String, steps: Int) {
        if (day != date) return
        if (steps > todaySteps) {
            todaySteps = steps
            savedToday = steps
            baseline = -1L
            putHistory(date, todaySteps)
            dirty = true
            persist(force = true)
            widgetDirty = true
            maybeRenderWidget()
        }
        // Su / hedef gibi uygulamada degisen bilgiler bildirime yansisin.
        notifyNow()
    }

    /**
     * Rota ayari ya da konum izni degisti (MainActivity, uygulama on plandayken).
     * Servis tipi yeniden bildirilir: izin geldiyse "location" eklenir.
     */
    fun onRouteSettingsChanged() {
        startForegroundTyped()
        route?.onSettingsChanged()
        notifyNow()
    }

    /** Konum tipi su an servise ekli mi (rota durum ekrani icin). */
    var locationTypeActive = false
        private set

    /**
     * Android 14+ (targetSdk 35): servis tipi izinlere gore secilir.
     * "location" tipi yalnizca konum izni varsa ve uygulama on plandaysa ya
     * da "Her zaman izin ver" verilmisse eklenebilir; aksi halde sistem
     * SecurityException atar (ornegin acilista BootReceiver'dan baslarken).
     * Bu durumda servis yalnizca "health" tipiyle surer; adim sayimi etkilenmez.
     */
    private fun startForegroundTyped() {
        val notification = buildNotification()
        val wantLocation = RouteTracker.isEnabled(this) &&
            RouteTracker.hasFine(this) &&
            (appInForeground || RouteTracker.hasBackground(this))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, notification)
            locationTypeActive = wantLocation
            return
        }
        val base = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH else 0
        if (wantLocation) {
            try {
                ServiceCompat.startForeground(
                    this, NOTIF_ID, notification,
                    base or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
                locationTypeActive = true
                return
            } catch (e: Exception) {
                // Izin/arka plan kisiti: konumsuz devam.
            }
        }
        ServiceCompat.startForeground(this, NOTIF_ID, notification, base)
        locationTypeActive = false
    }

    /** Uygulama arka plana gecti: Flutter widget'i az once cizdi, hemen ustune cizilmesin. */
    fun onAppBackground() {
        lastWidget = System.currentTimeMillis()
    }

    // ------------------------------------------------------------------
    // Kayit
    // ------------------------------------------------------------------

    private fun readJson(p: SharedPreferences, key: String): JSONObject =
        try {
            JSONObject(p.getString(key, "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }

    private fun putHistory(day: String, steps: Int) {
        if (day.isEmpty()) return
        history.put(day, steps)
        trimKeys(history, HISTORY_LIMIT)
    }

    private fun addHourly(day: String, hour: Int, delta: Int) {
        if (day.isEmpty() || hour !in 0..23) return
        val existing = hourly.optJSONArray(day)
        val arr = if (existing != null && existing.length() == 24) {
            existing
        } else {
            JSONArray().apply { repeat(24) { put(0) } }
        }
        arr.put(hour, arr.optInt(hour, 0) + delta)
        hourly.put(day, arr)
        trimKeys(hourly, HOURLY_LIMIT)
    }

    // ------------------------------------------------------------------
    // Tempo (normal / tempolu / kosu) - adim sayimini etkilemez
    // ------------------------------------------------------------------

    /** Artis, olcum anina ait takvim dakikasina eklenir. */
    private fun addToMinute(eventMs: Long, delta: Int) {
        val epoch = eventMs / 60_000L
        if (epoch != minuteEpoch) {
            // Siradan cikmis (daha eski) olay acik dakikayi bozmasin.
            if (minuteEpoch >= 0 && epoch < minuteEpoch) return
            closeMinute()
            minuteEpoch = epoch
            minuteDay = dayKey(eventMs)
            minuteSteps = 0
            minuteTainted = false
        }
        minuteSteps += delta
        if (delta > MAX_EVENT_DELTA) minuteTainted = true
    }

    /** Dakika bittiyse (duvar saati sonraki dakikada) kapatir. */
    private fun closeMinuteIfEnded() {
        if (minuteEpoch < 0) return
        if (System.currentTimeMillis() / 60_000L > minuteEpoch) closeMinute()
    }

    /**
     * Tamamlanan dakikayi kadansina gore siniflandirir. Yalnizca tempolu ve
     * kosu adimlari ayrica tutulur; normal adim = gunun toplami - ikisi.
     * Boylece siniflandirilamayan her adim normal sayilir ve toplamlar
     * gunluk adim sayisiyla her zaman tutarli kalir.
     */
    private fun closeMinute() {
        val steps = minuteSteps
        val day = minuteDay
        val tainted = minuteTainted
        minuteEpoch = -1L
        minuteSteps = 0
        minuteDay = ""
        minuteTainted = false
        if (tainted || day.isEmpty()) return
        if (steps < WALK_MIN_CADENCE || steps > MAX_CADENCE) return
        val existing = intensity.optJSONArray(day)
        val arr = if (existing != null && existing.length() == I_LEN) {
            existing
        } else {
            JSONArray().apply { repeat(I_LEN) { put(0) } }
        }
        fun add(i: Int, v: Int) = arr.put(i, arr.optInt(i, 0) + v)
        when {
            steps >= RUN_MIN_CADENCE -> { add(I_RUN_STEPS, steps); add(I_RUN_MIN, 1) }
            steps >= BRISK_MIN_CADENCE -> { add(I_BRISK_STEPS, steps); add(I_BRISK_MIN, 1) }
            else -> add(I_WALK_MIN, 1)
        }
        intensity.put(day, arr)
        trimKeys(intensity, HISTORY_LIMIT)
        dirty = true
    }

    /** Sinirsiz buyumesin: en eski gunler silinir. */
    private fun trimKeys(json: JSONObject, limit: Int) {
        if (json.length() <= limit) return
        val keys = json.keys().asSequence().toMutableList()
        keys.sort()
        for (k in keys.take(json.length() - limit)) json.remove(k)
    }

    /**
     * Olayin gercek olcum saati. Ekran kapaliyken olaylar toplu teslim
     * edilebilir; teslim anini degil olcum anini (event.timestamp) kullanmak
     * adimlari yurundugu saate yazar.
     */
    private fun eventMillis(event: SensorEvent): Long {
        val now = System.currentTimeMillis()
        val ageMs = (SystemClock.elapsedRealtimeNanos() - event.timestamp) / 1_000_000L
        return if (ageMs in 0L..(6L * 3_600_000L)) now - ageMs else now
    }

    private fun hourOf(event: SensorEvent): Int {
        val eventMs = eventMillis(event)
        if (dayKey(eventMs) != date) return 0
        val c = Calendar.getInstance()
        c.timeInMillis = eventMs
        return c.get(Calendar.HOUR_OF_DAY)
    }

    /**
     * Durumu diske yazar. force degilse en fazla PERSIST_INTERVAL_MS'de bir.
     * Surec arada oldurulse de adim kaybolmaz: bugunku deger taban ve
     * savedToday'den yeniden hesaplanir, ikisi de degistikleri an (force)
     * yazilir.
     */
    private fun persist(force: Boolean = false) {
        if (!dirty && !force) return
        val now = System.currentTimeMillis()
        if (!force && now - lastPersist < PERSIST_INTERVAL_MS) return
        prefs(this).edit()
            .putInt(K_TODAY, todaySteps)
            .putInt(K_SAVED, savedToday)
            .putLong(K_BASELINE, baseline)
            .putString(K_DATE, date)
            .putString(K_HISTORY, history.toString())
            .putString(K_HOURLY, hourly.toString())
            .putString(K_INTENSITY, intensity.toString())
            .apply()
        lastPersist = now
        dirty = false
    }

    // ------------------------------------------------------------------
    // Gece yarisi
    // ------------------------------------------------------------------

    private fun midnightIntent(): PendingIntent =
        PendingIntent.getService(
            this,
            1,
            Intent(this, StepService::class.java).setAction(ACTION_MIDNIGHT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    /**
     * Gun, ilk adim beklenmeden gece yarisi kapatilir; yoksa sabah ilk
     * adima kadar bildirim ve widget dunun sayisini gosteriyordu. Kesin
     * alarm izni gerekmez; Doze'da birkac dakika gecikebilir.
     */
    private fun scheduleMidnight() {
        val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val c = Calendar.getInstance()
        c.add(Calendar.DAY_OF_YEAR, 1)
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 5)
        c.set(Calendar.MILLISECOND, 0)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, c.timeInMillis, midnightIntent())
            } else {
                am.set(AlarmManager.RTC_WAKEUP, c.timeInMillis, midnightIntent())
            }
        } catch (e: Exception) {
        }
    }

    private fun onMidnight() {
        val today = dayKey()
        if (today != date) {
            putHistory(date, todaySteps)
            date = today
            savedToday = 0
            todaySteps = 0
            // Elde ham deger yok: ilk adim tabani o ana cakar. Adim yolundaki
            // gun gecisiyle ayni sonuc (dunun adimi bugune devretmez).
            baseline = -1L
            dirty = true
            persist(force = true)
            notifyNow()
            widgetDirty = true
            maybeRenderWidget(force = true)
        }
        scheduleMidnight()
    }

    // ------------------------------------------------------------------
    // Aksam hatirlatmasi (20:00)
    // ------------------------------------------------------------------

    private fun eveningIntent(): PendingIntent =
        PendingIntent.getService(
            this,
            2,
            Intent(this, StepService::class.java).setAction(ACTION_EVENING),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    /** Bir sonraki 20:00. Kesin alarm izni gerekmez; Doze'da birkac dakika kayabilir. */
    private fun scheduleEvening() {
        val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, EVENING_HOUR)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        if (c.timeInMillis <= System.currentTimeMillis()) c.add(Calendar.DAY_OF_YEAR, 1)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, c.timeInMillis, eveningIntent())
            } else {
                am.set(AlarmManager.RTC_WAKEUP, c.timeInMillis, eveningIntent())
            }
        } catch (e: Exception) {
        }
    }

    /**
     * Ayarlar > Aksam hatirlatmasi aciksa ve bugun hedef tutulmadiysa kalan
     * adimi soyleyen bildirim. Hedef tutulduysa hic bildirim gelmez.
     */
    private fun onEvening() {
        try {
            val flutter = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val on = flutter.getBoolean("flutter.notify_evening", false)
            val steps = maxOf(todaySteps, flutterHistory()?.optInt(date, 0) ?: 0)
            val nm = notificationManager()
            val allowed = Build.VERSION.SDK_INT < 33 ||
                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (on && allowed && nm != null && goal > 0 && steps < goal) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    nm.getNotificationChannel(REMINDER_CHANNEL_ID) == null
                ) {
                    nm.createNotificationChannel(
                        NotificationChannel(
                            REMINDER_CHANNEL_ID,
                            "Hatirlatmalar",
                            NotificationManager.IMPORTANCE_DEFAULT
                        ).apply { description = "Hedef ve yurume hatirlatmalari" }
                    )
                }
                val tr = Locale("tr", "TR")
                val left = String.format(tr, "%,d", goal - steps)
                val done = String.format(tr, "%,d", steps)
                val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pending = open?.let {
                    PendingIntent.getActivity(
                        this, 3, it,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                }
                val n = NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_menu_directions)
                    .setContentTitle("Hedefe $left adım kaldı")
                    .setContentText("Bugün $done adım attın. Kısa bir yürüyüşle hedefi tamamlayabilirsin.")
                    .setStyle(
                        NotificationCompat.BigTextStyle()
                            .bigText("Bugün $done adım attın. Kısa bir yürüyüşle hedefi tamamlayabilirsin.")
                    )
                    .setAutoCancel(true)
                    .setContentIntent(pending)
                    .build()
                nm.notify(EVENING_NOTIF_ID, n)
            }
        } catch (e: Exception) {
        }
        scheduleEvening()
    }

    // ------------------------------------------------------------------
    // Haftalik ozet (Pazar 20:30)
    // ------------------------------------------------------------------

    private fun weeklyIntent(): PendingIntent =
        PendingIntent.getService(
            this,
            4,
            Intent(this, StepService::class.java).setAction(ACTION_WEEKLY),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun scheduleWeekly() {
        val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val c = Calendar.getInstance()
        c.set(Calendar.DAY_OF_WEEK, Calendar.SUNDAY)
        c.set(Calendar.HOUR_OF_DAY, 20)
        c.set(Calendar.MINUTE, 30)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        while (c.timeInMillis <= System.currentTimeMillis()) c.add(Calendar.DAY_OF_YEAR, 7)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, c.timeInMillis, weeklyIntent())
            } else {
                am.set(AlarmManager.RTC_WAKEUP, c.timeInMillis, weeklyIntent())
            }
        } catch (e: Exception) {
        }
    }

    /** Haftanin gercek sayilari: adim, km, hedef tutulan gun, gecen haftaya gore degisim. */
    private fun onWeekly() {
        try {
            val allowed = Build.VERSION.SDK_INT < 33 ||
                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            val nm = notificationManager()
            if (flutterBool(this, "notify_weekly", false) && allowed && nm != null) {
                val flutter = flutterHistory()
                val today = maxOf(todaySteps, flutter?.optInt(date, 0) ?: 0)
                fun stepsOf(key: String): Int = when {
                    key == date -> today
                    flutter != null && flutter.has(key) -> flutter.optInt(key, 0)
                    else -> history.optInt(key, 0)
                }
                val c = Calendar.getInstance()
                c.add(Calendar.DAY_OF_YEAR, -weekdayIndex())
                var steps = 0
                var km = 0.0
                var goalDays = 0
                var prev = 0
                val p = Calendar.getInstance().apply { timeInMillis = c.timeInMillis; add(Calendar.DAY_OF_YEAR, -7) }
                for (i in 0 until 7) {
                    val key = dayKey(c.timeInMillis)
                    val s = stepsOf(key)
                    steps += s
                    km += dayMetrics(key, s).km
                    if (goal > 0 && s >= goal) goalDays++
                    prev += stepsOf(dayKey(p.timeInMillis))
                    c.add(Calendar.DAY_OF_YEAR, 1)
                    p.add(Calendar.DAY_OF_YEAR, 1)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    nm.getNotificationChannel(REMINDER_CHANNEL_ID) == null
                ) {
                    nm.createNotificationChannel(
                        NotificationChannel(
                            REMINDER_CHANNEL_ID, "Hatirlatmalar", NotificationManager.IMPORTANCE_DEFAULT
                        )
                    )
                }
                val tr = Locale("tr", "TR")
                val change = if (prev > 0) {
                    val pct = Math.round((steps - prev) * 100.0 / prev).toInt()
                    if (pct >= 0) "Geçen haftaya göre %$pct ↑" else "Geçen haftaya göre %${-pct} ↓"
                } else "Geçen hafta kayıt yok"
                val text = String.format(tr, "%,d adım · %.1f km · %d/7 gün hedef", steps, km, goalDays)
                val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pending = open?.let {
                    PendingIntent.getActivity(this, 5, it,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                }
                nm.notify(
                    WEEKLY_NOTIF_ID,
                    NotificationCompat.Builder(this, REMINDER_CHANNEL_ID)
                        .setSmallIcon(android.R.drawable.ic_menu_directions)
                        .setContentTitle("Haftalık özet")
                        .setContentText(text)
                        .setStyle(NotificationCompat.BigTextStyle().bigText("$text\n$change"))
                        .setAutoCancel(true)
                        .setContentIntent(pending)
                        .build()
                )
            }
        } catch (e: Exception) {
        }
        scheduleWeekly()
    }

    // ------------------------------------------------------------------
    // Widget (uygulama kapaliyken)
    // ------------------------------------------------------------------

    private fun maybeRenderWidget(force: Boolean = false) {
        // On plandayken widget'i Flutter ciziyor; ikisi birbirinin ustune yazmasin.
        if (appInForeground) return
        if (!widgetDirty && !force) return
        val now = System.currentTimeMillis()
        if (!force && now - lastWidget < WIDGET_INTERVAL_MS) return
        // Hata olsa da aralik uygulanir; her adimda yeniden denenmesin.
        lastWidget = now
        try {
            val mgr = AppWidgetManager.getInstance(this)
            val ids = mgr.getAppWidgetIds(ComponentName(this, StepWidgetProvider::class.java))
            if (ids.isEmpty()) {
                // Ana ekranda widget yok: cizmeye gerek yok.
                widgetDirty = false
                return
            }
            val flutter = flutterHistory()
            val steps = maxOf(todaySteps, flutter?.optInt(date, 0) ?: 0)
            // Uygulama ve kalici bildirimle ayni hesap (tempo kirilimi dahil).
            val m = todayMetrics(steps)
            val bmp = WidgetRenderer.render(
                this,
                steps,
                goal,
                m.km,
                m.kcal,
                m.minutes,
                currentWeek(flutter, steps),
                weekdayIndex(),
                // Su takibi kapaliysa su hucresi cizilmez.
                if (waterEnabled(this)) flutterWater()?.optInt(date, 0) ?: 0 else null
            )
            val file = File(filesDir, WIDGET_FILE)
            FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bmp.recycle()
            HomeWidgetPlugin.getData(this).edit()
                .putString(WIDGET_IMAGE_KEY, file.absolutePath)
                .apply()
            sendBroadcast(Intent(this, StepWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            })
            widgetDirty = false
        } catch (e: Exception) {
        }
    }

    /**
     * Flutter tarafinin gecmisi. Gecmis gunler icin asil kaynak odur: servisle
     * zaten birlestirilmistir ve elle duzeltilen gunleri icerir.
     */
    private fun flutterHistory(): JSONObject? =
        try {
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.history_json", null)
                ?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }

    private fun flutterWater(): JSONObject? =
        try {
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.water_json", null)
                ?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }

    /** Pazartesi = 0 ... Pazar = 6 (Dart'taki weekday - 1). */
    private fun weekdayIndex(): Int =
        (Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7

    private fun currentWeek(flutter: JSONObject?, todayValue: Int): IntArray {
        val c = Calendar.getInstance()
        c.add(Calendar.DAY_OF_YEAR, -weekdayIndex())
        val out = IntArray(7)
        for (i in 0 until 7) {
            val key = dayKey(c.timeInMillis)
            out[i] = when {
                key == date -> todayValue
                flutter != null && flutter.has(key) -> flutter.optInt(key, 0)
                else -> history.optInt(key, 0)
            }
            c.add(Calendar.DAY_OF_YEAR, 1)
        }
        return out
    }

    /**
     * Bugunun km / kcal / dakikasi. Formuller Formulas.kt'de (Dart'taki
     * breakdownForDay ile birebir): tempo kaydi gunun toplamina kirpilir,
     * sure saatlik kayit yeterliyse gercek sureden gelir.
     */
    private fun todayMetrics(steps: Int): Formulas.DayMetrics = dayMetrics(date, steps)

    /** Herhangi bir gun (haftalik ozet); sure yalnizca bugun icin gercek. */
    private fun dayMetrics(day: String, steps: Int): Formulas.DayMetrics {
        val arr = intensity.optJSONArray(day)
        val valid = arr != null && arr.length() == I_LEN
        val run = if (valid) arr!!.optInt(I_RUN_STEPS, 0).coerceIn(0, steps) else 0
        val brisk = if (valid) arr!!.optInt(I_BRISK_STEPS, 0).coerceIn(0, steps - run) else 0
        return Formulas.breakdown(
            totalSteps = steps,
            briskSteps = brisk,
            briskMin = if (brisk > 0) arr!!.optInt(I_BRISK_MIN, 0) else 0,
            runSteps = run,
            runMin = if (run > 0) arr!!.optInt(I_RUN_MIN, 0) else 0,
            hasData = valid,
            heightCm = heightCm,
            weightKg = weightKg,
            activeMin = if (day == date) activeMinutesToday(steps) else null
        )
    }

    /** Dart'taki activeMinutesFor ile ayni: kapsama yetersizse null (tahmine duser). */
    private fun activeMinutesToday(steps: Int): Int? {
        val arr = hourly.optJSONArray(date) ?: return null
        if (arr.length() != 24) return null
        var covered = 0
        var minutes = 0
        for (i in 0 until 24) {
            val h = arr.optInt(i, 0)
            covered += h
            if (h >= 20) minutes += ((h + 109) / 110).coerceIn(1, 60)
        }
        if (steps > 0 && covered < steps * 0.8) return null
        return if (minutes > 0) minutes else null
    }

    // ------------------------------------------------------------------
    // Bildirim
    // ------------------------------------------------------------------

    fun notifyNow() {
        lastNotify = System.currentTimeMillis()
        notificationManager()?.notify(NOTIF_ID, buildNotification())
    }

    private fun notificationManager(): NotificationManager? =
        getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Adım sayımı",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Adım sayımının arka planda sürmesini sağlar."
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        notificationManager()?.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val flutter = flutterHistory()
        val steps = maxOf(todaySteps, flutter?.optInt(date, 0) ?: 0)
        val percent = if (goal > 0) (steps * 100 / goal) else 0
        // Uygulamadaki hesapla ayni formuller (WidgetRenderer / metrics.dart).
        val tr = Locale("tr", "TR")
        // Tempo (normal / tempolu / kosu) kaydi varsa uygulamadaki
        // kirilimla ayni yontemle hesaplanir.
        val metrics = todayMetrics(steps)
        val km = metrics.km
        val kcal = metrics.kcal
        val minutes = metrics.minutes
        val waterOn = waterEnabled(this)
        val waterMl = flutterWater()?.optInt(date, 0) ?: 0
        val stepsTxt = String.format(tr, "%,d", steps)
        val kmTxt = String.format(tr, "%.2f km", km)
        val kcalTxt = String.format(tr, "%,d kcal", Math.round(kcal).toInt())
        val timeTxt = WidgetRenderer.duration(minutes)
        val waterTxt = String.format(tr, "%.1f L", waterMl / 1000.0)
        val short = "👣 $stepsTxt  📏 $kmTxt  🔥 $kcalTxt" + (if (waterOn) "  💧 $waterTxt" else "")
        val details = NotificationCompat.InboxStyle()
            .setBigContentTitle("Yürüyüş Defteri · hedefin %$percent")
            .addLine("👣  $stepsTxt adım")
            .addLine("📏  $kmTxt mesafe")
            .addLine("🔥  $kcalTxt yakıldı")
            .addLine("⏱  $timeTxt yürüyüş")
        if (waterOn) details.addLine("💧  $waterTxt su")
        workout?.notificationLine()?.let { details.addLine(it) }
        when {
            route?.active == true -> details.addLine("📍  Rota kaydediliyor")
            RouteTracker.isEnabled(this) && !RouteTracker.locationOn(this) ->
                details.addLine("📍  Konum kapalı · rota kaydedilmiyor")
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = if (open != null) {
            PendingIntent.getActivity(
                this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle("Yürüyüş Defteri · hedefin %$percent")
            .setContentText(short)
            .setStyle(details)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setContentIntent(pending)
            .build()
    }
}
