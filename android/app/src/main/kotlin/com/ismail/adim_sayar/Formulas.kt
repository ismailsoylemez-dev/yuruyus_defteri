package com.ismail.adim_sayar

/**
 * Native tarafin km / kcal / MET formullerinin TEK kaynagi.
 *
 * lib/utils/metrics.dart (Metrics) ve lib/utils/intensity.dart
 * (ActivityBreakdown.compute) ile birebir aynidir. Kalici bildirim ve
 * uygulama kapaliyken cizilen widget buradan hesaplar; boylece uygulama,
 * bildirim ve widget ayni gun icin ayni sayiyi gosterir.
 * Birini degistirirsen digerini de degistir: test/formulas_test.dart
 * ortak referans degerlerini tutar (172 cm, 93 kg):
 *   kcal(10000)            = 493.675   distanceKm(10000) = 7.138
 *   briskMet(120)          = 5.0       runMet(150)       = 10.1406
 *   breakdown(10000, 3000/25dk, 1500/10dk) = 7.6669 km, 622.18 kcal, 85 dk
 */
object Formulas {
    const val STEPS_PER_MINUTE = 110.0
    const val BRISK_MIN_CADENCE = 100
    const val RUN_MIN_CADENCE = 140
    private const val MIN_SPEED_KMH = 1.5
    private const val MAX_SPEED_KMH = 7.5

    class DayMetrics(val km: Double, val kcal: Double, val minutes: Int)

    /**
     * GPS ile olculen adim boyu (m). Doluysa boydan tahminin yerine gecer
     * (Dart'taki Metrics.strideOverrideM ile ayni; Flutter "setStride" ile yazar).
     */
    @Volatile
    var strideOverrideM: Double? = null

    fun strideMeters(heightCm: Int): Double = strideOverrideM ?: heightCm * 0.415 / 100.0

    fun runStrideMeters(heightCm: Int): Double = heightCm * 0.62 / 100.0

    fun distanceKm(steps: Int, heightCm: Int): Double =
        steps * strideMeters(heightCm) / 1000.0

    fun activeMinutes(steps: Int): Int = Math.round(steps / STEPS_PER_MINUTE).toInt()

    fun metForSpeed(kmh: Double): Double = when {
        kmh <= 0 -> 0.0
        kmh < 3.2 -> 2.8
        kmh < 4.0 -> 3.0
        kmh < 4.8 -> 3.5
        kmh < 5.6 -> 4.3
        kmh < 6.4 -> 5.0
        kmh < 8.0 -> 7.0
        else -> 9.8
    }

    fun kcal(steps: Int, heightCm: Int, weightKg: Double, activeMin: Int?): Double {
        if (steps <= 0) return 0.0
        val m = if (activeMin != null && activeMin > 0) activeMin else activeMinutes(steps)
        if (m <= 0) return 0.0
        val hours = m / 60.0
        val speed = (distanceKm(steps, heightCm) / hours).coerceIn(MIN_SPEED_KMH, MAX_SPEED_KMH)
        return metForSpeed(speed) * weightKg * hours
    }

    fun briskMet(cadence: Double, heightCm: Int): Double {
        val byCadence = 3.0 + (cadence - BRISK_MIN_CADENCE) * 0.1
        val kmh = cadence * strideMeters(heightCm) * 60.0 / 1000.0
        return maxOf(byCadence, metForSpeed(kmh)).coerceIn(3.0, 8.0)
    }

    fun runMet(cadence: Double, heightCm: Int): Double {
        val speed = (cadence * runStrideMeters(heightCm)).coerceIn(100.0, 300.0)
        return (0.2 * speed + 3.5) / 3.5
    }

    /**
     * ActivityBreakdown.compute ile ayni: normal + tempolu + kosu.
     * [briskSteps]/[runSteps] cagiran tarafta gunun toplamina kirpilmis olmali.
     */
    fun breakdown(
        totalSteps: Int,
        briskSteps: Int,
        briskMin: Int,
        runSteps: Int,
        runMin: Int,
        hasData: Boolean,
        heightCm: Int,
        weightKg: Double,
        activeMin: Int?,
    ): DayMetrics {
        val h = heightCm
        val w = weightKg
        if (!hasData || (briskSteps <= 0 && runSteps <= 0)) {
            return DayMetrics(
                distanceKm(totalSteps, h),
                kcal(totalSteps, h, w, activeMin),
                activeMin ?: activeMinutes(totalSteps)
            )
        }
        val rs = if (runMin > 0) runSteps else 0
        val bs = if (briskMin > 0) briskSteps else 0
        val ns = maxOf(0, totalSteps - bs - rs)

        var normalMin: Int? = null
        if (activeMin != null && ns > 0) {
            val rest = activeMin - briskMin - runMin
            val lo = Math.ceil(ns / 130.0).toInt()
            val hi = Math.ceil(ns / 60.0).toInt()
            if (rest in lo..hi) normalMin = rest
        }

        var km = distanceKm(ns, h)
        var kcal = kcal(ns, h, w, normalMin)
        var minutes = normalMin ?: activeMinutes(ns)
        if (bs > 0) {
            km += distanceKm(bs, h)
            kcal += briskMet(bs.toDouble() / briskMin, h) * w * briskMin / 60.0
            minutes += briskMin
        }
        if (rs > 0) {
            km += rs * runStrideMeters(h) / 1000.0
            kcal += runMet(rs.toDouble() / runMin, h) * w * runMin / 60.0
            minutes += runMin
        }
        return DayMetrics(km, kcal, minutes)
    }
}
