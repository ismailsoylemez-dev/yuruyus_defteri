package com.ismail.adim_sayar

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.location.LocationManagerCompat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

/**
 * Gun boyu rota kaydi. GPS'i adim sensoru yonetir:
 *  - kisa surede yeterli adim gelirse konum guncellemeleri acilir,
 *  - [IDLE_STOP_MS] boyunca adim gelmezse kapanir.
 * Boylece GPS yalnizca yururken/kosarken calisir; pil tuketimi dusuk kalir.
 *
 * Kayit: filesDir/routes/yyyy-MM-dd.csv
 *   satir = parca,zamanMs,enlem,boylam,dogrulukM
 * "parca" 5 dakikadan uzun duraklamada artar; harita her parcayi ayri cizer.
 */
class RouteTracker(
    private val ctx: Context,
    private val onStateChanged: () -> Unit,
    /** Gunun o anki adim sayisi (her noktaya yazilir: adim boyu olcumu). */
    private val stepsNow: () -> Int = { -1 },
    /** Kabul edilen her noktada bir oncekine uzaklik (m); yuruyus kaydi icin. */
    private val onDistance: (Double) -> Unit = {}
) {

    companion object {
        const val K_ROUTE_ENABLED = "routeEnabled"
        private const val DIR = "routes"

        /** GPS'i acmak icin [START_WINDOW_MS] icinde gereken adim. */
        private const val START_STEPS = 15
        private const val START_WINDOW_MS = 45_000L

        /** Bu kadar adim gelmezse GPS kapanir. */
        /** Durunca GPS en gec ~1,5-2 dk icinde kapanir (pil). */
        private const val IDLE_STOP_MS = 90_000L
        private const val IDLE_CHECK_MS = 20_000L

        /** Bundan uzun bosluk yeni parca baslatir. */
        private const val SEGMENT_GAP_MS = 300_000L

        /** Bundan kotu dogruluktaki konum atilir (bina ici sicramalar). */
        const val MAX_ACCURACY_M = 50f

        /** Kucuk hareketler de cizilsin: 2 m ve uzeri yer degistirme kaydedilir. */
        private const val MIN_MOVE_M = 2f

        /** Yaya icin imkansiz hiz (~43 km/sa): GPS sicramasi sayilir. */
        private const val MAX_SPEED_MPS = 12f

        private const val FLUSH_POINTS = 10
        private const val FLUSH_MS = 60_000L
        private const val KEEP_DAYS = 800

        fun hasFine(c: Context): Boolean =
            ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        fun hasBackground(c: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                ContextCompat.checkSelfPermission(
                    c, Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ) == PackageManager.PERMISSION_GRANTED

        fun isEnabled(c: Context): Boolean =
            StepService.prefs(c).getBoolean(K_ROUTE_ENABLED, false)

        fun dir(c: Context): File = File(c.filesDir, DIR).apply { mkdirs() }

        /**
         * [from]..[to] (yyyy-MM-dd, dahil) arasindaki gunleri okur.
         * [minGapM]: ardisik noktalar arasi en az mesafe; uzun donemlerde
         * veriyi seyreltir (yil gorunumu binlerce nokta tasimasin).
         * Donus: { "gun": [[parca, zamanMs, enlem, boylam, adim], ...] }
         * adim: o andaki gunluk adim sayisi (eski kayitlarda -1).
         */
        fun readDays(c: Context, from: String, to: String, minGapM: Double): JSONObject {
            val out = JSONObject()
            val files = dir(c).listFiles() ?: return out
            val result = FloatArray(1)
            for (f in files.sortedBy { it.name }) {
                if (!f.name.endsWith(".csv")) continue
                val day = f.name.removeSuffix(".csv")
                if (day < from || day > to) continue
                val arr = JSONArray()
                var lastSeg = -1
                var lastLat = 0.0
                var lastLng = 0.0
                var pending: JSONArray? = null
                try {
                    f.forEachLine { line ->
                        val p = line.split(',')
                        if (p.size < 4) return@forEachLine
                        val seg = p[0].toIntOrNull() ?: return@forEachLine
                        val t = p[1].toLongOrNull() ?: return@forEachLine
                        val lat = p[2].toDoubleOrNull() ?: return@forEachLine
                        val lng = p[3].toDoubleOrNull() ?: return@forEachLine
                        val steps = p.getOrNull(5)?.toIntOrNull() ?: -1
                        val point = JSONArray().put(seg).put(t).put(lat).put(lng).put(steps)
                        var keep = seg != lastSeg
                        if (!keep) {
                            Location.distanceBetween(lastLat, lastLng, lat, lng, result)
                            keep = result[0] >= minGapM
                        }
                        if (keep) {
                            // Parca degisiyorsa bir onceki parcanin son noktasi
                            // (seyreltmede atlandiysa) eklenir; cizgi kisa kalmasin.
                            if (seg != lastSeg) pending?.let { arr.put(it) }
                            arr.put(point)
                            lastSeg = seg
                            lastLat = lat
                            lastLng = lng
                            pending = null
                        } else {
                            pending = point
                        }
                    }
                    pending?.let { arr.put(it) }
                } catch (e: Exception) {
                    continue
                }
                if (arr.length() > 0) out.put(day, arr)
            }
            return out
        }

        /** Telefonun "Konum" anahtari acik mi (kapaliysa GPS hic veri vermez). */
        fun locationOn(c: Context): Boolean =
            try {
                val lm = c.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                lm != null && LocationManagerCompat.isLocationEnabled(lm)
            } catch (e: Exception) {
                false
            }

        fun clearAll(c: Context) {
            dir(c).listFiles()?.forEach { it.delete() }
        }
    }

    private val client = LocationServices.getFusedLocationProviderClient(ctx)
    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    var active = false
        private set

    private var windowStart = 0L
    private var windowSteps = 0
    private var lastStepAt = 0L

    private var last: Location? = null
    private var lastDay = ""
    private var segment = 0

    private val buffer = StringBuilder()
    private var bufferDay = ""
    private var bufferCount = 0
    private var lastFlush = 0L

    // ---- Tanilama (Rota ekranindaki durum satiri) ----
    /** Son gelen konum (filtreden once): dogruluk ve zaman. */
    @Volatile var lastFixAccuracy = -1f
        private set
    @Volatile var lastFixAt = 0L
        private set
    @Volatile var lastFixLat = 0.0
        private set
    @Volatile var lastFixLng = 0.0
        private set
    /** Bugun kaydedilen / dogruluk yuzunden elenen nokta sayisi. */
    @Volatile var acceptedToday = 0
        private set
    @Volatile var rejectedToday = 0
        private set
    private var statsDay = ""

    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (loc in result.locations) onLocation(loc)
        }
    }

    /**
     * Yuruyus kaydi (baslat/bitir) acikken GPS adimlardan bagimsiz surekli
     * aciktir; durunca kapanmaz.
     */
    @Volatile var forced = false
        private set

    /** Sonraki kabul edilen nokta yeni parca baslatsin (yuruyus basladi). */
    private var newSegment = false

    fun setForced(on: Boolean) {
        forced = on
        if (on) {
            newSegment = true
            lastStepAt = SystemClock.elapsedRealtime()
            start()
        }
    }

    private val idleCheck = object : Runnable {
        override fun run() {
            if (!active) return
            if (forced) {
                flush()
                handler.postDelayed(this, IDLE_CHECK_MS)
                return
            }
            if (SystemClock.elapsedRealtime() - lastStepAt > IDLE_STOP_MS) {
                stop()
            } else {
                flush()
                handler.postDelayed(this, IDLE_CHECK_MS)
            }
        }
    }

    init {
        trimOld()
    }

    /** StepService her adim artisinda cagirir. */
    fun onSteps(delta: Int) {
        if (delta <= 0) return
        val now = SystemClock.elapsedRealtime()
        lastStepAt = now
        if (active) return
        if (!isEnabled(ctx) || !hasFine(ctx)) return
        // Telefonun Konum anahtari kapaliysa GPS hic veri vermez; "kaydediliyor"
        // gorunmesin diye hic baslatilmaz (uygulama bu anahtari kendisi acamaz).
        if (!locationOn(ctx)) return
        if (now - windowStart > START_WINDOW_MS) {
            windowStart = now
            windowSteps = 0
        }
        windowSteps += delta
        if (windowSteps >= START_STEPS) start()
    }

    /** Ayar kapatildiysa GPS hemen durur. */
    fun onSettingsChanged() {
        if (!isEnabled(ctx) || !hasFine(ctx)) {
            forced = false
            stop()
        }
    }

    @SuppressLint("MissingPermission")
    private fun start() {
        if (active) return
        try {
            val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 3_000L)
                .setMinUpdateIntervalMillis(1_000L)
                .setMinUpdateDistanceMeters(MIN_MOVE_M)
                // Ekran kapaliyken noktalar toplu teslim edilebilir (pil).
                .setMaxUpdateDelayMillis(10_000L)
                .setWaitForAccurateLocation(false)
                .build()
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
            active = true
            windowSteps = 0
            handler.removeCallbacks(idleCheck)
            handler.postDelayed(idleCheck, IDLE_CHECK_MS)
            onStateChanged()
        } catch (e: SecurityException) {
            active = false
        } catch (e: Exception) {
            active = false
        }
    }

    fun stop() {
        handler.removeCallbacks(idleCheck)
        if (active) {
            try {
                client.removeLocationUpdates(callback)
            } catch (e: Exception) {
            }
            active = false
            onStateChanged()
        }
        flush()
    }

    fun shutdown() = stop()

    private fun onLocation(loc: Location) {
        val time = if (loc.time > 0) loc.time else System.currentTimeMillis()
        val day = StepService.dayKey(time)
        if (day != statsDay) {
            statsDay = day
            acceptedToday = 0
            rejectedToday = 0
        }
        lastFixAccuracy = if (loc.hasAccuracy()) loc.accuracy else -1f
        lastFixAt = System.currentTimeMillis()
        lastFixLat = loc.latitude
        lastFixLng = loc.longitude
        if (loc.hasAccuracy() && loc.accuracy > MAX_ACCURACY_M) {
            rejectedToday++
            return
        }
        val prev = last
        var moved = 0.0
        if (prev != null && day == lastDay) {
            val dtMs = time - prev.time
            if (dtMs < 0) return
            val dist = prev.distanceTo(loc)
            if (dist < MIN_MOVE_M) return
            if (dtMs > 0 && dist / (dtMs / 1000f) > MAX_SPEED_MPS) {
                rejectedToday++
                return
            }
            if (newSegment || dtMs > SEGMENT_GAP_MS) {
                segment++
            } else {
                moved = dist.toDouble()
            }
            newSegment = false
        } else {
            newSegment = false
            // Ilk nokta ya da gun degisti: dosyadaki son parcanin devami.
            segment = lastSegmentInFile(day) + 1
        }
        if (bufferDay.isNotEmpty() && bufferDay != day) flush()
        bufferDay = day
        buffer.append(segment).append(',')
            .append(time).append(',')
            .append(String.format(Locale.US, "%.6f", loc.latitude)).append(',')
            .append(String.format(Locale.US, "%.6f", loc.longitude)).append(',')
            .append(if (loc.hasAccuracy()) Math.round(loc.accuracy) else -1).append(',')
            .append(stepsNow())
            .append('\n')
        bufferCount++
        acceptedToday++
        if (moved > 0) onDistance(moved)
        last = Location(loc).apply { this.time = time }
        lastDay = day
        val now = SystemClock.elapsedRealtime()
        if (bufferCount >= FLUSH_POINTS || now - lastFlush > FLUSH_MS) flush()
    }

    /** Bekleyen noktalari diske ekler. */
    @Synchronized
    fun flush() {
        lastFlush = SystemClock.elapsedRealtime()
        if (bufferCount == 0 || bufferDay.isEmpty()) return
        try {
            File(dir(ctx), "$bufferDay.csv").appendText(buffer.toString())
            buffer.setLength(0)
            bufferCount = 0
        } catch (e: Exception) {
            // Disk hatasi: tampon korunur, bir sonraki denemede yazilir.
        }
    }

    private fun lastSegmentInFile(day: String): Int {
        if (day == bufferDay && bufferCount > 0) return segment
        val f = File(dir(ctx), "$day.csv")
        if (!f.exists()) return -1
        return try {
            var seg = -1
            f.forEachLine { line ->
                line.substringBefore(',').toIntOrNull()?.let { if (it > seg) seg = it }
            }
            seg
        } catch (e: Exception) {
            -1
        }
    }

    private fun trimOld() {
        try {
            val files = dir(ctx).listFiles()?.filter { it.name.endsWith(".csv") } ?: return
            if (files.size <= KEEP_DAYS) return
            files.sortedBy { it.name }.take(files.size - KEEP_DAYS).forEach { it.delete() }
        } catch (e: Exception) {
        }
    }
}
