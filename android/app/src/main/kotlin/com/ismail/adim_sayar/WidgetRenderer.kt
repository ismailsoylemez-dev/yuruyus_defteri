package com.ismail.adim_sayar

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Ana ekran widget'inin native cizimi.
 *
 * Normalde widget'i Flutter tarafi (HomeWidgetView) PNG olarak ciziyor; ama
 * uygulama kapaliyken Flutter motoru calismadigi icin widget son acilistaki
 * sayida donup kaliyordu. Bu sinif ayni tasarimi (olculer, renkler, ikonlar,
 * hesaplar) Canvas ile tekrarlar; servis uygulama kapaliyken bunu kullanir.
 *
 * Olculer HomeWidgetView ile ayni mantiksal birimdedir (360x168) ve Flutter
 * tarafindaki pixelRatio: 3 ile ayni SCALE'le piksele cevrilir. Hesaplar
 * (km, kcal, sure, bicimler) lib/utils/metrics.dart ile birebirdir.
 */
object WidgetRenderer {
    private const val W = 360f
    private const val H = 168f
    private const val SCALE = 3f

    // lib/theme/app_theme.dart -> AppColors ile ayni.
    private val BG = Color.parseColor("#0D0F14")
    private val SURFACE_ALT = Color.parseColor("#1E232E")
    private val ACCENT = Color.parseColor("#4ADE80")
    private val BEST = Color.parseColor("#FFA726")
    private val TEXT = Color.parseColor("#F1F4F9")
    private val TEXT_DIM = Color.parseColor("#8A93A6")
    private val DIVIDER = Color.parseColor("#232937")
    private val BLUE = Color.parseColor("#42A5F5")
    private val GREEN = Color.parseColor("#66BB6A")

    // Uygulamadaki MetricColors ile ayni (lib/theme/app_theme.dart).
    private val C_KM = Color.parseColor("#38BDF8")
    private val C_KCAL = Color.parseColor("#FF7043")
    private val C_WATER = Color.parseColor("#3B82F6")
    private val C_TIME = Color.parseColor("#A78BFA")

    // Flutter Icons kod noktalari (APK icindeki MaterialIcons fontundan dogrulandi).
    private const val IC_WALK = 0xe1e1
    private const val IC_DIST = 0xe60e // Icons.straighten (mesafe)
    private const val IC_FIRE = 0xe392
    private const val IC_SCHEDULE = 0xe556
    private const val IC_WATER = 0xe6a4

    private val WEEKDAY = arrayOf("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz")

    private var iconFont: Typeface? = null
    private var iconFontTried = false

    private data class Cell(val icon: Int, val color: Int, val value: String, val label: String)

    /** Flutter'in kendi ikon fontu; bulunamazsa ikonlar cizilmez, gerisi cizilir. */
    private fun iconTypeface(context: Context): Typeface? {
        if (!iconFontTried) {
            iconFontTried = true
            iconFont = try {
                Typeface.createFromAsset(
                    context.assets,
                    "flutter_assets/fonts/MaterialIcons-Regular.otf"
                )
            } catch (e: Exception) {
                null
            }
        }
        return iconFont
    }

    private fun typefaceOf(w: Int): Typeface =
        if (Build.VERSION.SDK_INT >= 28) {
            Typeface.create(Typeface.DEFAULT, w, false)
        } else if (w >= 600) {
            Typeface.DEFAULT_BOLD
        } else {
            Typeface.DEFAULT
        }

