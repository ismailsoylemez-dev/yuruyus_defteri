package com.ismail.adim_sayar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject
import java.util.Locale

/**
 * Ana ekran widget'i. Gorsel uygulama (Flutter) ya da uygulama kapaliyken
 * StepService tarafindan PNG olarak cizilir; burada yalnizca yerlestirilir.
 *
 * Sagdaki "su ekle" seridi uygulamayi acmadan 250 ml ekler. Su takibi
 * kapaliysa serit gizlenir.
 */
class StepWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_ADD_WATER = "com.ismail.adim_sayar.WIDGET_ADD_WATER"
        private const val IMAGE_KEY = "stepWidgetImage"
        private const val WATER_STEP_ML = 250

        fun refreshAll(c: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(c)
                val ids = mgr.getAppWidgetIds(ComponentName(c, StepWidgetProvider::class.java))
                for (id in ids) update(c, mgr, id)
            } catch (e: Exception) {
            }
        }

        fun update(c: Context, mgr: AppWidgetManager, id: Int) {
            val views = RemoteViews(c.packageName, R.layout.step_widget)

            val path = try {
                HomeWidgetPlugin.getData(c).getString(IMAGE_KEY, null)
            } catch (e: Exception) {
                null
            }
            val bmp = path?.let {
                try {
                    BitmapFactory.decodeFile(it)
                } catch (e: Exception) {
                    null
                }
            }
            if (bmp != null) {
                views.setImageViewBitmap(R.id.widget_image, bmp)
                views.setViewVisibility(R.id.widget_placeholder, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_placeholder, View.VISIBLE)
            }

            // Widget'a dokununca uygulama acilir.
            c.packageManager.getLaunchIntentForPackage(c.packageName)?.let { open ->
                open.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        c, 10, open,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }

            val waterOn = StepService.waterEnabled(c)
            views.setViewVisibility(R.id.widget_water_add, if (waterOn) View.VISIBLE else View.GONE)
            if (waterOn) {
                val add = Intent(c, StepWidgetProvider::class.java).setAction(ACTION_ADD_WATER)
                views.setOnClickPendingIntent(
                    R.id.widget_water_add,
                    PendingIntent.getBroadcast(
                        c, 11, add,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }
            mgr.updateAppWidget(id, views)
        }

        /** Flutter'in su kaydina (flutter.water_json) ekler; yeni gunluk toplami doner. */
        fun addWater(c: Context, ml: Int): Int {
            val p = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val json = try {
                JSONObject(p.getString("flutter.water_json", null) ?: "{}")
            } catch (e: Exception) {
                JSONObject()
            }
            val day = StepService.dayKey()
            val total = (json.optInt(day, 0) + ml).coerceIn(0, 20_000)
            json.put(day, total)
            p.edit().putString("flutter.water_json", json.toString()).apply()
            return total
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) update(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_ADD_WATER) return
        if (!StepService.waterEnabled(context)) return
        val total = addWater(context, WATER_STEP_ML)
        val liters = String.format(Locale("tr", "TR"), "%.2f", total / 1000.0)
        Toast.makeText(context, "+$WATER_STEP_ML ml su · bugün $liters L", Toast.LENGTH_SHORT).show()
        // Servis calisiyorsa widget'i yeni su degeriyle yeniden cizer.
        val svc = StepService.instance
        if (svc != null) svc.onWaterChanged() else refreshAll(context)
    }
}
