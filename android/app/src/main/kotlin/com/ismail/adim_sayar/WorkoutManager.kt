package com.ismail.adim_sayar

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

/**
 * Yuruyus kaydi (baslat / bitir) ve aralikli yuruyus modu.
 *
 * - Baslayinca GPS adimlardan bagimsiz surekli acik kalir (RouteTracker.setForced),
 *   rota yeni bir parca olarak cizilir.
 * - Her kilometrede titresim + sesli bildirim: mesafe, toplam sure, son km temposu.
 * - Aralikli modda [fastSec] hizli / [slowSec] yavas donguleri [rounds] tur;
 *   her geciste titresim ve "Hizli tempo" / "Yavasla" sesi.
 * - Bitince ozet filesDir/workouts.json'a eklenir (son 300 kayit).
 *
 * Uygulama kapaliyken de calisir (StepService icinde).
 */
class WorkoutManager(
    private val ctx: Context,
    private val stepsNow: () -> Int,
    private val onChanged: () -> Unit
) : TextToSpeech.OnInitListener {

    companion object {
        private const val FILE = "workouts.json"
        private const val KEEP = 300

        /** Otomatik duraklatma acik mi (varsayilan acik). */
        const val K_AUTO_PAUSE = "auto_pause"
        /** Bu kadar adim gelmezse kayit duraklar. */
        private const val PAUSE_AFTER_MS = 10_000L
        /** Devam icin adim olayi en fazla bu kadar eski olabilir (toplu teslim). */
        private const val RESUME_FRESH_MS = 5_000L
        private const val PAUSE_CHECK_MS = 2_000L

        /** Sesli koc sikligi: 0 = her km, 5/10 = her N dakika. */
        const val K_VOICE_EVERY = "voice_every_min"

        /** Rakim: tirmanis/inis sayilmasi icin en az degisim (gurultu esigi). */
        private const val ELEV_STEP_M = 3.0
        /** Barometre yumusatma katsayisi. */
        private const val ELEV_ALPHA = 0.1
        /** Rakim profili ornekleme araligi (sn) ve ozetteki en fazla nokta. */
        private const val ELEV_SAMPLE_SEC = 10L
        private const val ELEV_MAX_POINTS = 120

        fun readAll(c: Context): JSONArray =
            try {
                val f = File(c.filesDir, FILE)
                if (f.exists()) JSONArray(f.readText()) else JSONArray()
            } catch (e: Exception) {
                JSONArray()
            }
    }

    @Volatile var active = false
        private set

    private var startWall = 0L
    private var startElapsed = 0L
    private var startSteps = -1
    private var distanceM = 0.0
    /** Her tamamlanan km'nin baslangictan itibaren saniyesi. */
    private val splits = mutableListOf<Long>()

    // ---- Aralikli mod ----
    private var interval = false
    private var fastSec = 180
    private var slowSec = 180
    private var rounds = 5
    private var round = 0
    private var fastPhase = true
    private var phaseEndsAt = 0L
    private var intervalDone = false

    private var briskSteps = 0
    private var briskMin = 0
    private var runSteps = 0
    private var runMin = 0
    private var lastMinuteSec = 0L
    private var lastMinuteSteps = -1

    // ---- Hedef (0: yok) ----
    private var goalM = 0
    private var goalSec = 0
    private var goalDone = false
    private var goalHalfSaid = false

    // ---- Otomatik duraklatma ----
    /** Adim dedektoru bagli mi (yoksa duraklatma devre disi; gecikmeli sayac yanlis durdurur). */
    @Volatile var stepFeedLive = false
    private var autoPause = true
    @Volatile var paused = false
        private set
    /** Kullanici duraklatti (bildirim/uygulama): adim gelince kendiliginden devam etmez. */
    @Volatile var manualPaused = false
        private set

    fun pauseManual() {
        if (!active) return
        manualPaused = true
        if (paused) { onChanged(); return }
        paused = true
        pauseStartElapsed = SystemClock.elapsedRealtime()
        vibrate(longArrayOf(0, 60, 80, 60))
        onChanged()
    }

    fun resumeManual() {
        if (!active || !paused) return
        val now = SystemClock.elapsedRealtime()
        pausedTotalMs += maxOf(0L, now - pauseStartElapsed)
        paused = false
        manualPaused = false
        lastStepElapsed = now
        vibrate(longArrayOf(0, 120))
        onChanged()
    }
    private var pauseStartElapsed = 0L
    private var pausedTotalMs = 0L
    private var lastStepElapsed = 0L

    private val pauseCheck = object : Runnable {
        override fun run() {
            if (!active) return
            val now = SystemClock.elapsedRealtime()
            if (autoPause && stepFeedLive && !paused &&
                now - startElapsed > 15_000L &&
                now - lastStepElapsed > PAUSE_AFTER_MS
            ) {
                paused = true
                // Duraklama son adimdan ~1 sn sonra baslamis sayilir.
                pauseStartElapsed = minOf(now, lastStepElapsed + 1_000L)
                vibrate(longArrayOf(0, 60, 80, 60))
                onChanged()
            }
            handler.postDelayed(this, PAUSE_CHECK_MS)
        }
    }

    /** StepService her adim olayinda cagirir ([eventWallMs]: olayin zamani). */
    fun onStep(eventWallMs: Long) {
        if (!active) return
        val ageMs = System.currentTimeMillis() - eventWallMs
        if (ageMs > RESUME_FRESH_MS) return
        val now = SystemClock.elapsedRealtime()
        val at = now - maxOf(0L, ageMs)
        if (at > lastStepElapsed) lastStepElapsed = at
        if (paused && !manualPaused) {
            pausedTotalMs += maxOf(0L, at - pauseStartElapsed)
            paused = false
            vibrate(longArrayOf(0, 120))
            onChanged()
        }
    }

    /** Hareket suresi (duraklamalar haric), sn. Otomatik duraklatma kapaliysa toplam sure. */
    fun activeSec(): Long {
        if (startElapsed == 0L) return 0
        val now = SystemClock.elapsedRealtime()
        val current = if (paused) maxOf(0L, now - pauseStartElapsed) else 0L
        return maxOf(0L, (now - startElapsed - pausedTotalMs - current) / 1000)
    }

    // ---- Sesli koc (zaman tabanli) ----
    private var nextVoiceSec = 0L

    // ---- Rakim (barometre) ----
    private val sensorManager = ctx.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private var baroOn = false
    private var elevSmooth = Double.NaN
    private var elevBase = Double.NaN
    private var elevRef = Double.NaN
    private var elevGain = 0.0
    private var elevLoss = 0.0
    private var lastElevSampleSec = -ELEV_SAMPLE_SEC
    private val elevSamples = mutableListOf<Double>()

    private val baroListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            val p = event?.values?.firstOrNull() ?: return
            if (p <= 0f) return
            val alt = SensorManager.getAltitude(SensorManager.PRESSURE_STANDARD_ATMOSPHERE, p).toDouble()
            if (elevSmooth.isNaN()) {
                elevSmooth = alt
                elevBase = alt
                elevRef = alt
                return
            }
            elevSmooth += ELEV_ALPHA * (alt - elevSmooth)
            val d = elevSmooth - elevRef
            if (d >= ELEV_STEP_M) {
                elevGain += d
                elevRef = elevSmooth
            } else if (d <= -ELEV_STEP_M) {
                elevLoss += -d
                elevRef = elevSmooth
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            if (!active) return
            if (interval && !intervalDone) checkPhase()
            checkGoal()
            checkTimedVoice()
            sampleElevation()
            
            val currentSteps = stepsNow()
            val sec = elapsedSec()
            if (sec - lastMinuteSec >= 60) {
                val deltaSteps = currentSteps - lastMinuteSteps
                if (deltaSteps >= Formulas.RUN_MIN_CADENCE) {
                    runSteps += deltaSteps
                    runMin += 1
                } else if (deltaSteps >= Formulas.BRISK_MIN_CADENCE) {
                    briskSteps += deltaSteps
                    briskMin += 1
                }
                lastMinuteSec = sec
                lastMinuteSteps = currentSteps
            }
            
            onChanged()
            handler.postDelayed(this, 5_000L)
        }
    }

    fun start(
        intervalMode: Boolean,
        roundCount: Int,
        fastS: Int,
        slowS: Int,
        goalMeters: Int = 0,
        goalSeconds: Int = 0
    ) {
        if (active) return
        active = true
        goalM = goalMeters.coerceIn(0, 100_000)
        goalSec = goalSeconds.coerceIn(0, 6 * 3600)
        goalDone = false
        goalHalfSaid = false
        nextVoiceSec = voiceEveryMin() * 60L
        startBarometer()
        autoPause = StepService.prefs(ctx).getBoolean(K_AUTO_PAUSE, true)
        paused = false
        manualPaused = false
        pausedTotalMs = 0L
        lastStepElapsed = startElapsed
        handler.removeCallbacks(pauseCheck)
        handler.postDelayed(pauseCheck, PAUSE_CHECK_MS)
        startWall = System.currentTimeMillis()
        startElapsed = SystemClock.elapsedRealtime()
        startSteps = stepsNow()
        distanceM = 0.0
        splits.clear()
        interval = intervalMode
        rounds = roundCount.coerceIn(1, 20)
        fastSec = fastS.coerceIn(30, 900)
        slowSec = slowS.coerceIn(30, 900)
        round = 1
        fastPhase = true
        intervalDone = false
        phaseEndsAt = startElapsed + fastSec * 1000L
        briskSteps = 0
        briskMin = 0
        runSteps = 0
        runMin = 0
        lastMinuteSec = 0L
        lastMinuteSteps = startSteps
        initTts()
        vibrate(longArrayOf(0, 250))
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, 1_000L)
        // Ilk anons TTS hazir olunca (onInit) yapilir.
        onChanged()
    }

    /** Biter, ozeti kaydeder ve dondurur. */
    fun stop(): JSONObject? {
        if (!active) return null
        // Duraklamadayken bitirilirse duraklama suresi dusulur.
        val finalActive = activeSec()
        active = false
        handler.removeCallbacks(tick)
        handler.removeCallbacks(pauseCheck)
        stopBarometer()
        val summary = summaryJson()
        paused = false
        save(summary)
        val km = String.format(Locale("tr", "TR"), "%.2f", distanceM / 1000.0)
        speak("Yürüyüş bitti. $km kilometre, ${spokenDuration(finalActive)}.")
        vibrate(longArrayOf(0, 200, 120, 200))
        // Son anons bitince TTS kapanir.
        handler.postDelayed({ shutdownTts() }, 8_000L)
        onChanged()
        return summary
    }

    fun shutdown() {
        if (active) stop()
        stopBarometer()
        handler.removeCallbacks(tick)
        shutdownTts()
    }

    /** RouteTracker kabul edilen her noktada cagirir. */
    fun onDistance(m: Double) {
        if (!active || m <= 0) return
        // Duraklamadayken GPS kaymasi mesafeye eklenmez.
        if (paused) return
        distanceM += m
        val km = (distanceM / 1000.0).toInt()
        if (km > splits.size) {
            val sec = activeSec()
            val prev = splits.lastOrNull() ?: 0L
            splits.add(sec)
            vibrate(longArrayOf(0, 300))
            // Zaman tabanli kocta km anonsu yapilmaz (yalniz titresim).
            if (voiceEveryMin() == 0) {
                speak("$km kilometre tamamlandı. Süre ${spokenDuration(sec)}. " +
                    "Son kilometre ${spokenDuration(sec - prev)}. " +
                    "Ortalama tempo ${spokenPace(sec.toDouble(), distanceM)}.")
            }
            onChanged()
        }
    }

    fun elapsedSec(): Long =
        if (startElapsed == 0L) 0 else (SystemClock.elapsedRealtime() - startElapsed) / 1000

    fun distanceMeters(): Double = distanceM

    fun statusJson(): JSONObject {
        val o = JSONObject()
        o.put("active", active)
        if (!active) return o
        o.put("start", startWall)
        o.put("elapsedSec", elapsedSec())
        o.put("movingSec", activeSec())
        o.put("paused", paused)
        o.put("manualPaused", manualPaused)
        o.put("autoPause", autoPause && stepFeedLive)
        o.put("distanceM", distanceM)
        val now = stepsNow()
        o.put("steps", if (startSteps >= 0 && now >= startSteps) now - startSteps else 0)
        o.put("briskSteps", briskSteps)
        o.put("briskMin", briskMin)
        o.put("runSteps", runSteps)
        o.put("runMin", runMin)
        o.put("splits", JSONArray(splits))
        o.put("interval", interval)
        o.put("goalM", goalM)
        o.put("goalSec", goalSec)
        o.put("goalDone", goalDone)
        if (baroOn) {
            o.put("elevGain", Math.round(elevGain * 10) / 10.0)
            o.put("elevLoss", Math.round(elevLoss * 10) / 10.0)
        }
        if (interval) {
            o.put("rounds", rounds)
            o.put("round", round)
            o.put("fast", fastPhase)
            o.put("intervalDone", intervalDone)
            o.put("phaseLeftSec",
                if (intervalDone) 0 else maxOf(0L, (phaseEndsAt - SystemClock.elapsedRealtime()) / 1000))
        }
        return o
    }

    /** Kalici bildirim satiri. */
    fun notificationLine(): String? {
        if (!active) return null
        val tr = Locale("tr", "TR")
        val base = String.format(tr, "%s  Yürüyüş · %.2f km · %s",
            if (paused) "⏸" else "🏃", distanceM / 1000.0, clock(activeSec())) +
            (if (paused) " · duraklatıldı" else "")
        if (!interval || intervalDone) return base
        val left = maxOf(0L, (phaseEndsAt - SystemClock.elapsedRealtime()) / 1000)
        return "$base · ${if (fastPhase) "HIZLI" else "yavaş"} ${clock(left)} (tur $round/$rounds)"
    }

    // ------------------------------------------------------------------

    private fun voiceEveryMin(): Int =
        StepService.prefs(ctx).getInt(K_VOICE_EVERY, 0).let { if (it == 5 || it == 10) it else 0 }

    /** "6 dakika 30 saniye" (km basina); 200 m altinda anlamsiz. */
    private fun spokenPace(sec: Double, meters: Double): String {
        if (meters < 200) return "henüz hesaplanmadı"
        return spokenDuration((sec / (meters / 1000.0)).toLong())
    }

    /** Her 5/10 dakikada bir: sure, mesafe, ortalama tempo. */
    private fun checkTimedVoice() {
        val every = voiceEveryMin()
        if (every == 0 || paused) return
        val sec = activeSec()
        if (nextVoiceSec <= 0L) nextVoiceSec = every * 60L
        if (sec < nextVoiceSec) return
        nextVoiceSec = (sec / (every * 60L) + 1) * every * 60L
        val km = String.format(Locale("tr", "TR"), "%.2f", distanceM / 1000.0)
        speak("${spokenDuration(sec)} oldu. Mesafe $km kilometre. " +
            "Ortalama tempo ${spokenPace(sec.toDouble(), distanceM)}.")
    }

    private fun startBarometer() {
        elevSmooth = Double.NaN
        elevBase = Double.NaN
        elevRef = Double.NaN
        elevGain = 0.0
        elevLoss = 0.0
        lastElevSampleSec = -ELEV_SAMPLE_SEC
        elevSamples.clear()
        val sm = sensorManager ?: return
        val sensor = sm.getDefaultSensor(Sensor.TYPE_PRESSURE) ?: return
        baroOn = try {
            sm.registerListener(baroListener, sensor, SensorManager.SENSOR_DELAY_NORMAL, 5_000_000)
        } catch (e: Exception) {
            false
        }
    }

    private fun stopBarometer() {
        if (!baroOn) return
        try { sensorManager?.unregisterListener(baroListener) } catch (e: Exception) {}
        baroOn = false
    }

    private fun sampleElevation() {
        if (!baroOn || elevSmooth.isNaN()) return
        val sec = elapsedSec()
        if (sec - lastElevSampleSec < ELEV_SAMPLE_SEC) return
        lastElevSampleSec = sec
        elevSamples.add(Math.round((elevSmooth - elevBase) * 10) / 10.0)
    }

    /** Esit aralikli en fazla [max] nokta. */
    private fun downsample(src: List<Double>, max: Int): List<Double> {
        if (src.size <= max) return src.toList()
        val step = (src.size - 1).toDouble() / (max - 1)
        return List(max) { i -> src[Math.round(i * step).toInt()] }
    }

    /** Mesafe/sure hedefi: yarida ve dolunca sesli bildirim. */
    private fun checkGoal() {
        if (goalDone || (goalM <= 0 && goalSec <= 0)) return
        val progress = when {
            goalM > 0 -> distanceM / goalM
            else -> activeSec().toDouble() / goalSec
        }
        if (!goalHalfSaid && progress >= 0.5 && progress < 1.0) {
            goalHalfSaid = true
            vibrate(longArrayOf(0, 150, 100, 150))
            speak("Hedefin yarısı tamam. Böyle devam!")
        }
        val reached = (goalM > 0 && distanceM >= goalM) ||
            (goalSec > 0 && activeSec() >= goalSec)
        if (!reached) return
        goalDone = true
        vibrate(longArrayOf(0, 300, 150, 300, 150, 500))
        val km = String.format(Locale("tr", "TR"), "%.2f", distanceM / 1000.0)
        speak("Tebrikler, hedefe ulaştın. $km kilometre, ${spokenDuration(activeSec())}.")
        onChanged()
    }

    private fun checkPhase() {
        val now = SystemClock.elapsedRealtime()
        if (now < phaseEndsAt) return
        if (fastPhase) {
            fastPhase = false
            phaseEndsAt = now + slowSec * 1000L
            vibrate(longArrayOf(0, 150, 100, 150))
            speak("Yavaşla. ${spokenDuration(slowSec.toLong())} rahat tempo.")
        } else if (round < rounds) {
            round++
            fastPhase = true
            phaseEndsAt = now + fastSec * 1000L
            vibrate(longArrayOf(0, 400))
            speak("Tur $round. Hızlı tempo, ${spokenDuration(fastSec.toLong())}.")
        } else {
            intervalDone = true
            vibrate(longArrayOf(0, 200, 120, 200, 120, 200))
            speak("Aralıklı yürüyüş tamamlandı. Kayıt sürüyor, bitirmek için uygulamadan Bitir'e bas.")
        }
    }

    private fun summaryJson(): JSONObject {
        val o = JSONObject()
        o.put("start", startWall)
        o.put("end", System.currentTimeMillis())
        // durationSec: hareket suresi (tempo bundan); totalSec: duraklamalar dahil.
        o.put("durationSec", activeSec())
        o.put("totalSec", elapsedSec())
        o.put("distanceM", distanceM)
        val now = stepsNow()
        o.put("steps", if (startSteps >= 0 && now >= startSteps) now - startSteps else 0)
        o.put("briskSteps", briskSteps)
        o.put("briskMin", briskMin)
        o.put("runSteps", runSteps)
        o.put("runMin", runMin)
        o.put("splits", JSONArray(splits))
        o.put("interval", interval)
        if (goalM > 0) o.put("goalM", goalM)
        if (goalSec > 0) o.put("goalSec", goalSec)
        if (goalM > 0 || goalSec > 0) o.put("goalDone", goalDone)
        if (elevSamples.size >= 2) {
            o.put("elevGain", Math.round(elevGain * 10) / 10.0)
            o.put("elevLoss", Math.round(elevLoss * 10) / 10.0)
            o.put("elev", JSONArray(downsample(elevSamples, ELEV_MAX_POINTS)))
        }
        if (interval) {
            o.put("rounds", rounds)
            o.put("roundsDone", if (intervalDone) rounds else round - (if (fastPhase) 1 else 0))
        }
        o.put("day", StepService.dayKey(startWall))
        return o
    }

    private fun save(o: JSONObject) {
        try {
            val all = readAll(ctx)
            all.put(o)
            val out = JSONArray()
            val from = maxOf(0, all.length() - KEEP)
            for (i in from until all.length()) out.put(all.get(i))
            File(ctx.filesDir, FILE).writeText(out.toString())
        } catch (e: Exception) {
        }
    }

    // ---- Ses ve titresim ----

    private fun initTts() {
        if (tts != null) return
        try {
            tts = TextToSpeech(ctx.applicationContext, this)
        } catch (e: Exception) {
            tts = null
        }
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) {
            try {
                tts?.language = Locale("tr", "TR")
            } catch (e: Exception) {
            }
            if (active) {
                speak(
                    if (interval) "Aralıklı yürüyüş başladı. Tur 1. Hızlı tempo, ${spokenDuration(fastSec.toLong())}."
                    else "Yürüyüş başladı."
                )
            }
        }
    }

    private fun speak(text: String) {
        if (!ttsReady) return
        val muted = StepService.prefs(ctx).getBoolean("voice_muted", false)
        if (muted) return
        try {
            tts?.speak(text, TextToSpeech.QUEUE_ADD, null, "yd_${SystemClock.elapsedRealtime()}")
        } catch (e: Exception) {
        }
    }

    private fun shutdownTts() {
        if (active) return
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (e: Exception) {
        }
        tts = null
        ttsReady = false
    }

    private fun vibrate(pattern: LongArray) {
        try {
            val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
                (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            if (v == null || !v.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= 26) {
                v.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, -1)
            }
        } catch (e: Exception) {
        }
    }

    private fun clock(sec: Long): String {
        val h = sec / 3600
        val m = (sec % 3600) / 60
        val s = sec % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%d:%02d", m, s)
    }

    private fun spokenDuration(sec: Long): String {
        val m = sec / 60
        val s = sec % 60
        return when {
            m == 0L -> "$s saniye"
            s == 0L -> "$m dakika"
            else -> "$m dakika $s saniye"
        }
    }
}