    private fun textPaint(size: Float, color: Int, w: Int): Paint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.textSize = size
            this.color = color
            this.typeface = typefaceOf(w)
            this.textAlign = Paint.Align.CENTER
        }

    /** Flutter'da height verilmemis metnin satir yuksekligi. */
    private fun naturalHeight(p: Paint): Float {
        val fm = p.fontMetrics
        return fm.descent - fm.ascent
    }

    /**
     * Metni, ust kenari [top] ve satir yuksekligi [lineH] olan kutuya
     * yatayda [cx] merkezli cizer. Flutter'in varsayilan (orantili) satir
     * araligi dagilimiyla ayni taban cizgisini kullanir.
     */
    private fun drawText(c: Canvas, s: String, p: Paint, cx: Float, top: Float, lineH: Float) {
        val fm = p.fontMetrics
        val natural = fm.descent - fm.ascent
        val baseline = top + (-fm.ascent) * lineH / natural
        c.drawText(s, cx, baseline, p)
    }

    private fun drawIcon(c: Canvas, tf: Typeface, code: Int, size: Float, color: Int, cx: Float, top: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.typeface = tf
            this.textSize = size
            this.color = color
            this.textAlign = Paint.Align.CENTER
        }
        drawText(c, String(Character.toChars(code)), p, cx, top, size)
    }

    private fun alpha(color: Int, a: Float): Int =
        Color.argb((a * 255f).roundToInt(), Color.red(color), Color.green(color), Color.blue(color))

    fun render(
        context: Context,
        steps: Int,
        goal: Int,
        km: Double,
        kcal: Double,
        minutes: Int,
        week: IntArray,
        todayIndex: Int,
        /** null: su takibi kapali, su hucresi cizilmez (3 hucre esit yayilir). */
        waterMl: Int?,
    ): Bitmap {
        val bmp = Bitmap.createBitmap(
            (W * SCALE).toInt(),
            (H * SCALE).toInt(),
            Bitmap.Config.ARGB_8888
        )
        val c = Canvas(bmp)
        c.scale(SCALE, SCALE)
        val icons = iconTypeface(context)

        // Arka plan: BoxDecoration(color: bg, radius 26, border 1.2 divider)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = BG }
        c.drawRoundRect(RectF(0f, 0f, W, H), 26f, 26f, fill)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            this.strokeWidth = 1.2f
            this.color = DIVIDER
        }
        c.drawRoundRect(RectF(0.6f, 0.6f, W - 0.6f, H - 0.6f), 25.4f, 25.4f, border)

        // ---- Halka: 104x104, dikeyde ortali, sol pay 18 ----
        val ringLeft = 18f
        val ringTop = (H - 104f) / 2f
        val cx = ringLeft + 52f
        val cy = ringTop + 52f
        val stroke = 9f
        val radius = (104f - stroke) / 2f
        val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            this.strokeWidth = stroke
            this.strokeCap = Paint.Cap.ROUND
            this.color = SURFACE_ALT
        }
        c.drawCircle(cx, cy, radius, ringPaint)
        val progress = if (goal <= 0) 0f else (steps.toFloat() / goal).coerceIn(0f, 1f)
        if (progress > 0f) {
            ringPaint.color = ACCENT
            c.drawArc(
                RectF(cx - radius, cy - radius, cx + radius, cy + radius),
                -90f, 360f * progress, false, ringPaint
            )
        }

        // Halka ici: ikon(17) + 2 + adim(22, height 1.1) + hedef(10.5)
        val stepsPaint = textPaint(22f, TEXT, 800).apply { this.letterSpacing = -0.6f / 22f }
        val goalPaint = textPaint(10.5f, TEXT_DIM, 400)
        val stepsLine = 22f * 1.1f
        val goalLine = naturalHeight(goalPaint)
        var y = cy - (17f + 2f + stepsLine + goalLine) / 2f
        if (icons != null) drawIcon(c, icons, IC_WALK, 17f, ACCENT, cx, y)
        y += 17f + 2f
        drawText(c, thousands(steps), stepsPaint, cx, y, stepsLine)
        y += stepsLine
        drawText(c, "/ ${compact(goal)}", goalPaint, cx, y, goalLine)

        // ---- Sag taraf: haftalik cubuklar + Km/Kcal/Sure ----
        val left = ringLeft + 104f + 18f
        val right = W - 18f
        val width = right - left
        val valuePaint = textPaint(13.5f, TEXT, 800)
        val labelPaint = textPaint(9f, TEXT_DIM, 400)
        val valueLine = 13.5f * 1.1f
        val labelLine = naturalHeight(labelPaint)
        val contentH = 58f + 12f + (13f + 3f + valueLine + labelLine)
        val top = 16f + ((H - 32f) - contentH) / 2f

        val colW = width / 7f
        val maxVal = maxOf(goal, week.maxOrNull() ?: 0)
        val labelTop = top + 58f - 9.5f
        val barBottom = labelTop - 5f
        val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        for (i in 0 until 7) {
            val v = week.getOrElse(i) { 0 }
            val ratio = if (maxVal == 0) 0f else v.toFloat() / maxVal
            val bh = (40f * ratio).coerceIn(3f, 40f)
            val isToday = i == todayIndex
            val reached = goal > 0 && v >= goal
            barPaint.color = when {
                isToday -> ACCENT
                reached -> alpha(ACCENT, 0.75f)
                v > 0 -> alpha(ACCENT, 0.32f)
                else -> SURFACE_ALT
            }
            val x0 = left + colW * i + 3.5f
            val x1 = left + colW * (i + 1) - 3.5f
            c.drawRoundRect(RectF(x0, barBottom - bh, x1, barBottom), 5f, 5f, barPaint)
            val dayPaint = textPaint(9.5f, if (isToday) ACCENT else TEXT_DIM, if (isToday) 800 else 500)
            drawText(c, WEEKDAY[i], dayPaint, (x0 + x1) / 2f, labelTop, 9.5f)
        }

        // km / kcal / sure cagiran taraftan (Formulas.breakdown) gelir.
        val cells = listOfNotNull(
            Cell(IC_DIST, C_KM, String.format(Locale.US, "%.2f", km), "Km"),
            Cell(IC_FIRE, C_KCAL, String.format(Locale.US, "%.0f", kcal), "Kcal"),
            waterMl?.let {
                Cell(IC_WATER, C_WATER, if (it >= 1000) String.format(Locale.US, "%.1f", it / 1000.0) + "L" else "${it}ml", "Su")
            },
            Cell(IC_SCHEDULE, C_TIME, duration(minutes), "Süre"),
        )
        // Row(spaceBetween): hucre genisligi = en genis icerik
        val widths = cells.map {
            maxOf(13f, valuePaint.measureText(it.value), labelPaint.measureText(it.label))
        }
        // spaceBetween: hucreler arasi (n - 1) bosluk. Eskiden sabit 2'ye
        // bolunuyordu; 4 hucrede son hucre sag kenardan tasiyordu.
        val gap = (width - widths.sum()) / maxOf(1, cells.size - 1).toFloat()
        val cellTop = top + 58f + 12f
        var x = left
        cells.forEachIndexed { i, cell ->
            val center = x + widths[i] / 2f
            var cyy = cellTop
            if (icons != null) drawIcon(c, icons, cell.icon, 13f, cell.color, center, cyy)
            cyy += 13f + 3f
            drawText(c, cell.value, valuePaint, center, cyy, valueLine)
            cyy += valueLine
            drawText(c, cell.label, labelPaint, center, cyy, labelLine)
            x += widths[i] + gap
        }
        return bmp
    }

    // Formuller Formulas.kt'de; burada yalnizca bicimlendirme.

    fun duration(minutes: Int): String {
        if (minutes < 60) return "$minutes dk"
        val h = minutes / 60
        val m = minutes % 60
        return if (m == 0) "$h sa" else "$h sa $m dk"
    }

    private fun thousands(v: Int): String {
        val s = v.toString()
        val b = StringBuilder()
        for (i in s.indices) {
            if (i > 0 && (s.length - i) % 3 == 0) b.append('.')
            b.append(s[i])
        }
        return b.toString()
    }

    private fun compact(v: Int): String {
        if (v < 1000) return v.toString()
        val k = v / 1000.0
        val s = if (k >= 10) String.format(Locale.US, "%.0f", k) else String.format(Locale.US, "%.1f", k)
        return s.replace('.', ',') + "b"
    }
}
