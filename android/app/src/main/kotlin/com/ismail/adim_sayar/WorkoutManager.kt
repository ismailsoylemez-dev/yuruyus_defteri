package com.ismail.adim_sayar

import android.content.Context
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

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val handler = Handler(Looper.getMainLooper())

    private val tick = object : Runnable {
        override fun run() {
            if (!active) return
            if (interval && !intervalDone) checkPhase()
            onChanged()
            handler.postDelayed(this, 5_000L)
        }
    }

    fun start(intervalMode: Boolean, roundCount: Int, fastS: Int, slowS: Int) {
        if (active) return
        active = true
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
        active = false
        handler.removeCallbacks(tick)
        val summary = summaryJson()
        save(summary)
        val km = String.format(Locale("tr", "TR"), "%.2f", distanceM / 1000.0)
        speak("Yürüyüş bitti. $km kilometre, ${spokenDuration(elapsedSec())}.")
        vibrate(longArrayOf(0, 200, 120, 200))
        // Son anons bitince TTS kapanir.
        handler.postDelayed({ shutdownTts() }, 8_000L)
        onChanged()
        return summary
    }

    fun shutdown() {
        if (active) stop()
        handler.removeCallbacks(tick)
        shutdownTts()
    }

    /** RouteTracker kabul edilen her noktada cagirir. */
    fun onDistance(m: Double) {
        if (!active || m <= 0) return
        distanceM += m
        val km = (distanceM / 1000.0).toInt()
        if (km > splits.size) {
            val sec = elapsedSec()
            val prev = splits.lastOrNull() ?: 0L
            splits.add(sec)
            vibrate(longArrayOf(0, 300))
            speak("$km kilometre. Süre ${spokenDuration(sec)}. " +
                "Son kilometre ${spokenDuration(sec - prev)}.")
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
        o.put("distanceM", distanceM)
        val now = stepsNow()
        o.put("steps", if (startSteps >= 0 && now >= startSteps) now - startSteps else 0)
        o.put("splits", JSONArray(splits))
        o.put("interval", interval)
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
        val base = String.format(tr, "🏃  Yürüyüş · %.2f km · %s", distanceM / 1000.0, clock(elapsedSec()))
        if (!interval || intervalDone) return base
        val left = maxOf(0L, (phaseEndsAt - SystemClock.elapsedRealtime()) / 1000)
        return "$base · ${if (fastPhase) "HIZLI" else "yavaş"} ${clock(left)} (tur $round/$rounds)"
    }

    // ------------------------------------------------------------------

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
        o.put("durationSec", elapsedSec())
        o.put("distanceM", distanceM)
        val now = stepsNow()
        o.put("steps", if (startSteps >= 0 && now >= startSteps) now - startSteps else 0)
        o.put("splits", JSONArray(splits))
        o.put("interval", interval)
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
