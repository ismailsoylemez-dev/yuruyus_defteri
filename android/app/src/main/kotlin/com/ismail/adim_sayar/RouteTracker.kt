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
 * Rota kaydi. Iki mod:
 *  - Antrenman (forced): "Antrenmani Baslat" ile GPS surekli acik; yalniz
 *    uygulama on plandayken baslatilir, arka plan konum izni gerekmez.
 *  - Otomatik rota (istege bagli, varsayilan kapali): adim olaylarinin
 *    GERCEK zamanina bakilir; son [AUTO_WINDOW_MS] icinde en az [AUTO_STEPS]
 *    adim ve yuruyus en az [AUTO_SPAN_MS] suruyorsa GPS acilir, [IDLE_STOP_MS]
 *    adimsiz kalinca kapanir. Olcum seyrek ve toplu teslimli (pil).
 *
 * Eski surum yalnizca 60 sn'den taze adim olaylarini sayiyordu; ekran
 * kapaliyken sensor olaylari toplu/gecikmeli geldigi icin esik hic
 * dolmuyor ve GPS hic acilmiyordu. Artik olay zamani kullaniliyor.
 *
 * Kayit: filesDir/routes/yyyy-MM-dd.csv
 *   satir = parca,zamanMs,enlem,boylam,dogrulukM,adim
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
        /** Eski anahtar (her antrenmanda true yaziliyordu); artik okunmaz. */
        const val K_ROUTE_ENABLED_LEGACY = "routeEnabled"

        /** Otomatik rota (arka planda yururken iz) acik mi. Varsayilan kapali. */
        const val K_ROUTE_ENABLED = "routeAutoV2"
        private const val DIR = "routes"

        // ---- Otomatik mod tetigi (olay zamanina gore) ----
        private const val AUTO_WINDOW_MS = 120_000L
        private const val AUTO_STEPS = 160
        private const val AUTO_SPAN_MS = 90_000L
        /** Son adim bundan eskiyse "su an yurumuyor" sayilir. */
        private const val FRESH_MS = 45_000L

        /** Otomatik modda bu kadar adimsiz kalinca GPS kapanir. */
        private const val IDLE_STOP_MS = 90_000L
        /** Antrenmanda uzun mola (5 dk) GPS'i kapatir; adim gelince geri acilir. */
        private const val WORKOUT_IDLE_STOP_MS = 300_000L
        private const val IDLE_CHECK_MS = 15_000L

        /** Bundan uzun bosluk yeni parca baslatir. */
        private const val SEGMENT_GAP_MS = 300_000L

        /** Bundan kotu dogruluktaki konum atilir (bina ici sicramalar). */
        const val MAX_ACCURACY_M = 50f

        /** Antrenmanda 2 m, otomatik modda 5 m yer degistirme kaydedilir. */
        private const val MIN_MOVE_WORKOUT_M = 2f
        private const val MIN_MOVE_AUTO_M = 5f

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

        /**
         * Kisisel isi haritasi: tum gunlerin rotalari ~[cellM] m'lik karelere
         * bolunur; her kare gecisinin (kenarin) kac FARKLI gunde yuruldugu
         * sayilir. Ayni kenar bir kez cizilir; ardisik ve ayni seviyedeki
         * kenarlar tek cizgide birlesir (harita binlerce parcayla yorulmasin).
         *
         * [privacyM] > 0 ise en sik baslanan/bitirilen kare "ev" sayilir ve
         * cevresindeki [privacyM] metre cizilmez.
         *
         * Donus: { lines: [[seviye, lat, lng, lat, lng, ...], ...],
         *          days, km, maxCount, home: [lat, lng]? }
         * seviye: 0 = 1 gun, 1 = 2-4, 2 = 5-9, 3 = 10+ gun.
         */
        fun heatmap(
            c: Context,
            cellM: Double,
            privacyM: Double,
            from: String = "0000-00-00",
            to: String = "9999-99-99"
        ): JSONObject {
            val files = (dir(c).listFiles() ?: emptyArray())
                .filter { it.name.endsWith(".csv") }
                .filter { val d = it.name.removeSuffix(".csv"); d >= from && d <= to }
                .sortedBy { it.name }
            val out = JSONObject()
            val lines = JSONArray()
            out.put("lines", lines)
            if (files.isEmpty()) {
                out.put("days", 0); out.put("km", 0.0); out.put("maxCount", 0)
                return out
            }

            // Gun gun seyreltilmis parcalar: her parca DoubleArray(lat, lng, ...)
            fun readThinned(f: File): List<DoubleArray> {
                val segs = mutableListOf<DoubleArray>()
                var cur = ArrayList<Double>()
                var lastSeg = Int.MIN_VALUE
                var lastLat = 0.0
                var lastLng = 0.0
                val res = FloatArray(1)
                try {
                    f.forEachLine { line ->
                        val p = line.split(',')
                        if (p.size < 4) return@forEachLine
                        val seg = p[0].toIntOrNull() ?: return@forEachLine
                        val lat = p[2].toDoubleOrNull() ?: return@forEachLine
                        val lng = p[3].toDoubleOrNull() ?: return@forEachLine
                        if (seg != lastSeg) {
                            if (cur.size >= 4) segs.add(cur.toDoubleArray())
                            cur = ArrayList()
                            cur.add(lat); cur.add(lng)
                            lastSeg = seg; lastLat = lat; lastLng = lng
                            return@forEachLine
                        }
                        Location.distanceBetween(lastLat, lastLng, lat, lng, res)
                        if (res[0] >= cellM / 2) {
                            cur.add(lat); cur.add(lng)
                            lastLat = lat; lastLng = lng
                        }
                    }
                } catch (e: Exception) {
                }
                if (cur.size >= 4) segs.add(cur.toDoubleArray())
                return segs
            }

            val all = files.map { readThinned(it) }
            val first = all.firstOrNull { it.isNotEmpty() }?.first()
            if (first == null) {
                out.put("days", 0); out.put("km", 0.0); out.put("maxCount", 0)
                return out
            }
            val lat0 = first[0]
            val dLat = cellM / 111_320.0
            val dLng = cellM / (111_320.0 * Math.cos(Math.toRadians(lat0)).coerceAtLeast(0.2))
            fun cell(lat: Double, lng: Double): Long {
                val y = Math.floor(lat / dLat).toLong()
                val x = Math.floor(lng / dLng).toLong()
                return (y shl 32) xor (x and 0xffffffffL)
            }
            fun edge(a: Long, b: Long): Pair<Long, Long> = if (a < b) a to b else b to a

            // 1) Kenar basina farkli gun sayisi + ev tahmini (uc noktalar)
            val counts = HashMap<Pair<Long, Long>, Int>()
            val ends = HashMap<Long, Int>()
            val endPos = HashMap<Long, DoubleArray>()
            var days = 0
            for (segs in all) {
                if (segs.isEmpty()) continue
                days++
                val seen = HashSet<Pair<Long, Long>>()
                for (arr in segs) {
                    val n = arr.size / 2
                    for (k in intArrayOf(0, n - 1)) {
                        val cc = cell(arr[k * 2], arr[k * 2 + 1])
                        ends[cc] = (ends[cc] ?: 0) + 1
                        endPos.getOrPut(cc) { doubleArrayOf(arr[k * 2], arr[k * 2 + 1]) }
                    }
                    var prev = cell(arr[0], arr[1])
                    for (i in 1 until n) {
                        val cc = cell(arr[i * 2], arr[i * 2 + 1])
                        if (cc == prev) continue
                        val e = edge(prev, cc)
                        if (seen.add(e)) counts[e] = (counts[e] ?: 0) + 1
                        prev = cc
                    }
                }
            }

            var home: DoubleArray? = null
            if (privacyM > 0) {
                ends.maxByOrNull { it.value }?.let { if (it.value >= 3) home = endPos[it.key] }
            }
            val res = FloatArray(1)
            fun hidden(lat: Double, lng: Double): Boolean {
                val h = home ?: return false
                Location.distanceBetween(h[0], h[1], lat, lng, res)
                return res[0] < privacyM
            }
            fun level(n: Int): Int = when {
                n >= 10 -> 3
                n >= 5 -> 2
                n >= 2 -> 1
                else -> 0
            }

            // 2) Cizgiler: her kenar bir kez, ayni seviyede ardisik kenarlar birlesir.
            val emitted = HashSet<Pair<Long, Long>>()
            var km = 0.0
            var maxCount = 0
            for (segs in all) {
                for (arr in segs) {
                    val n = arr.size / 2
                    var line: JSONArray? = null
                    var lineLevel = -1
                    var prevCell = cell(arr[0], arr[1])
                    for (i in 1 until n) {
                        val aLat = arr[(i - 1) * 2]; val aLng = arr[(i - 1) * 2 + 1]
                        val bLat = arr[i * 2]; val bLng = arr[i * 2 + 1]
                        val cc = cell(bLat, bLng)
                        val e = if (cc == prevCell) null else edge(prevCell, cc)
                        prevCell = cc
                        val skip = e == null || !emitted.add(e) ||
                            hidden(aLat, aLng) || hidden(bLat, bLng)
                        if (skip) {
                            if (e != null) {
                                // Ayni kenar daha once cizildi / gizli: cizgi kesilir.
                                line = null
                            }
                            continue
                        }
                        val cnt = counts[e!!] ?: 1
                        if (cnt > maxCount) maxCount = cnt
                        val lv = level(cnt)
                        Location.distanceBetween(aLat, aLng, bLat, bLng, res)
                        km += res[0] / 1000.0
                        val l = line
                        if (l != null && lv == lineLevel) {
                            l.put(round5(bLat)).put(round5(bLng))
                        } else {
                            val nl = JSONArray().put(lv)
                                .put(round5(aLat)).put(round5(aLng))
                                .put(round5(bLat)).put(round5(bLng))
                            lines.put(nl)
                            line = nl
                            lineLevel = lv
                        }
                    }
                }
            }
            out.put("days", days)
            out.put("km", Math.round(km * 10) / 10.0)
            out.put("maxCount", maxCount)
            home?.let { out.put("home", JSONArray().put(round5(it[0])).put(round5(it[1]))) }
            return out
        }

        /**
         * Buluttan gelen gunu cihaza yazar (yeni telefon / yeniden kurulum).
         * Gunun dosyasi zaten varsa dokunulmaz. [csv]: "parca,zaman,enlem,boylam" satirlari.
         */
        fun importDay(c: Context, day: String, csv: String): Boolean {
            if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(day)) return false
            val f = File(dir(c), "$day.csv")
            if (f.exists() && f.length() > 0) return false
            return try {
                f.writeText(csv)
                true
            } catch (e: Exception) {
                false
            }
        }

        private fun round5(v: Double): Double = Math.round(v * 100_000.0) / 100_000.0

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

    /** Otomatik mod icin son adim olaylari: (olay zamani ms, adim). */
    private val recent = ArrayDeque<Pair<Long, Int>>()
    /** Son adimin duvar saati (ms); olay zamanina gore. */
    private var lastStepWall = 0L

    /** GPS neden kapali / acik (Rota ekraninda gosterilir). */
    @Volatile var reason = ""
        private set
    /** Son 2 dk'daki adim (otomatik tetik ilerlemesi). */
    @Volatile var windowSteps = 0
        private set

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

    /** Antrenman acikken GPS adimlardan bagimsiz aciktir. */
    @Volatile var forced = false
        private set

    /** Su anki istek antrenman ayariyla mi acildi (mod degisince yeniden kurulur). */
    private var requestIsWorkout = false

    /** Sonraki kabul edilen nokta yeni parca baslatsin (yuruyus basladi). */
    private var newSegment = false

    fun setForced(on: Boolean) {
        forced = on
        lastStepWall = System.currentTimeMillis()
        if (on) {
            newSegment = true
            restart()
        } else if (active) {
            // Antrenman bitti: otomatik mod kapaliysa GPS kapanir,
            // aciksa seyrek ayara gecer.
            if (autoAllowed()) restart() else stop()
        }
        updateReason()
    }

    private val idleCheck = object : Runnable {
        override fun run() {
            if (!active) return
            val limit = if (forced) WORKOUT_IDLE_STOP_MS else IDLE_STOP_MS
            if (System.currentTimeMillis() - lastStepWall > limit) {
                stop()
            } else {
                flush()
                handler.postDelayed(this, IDLE_CHECK_MS)
            }
        }
    }

    init {
        trimOld()
        updateReason()
    }

    /** Otomatik mod baslayabilir mi (izin + konum + arka plan kosulu). */
    private fun autoAllowed(): Boolean =
        isEnabled(ctx) && hasFine(ctx) && locationOn(ctx) &&
            (StepService.appInForeground || hasBackground(ctx))

    /**
     * StepService her adim artisinda cagirir. [eventWallMs]: olayin gercek
     * zamani (toplu teslimde gecmiste olabilir).
     */
    fun onSteps(delta: Int, eventWallMs: Long = System.currentTimeMillis()) {
        if (delta <= 0) return
        val now = System.currentTimeMillis()
        val t = if (eventWallMs in (now - 6 * 3_600_000L)..now) eventWallMs else now
        if (t > lastStepWall) lastStepWall = t

        if (forced) {
            if (!active && hasFine(ctx) && locationOn(ctx)) restart()
            return
        }
        recent.addLast(t to delta)
        while (recent.isNotEmpty() && recent.first().first < now - AUTO_WINDOW_MS) recent.removeFirst()
        windowSteps = recent.sumOf { it.second }
        if (active) return
        if (!autoAllowed()) {
            updateReason()
            return
        }
        val span = if (recent.isEmpty()) 0L else recent.last().first - recent.first().first
        val fresh = now - lastStepWall <= FRESH_MS
        if (windowSteps >= AUTO_STEPS && span >= AUTO_SPAN_MS && fresh) {
            newSegment = true
            restart()
        } else {
            updateReason()
        }
    }

    /** Ayar/izin degisti. */
    fun onSettingsChanged() {
        if (!hasFine(ctx)) {
            forced = false
            stop()
        } else if (!forced && active && !autoAllowed()) {
            stop()
        }
        updateReason()
    }

    private fun updateReason() {
        reason = when {
            !hasFine(ctx) -> "Konum izni yok"
            !locationOn(ctx) -> "Telefonun Konum özelliği kapalı"
            forced && active -> "Antrenman kaydı"
            forced -> "Antrenman: hareket bekleniyor"
            active -> "Otomatik rota kaydediliyor"
            !isEnabled(ctx) -> "Otomatik rota kapalı · GPS sadece antrenmanda"
            !StepService.appInForeground && !hasBackground(ctx) ->
                "Arka plan konum izni yok · uygulama kapalıyken otomatik rota çalışmaz"
            else -> "Otomatik rota · yürüyüş bekleniyor ($windowSteps/$AUTO_STEPS adım)"
        }
    }

    @SuppressLint("MissingPermission")
    private fun restart() {
        val workout = forced
        if (active && requestIsWorkout == workout) return
        if (active) {
            try { client.removeLocationUpdates(callback) } catch (e: Exception) {}
            active = false
        }
        try {
            val request = if (workout) {
                LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2_000L)
                    .setMinUpdateIntervalMillis(1_000L)
                    .setMinUpdateDistanceMeters(MIN_MOVE_WORKOUT_M)
                    .setMaxUpdateDelayMillis(4_000L)
                    .setWaitForAccurateLocation(false)
                    .build()
            } else {
                // Otomatik: 5 sn aralik, 30 sn'ye kadar toplu teslim (CPU az uyanir).
                LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
                    .setMinUpdateIntervalMillis(3_000L)
                    .setMinUpdateDistanceMeters(MIN_MOVE_AUTO_M)
                    .setMaxUpdateDelayMillis(30_000L)
                    .setWaitForAccurateLocation(false)
                    .build()
            }
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
            active = true
            requestIsWorkout = workout
            recent.clear()
            windowSteps = 0
            handler.removeCallbacks(idleCheck)
            handler.postDelayed(idleCheck, IDLE_CHECK_MS)
        } catch (e: SecurityException) {
            active = false
            reason = "Konum izni reddedildi"
        } catch (e: Exception) {
            active = false
            reason = "GPS başlatılamadı: ${e.javaClass.simpleName}"
        }
        if (active) updateReason()
        onStateChanged()
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
        updateReason()
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
            if (dist < (if (requestIsWorkout) MIN_MOVE_WORKOUT_M else MIN_MOVE_AUTO_M)) return
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
