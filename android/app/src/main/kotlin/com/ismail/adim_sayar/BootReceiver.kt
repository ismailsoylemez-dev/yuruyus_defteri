package com.ismail.adim_sayar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Cihaz yeniden baslatildiginda servisi geri getirir. Aksi halde telefon
 * kapanip acildiktan sonra gun gecisi yine kacirilirdi.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        val p = StepService.prefs(context)
        if (!p.getBoolean(StepService.K_ENABLED, true)) return

        try {
            val service = Intent(context, StepService::class.java)
                .putExtra("goal", p.getInt(StepService.K_GOAL, 8000))
            ContextCompat.startForegroundService(context, service)
        } catch (e: Exception) {
            // Bazi surumlerde acilistan hemen sonra izin verilmez; uygulama
            // bir sonraki acilisinda zaten yeniden baslatilir.
        }
    }
}
