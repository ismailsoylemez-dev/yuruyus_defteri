package com.ismail.adim_sayar

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.common.api.ResolvableApiException

/**
 * TYPE_STEP_COUNTER'i gecikmesiz dinler.
 *
 * Hazir eklentiler bu sensoru varsayilan gecikmeyle ve toplu raporlamayla
 * kaydeder; olaylar 10-30 saniyede bir, birikmis halde gelir. Burada
 * SENSOR_DELAY_FASTEST ve maxReportLatencyUs = 0 kullanilir: on-change tipi
 * olan bu sensor her degisimde, yani her adimda olay uretir.
 *
 * Yayinlanan deger cihaz acilisindan beri toplam adim sayisidir (kumulatif),
 * tek dogru kaynaktir; arayuz ayri bir tahmin yurutmez.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "adim_sayar/step_counter"
    private val serviceChannelName = "adim_sayar/service"
    private val main = Handler(Looper.getMainLooper())

    /** "Konumu ac" sistem penceresinin sonucu bekleyen cagri. */
    private var pendingLocationOn: MethodChannel.Result? = null
    private val reqLocationOn = 7301

    private var sink: EventChannel.EventSink? = null
    private var sensorManager: SensorManager? = null
    private var listener: SensorEventListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    register()
                }

                override fun onCancel(arguments: Any?) {
                    unregister()
                    sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, serviceChannelName)
            .setMethodCallHandler { call, result -> handleService(call.method, call.arguments, result) }
    }

    /**
     * Arka plan servisinin kontrolu. Servis Dart calistirmadigi icin
     * baslatirken beklenecek bir el sikisma yoktur; basarisizlik yalnizca
     * sistemin servisi reddetmesi halinde olusur ve istisna olarak doner.
     */
    @SuppressLint("MissingPermission")
    private fun handleService(method: String, args: Any?, result: MethodChannel.Result) {
        try {
            when (method) {
                "start" -> {
                    val m = args as? Map<*, *>
                    val goal = m?.get("goal") as? Int ?: 8000
                    val height = m?.get("heightCm") as? Int ?: -1
                    val weight = (m?.get("weightKg") as? Number)?.toDouble() ?: -1.0
                    val edit = StepService.prefs(this).edit()
                        .putInt(StepService.K_GOAL, goal)
                        .putBoolean(StepService.K_ENABLED, true)
                    if (height > 0) edit.putInt(StepService.K_HEIGHT, height)
                    if (weight > 0) edit.putFloat(StepService.K_WEIGHT, weight.toFloat())
                    edit.apply()
                    val intent = Intent(this, StepService::class.java)
                        .putExtra("goal", goal)
                        .putExtra("heightCm", height)
                        .putExtra("weightKg", weight)
                    ContextCompat.startForegroundService(this, intent)
                    result.success(true)
                }

                // Hedef/boy/kilo degisti: kalici bildirim ve widget hemen tazelenir.
                "syncToday" -> {
                    // Uygulamanin bugunku degeri; servis kucukse benimser.
                    val m = args as? Map<*, *>
                    val day = m?.get("date") as? String ?: ""
                    val steps = (m?.get("steps") as? Number)?.toInt() ?: -1
                    if (day.isNotEmpty() && steps > 0) {
                        StepService.instance?.adoptToday(day, steps)
                    }
                    result.success(true)
                }

                "updateGoal" -> {
                    val m = args as? Map<*, *>
                    val goal = m?.get("goal") as? Int ?: -1
                    val height = m?.get("heightCm") as? Int ?: -1
                    val weight = (m?.get("weightKg") as? Number)?.toDouble() ?: -1.0
                    val edit = StepService.prefs(this).edit()
                    if (goal > 0) edit.putInt(StepService.K_GOAL, goal)
                    if (height > 0) edit.putInt(StepService.K_HEIGHT, height)
                    if (weight > 0) edit.putFloat(StepService.K_WEIGHT, weight.toFloat())
                    edit.apply()
                    StepService.instance?.applyProfile(goal, height, weight)
                    result.success(true)
                }

                "stop" -> {
                    StepService.prefs(this).edit()
                        .putBoolean(StepService.K_ENABLED, false).apply()
                    stopService(Intent(this, StepService::class.java))
                    result.success(true)
                }

                "isRunning" -> result.success(StepService.running)

                "pull" -> {
                    // Servis diske 30 sn'de bir yazar; once en guncel hali yazilsin.
                    StepService.instance?.flushNow()
                    val p = StepService.prefs(this)
                    val out = JSONObject()
                    out.put("running", StepService.running)
                    out.put("date", p.getString(StepService.K_DATE, "") ?: "")
                    out.put("today", p.getInt(StepService.K_TODAY, 0))
                    out.put("history", p.getString(StepService.K_HISTORY, "{}") ?: "{}")
                    out.put("hourly", p.getString(StepService.K_HOURLY, "{}") ?: "{}")
                    out.put("intensity", p.getString(StepService.K_INTENSITY, "{}") ?: "{}")
                    result.success(out.toString())
                }

                "clear" -> {
                    StepService.prefs(this).edit()
                        .remove(StepService.K_HISTORY)
                        .remove(StepService.K_HOURLY)
                        .remove(StepService.K_INTENSITY)
                        .remove(StepService.K_TODAY)
                        .remove(StepService.K_SAVED)
                        .remove(StepService.K_BASELINE)
                        .remove(StepService.K_DATE)
                        .apply()
                    // Calisan servisin bellekteki kopyasi da sifirlanmali; yoksa
                    // bir sonraki adimda eski degerleri geri yazar.
                    StepService.instance?.resetState()
                    result.success(true)
                }

                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                    val isIgnoring = pm?.isIgnoringBatteryOptimizations(packageName) ?: false
                    result.success(isIgnoring)
                }

                "openBatterySettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = android.net.Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    try {
                        startActivity(intent)
                    } catch (e: Exception) {
                        // If device doesn't support the targeted intent, fallback to global battery settings
                        val fallback = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        fallback.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(fallback)
                    }
                    result.success(true)
                }

                // ---- Rota (RouteTracker) ----
                "routeStatus" -> {
                    val out = JSONObject()
                    out.put("enabled", RouteTracker.isEnabled(this))
                    out.put("fine", RouteTracker.hasFine(this))
                    out.put("background", RouteTracker.hasBackground(this))
                    out.put("active", StepService.instance?.route?.active == true)
                    out.put("serviceRunning", StepService.running)
                    out.put("locationType", StepService.instance?.locationTypeActive == true)
                    out.put("locationOn", RouteTracker.locationOn(this))
                    StepService.instance?.route?.let { r ->
                        out.put("lastAccuracy", r.lastFixAccuracy.toDouble())
                        out.put("lastFixAgoSec",
                            if (r.lastFixAt > 0) (System.currentTimeMillis() - r.lastFixAt) / 1000 else -1)
                        if (r.lastFixAt > 0) {
                            out.put("lastLat", r.lastFixLat)
                            out.put("lastLng", r.lastFixLng)
                        }
                        out.put("accepted", r.acceptedToday)
                        out.put("rejected", r.rejectedToday)
                    }
                    result.success(out.toString())
                }

                "setRouteEnabled" -> {
                    val m = args as? Map<*, *>
                    val enabled = m?.get("enabled") as? Boolean ?: false
                    StepService.prefs(this).edit()
                        .putBoolean(RouteTracker.K_ROUTE_ENABLED, enabled).apply()
                    StepService.instance?.onRouteSettingsChanged()
                    result.success(true)
                }

                // Izin degisti (uygulamaya donuldu): servis tipi tazelenir.
                "refreshRoute" -> {
                    StepService.instance?.onRouteSettingsChanged()
                    result.success(true)
                }

                "getRoutes" -> {
                    val m = args as? Map<*, *>
                    val from = m?.get("from") as? String ?: ""
                    val to = m?.get("to") as? String ?: ""
                    val gap = (m?.get("minGap") as? Number)?.toDouble() ?: 0.0
                    StepService.instance?.route?.flush()
                    val app = applicationContext
                    // Yil gorunumunde yuzlerce dosya okunabilir: ana is parcacigi bloklanmasin.
                    Thread {
                        try {
                            val json = RouteTracker.readDays(app, from, to, gap).toString()
                            main.post { result.success(json) }
                        } catch (e: Exception) {
                            main.post { result.error("route_error", e.message, null) }
                        }
                    }.start()
                }

                // Telefonun Konum anahtari kapaliysa Google'in tek dokunuslu
                // "Konumu ac" penceresi. Uygulama anahtari kendisi acamaz;
                // kullanici "Tamam" derse sistem acar.
                "requestLocationOn" -> {
                    val req = LocationSettingsRequest.Builder()
                        .addLocationRequest(
                            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 3_000L).build()
                        )
                        .setAlwaysShow(true)
                        .build()
                    LocationServices.getSettingsClient(this).checkLocationSettings(req)
                        .addOnSuccessListener { result.success(true) }
                        .addOnFailureListener { e ->
                            if (e is ResolvableApiException && pendingLocationOn == null) {
                                try {
                                    pendingLocationOn = result
                                    e.startResolutionForResult(this, reqLocationOn)
                                } catch (x: Exception) {
                                    pendingLocationOn = null
                                    result.success(false)
                                }
                            } else {
                                result.success(false)
                            }
                        }
                }

                // Telefonun Konum anahtari kapaliysa ayar ekrani.
                "openLocationSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }

                // ---- Yuruyus kaydi / aralikli yuruyus ----
                "workoutStart" -> {
                    val m = args as? Map<*, *>
                    val svc = StepService.instance
                    if (svc == null) {
                        result.error("no_service", "Arka plan servisi çalışmıyor", null)
                    } else {
                        val ok = svc.startWorkout(
                            m?.get("interval") as? Boolean ?: false,
                            (m?.get("rounds") as? Number)?.toInt() ?: 5,
                            (m?.get("fastSec") as? Number)?.toInt() ?: 180,
                            (m?.get("slowSec") as? Number)?.toInt() ?: 180
                        )
                        result.success(ok)
                    }
                }

                "workoutStop" -> {
                    result.success(StepService.instance?.stopWorkout()?.toString())
                }

                "workoutStatus" -> {
                    val o = StepService.instance?.workout?.statusJson() ?: JSONObject().put("active", false)
                    result.success(o.toString())
                }

                "workouts" -> {
                    result.success(WorkoutManager.readAll(this).toString())
                }

                // GPS ile olculen adim boyu (m); <= 0 ise boydan tahmine donulur.
                "setStride" -> {
                    val m = args as? Map<*, *>
                    val v = (m?.get("strideM") as? Number)?.toDouble() ?: -1.0
                    StepService.prefs(this).edit()
                        .putFloat(StepService.K_STRIDE, if (v > 0) v.toFloat() else -1f).apply()
                    Formulas.strideOverrideM = if (v > 0) v else null
                    StepService.instance?.onStrideChanged()
                    result.success(true)
                }

                // Su ayari / widget'tan eklenen su: bildirim ve widget tazelensin.
                "waterChanged" -> {
                    StepService.instance?.onWaterChanged()
                    StepWidgetProvider.refreshAll(this)
                    result.success(true)
                }

                // Rota haritasi kayit yokken bulunulan yere odaklansin.
                "lastLocation" -> {
                    if (!RouteTracker.hasFine(this)) {
                        result.success(null)
                    } else {
                        val client = LocationServices.getFusedLocationProviderClient(this)
                        client.lastLocation
                            .addOnSuccessListener { loc ->
                                if (loc != null) {
                                    result.success("${loc.latitude},${loc.longitude}")
                                } else {
                                    client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
                                        .addOnSuccessListener { cur ->
                                            result.success(cur?.let { "${it.latitude},${it.longitude}" })
                                        }
                                        .addOnFailureListener { result.success(null) }
                                }
                            }
                            .addOnFailureListener { result.success(null) }
                    }
                }

                "clearRoutes" -> {
                    StepService.instance?.route?.flush()
                    RouteTracker.clearAll(this)
                    result.success(true)
                }

                // "Her zaman izin ver" secenegi yalnizca uygulama ayarlarinda var.
                "openAppSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    intent.data = android.net.Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("service_error", e.message, null)
        }
    }

    private fun register() {
        if (listener != null) return
        val events = sink ?: return

        val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        if (sm == null) {
            events.error("no_service", "Sensor servisi alinamadi", null)
            return
        }

        val sensor = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sensor == null) {
            events.error("no_sensor", "Cihazda adim sayaci yok", null)
            return
        }

        val l = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent?) {
                val value = event?.values?.firstOrNull() ?: return
                // EventSink yalnizca ana is parcacigindan cagrilabilir.
                main.post { sink?.success(value.toLong()) }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        sm.registerListener(l, sensor, SensorManager.SENSOR_DELAY_FASTEST, 0)
        sensorManager = sm
        listener = l
    }

    private fun unregister() {
        listener?.let { sensorManager?.unregisterListener(it) }
        listener = null
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqLocationOn) {
            val r = pendingLocationOn
            pendingLocationOn = null
            r?.success(resultCode == RESULT_OK)
            if (resultCode == RESULT_OK) StepService.instance?.onRouteSettingsChanged()
        }
    }

    override fun onResume() {
        super.onResume()
        // On plandayken widget'i Flutter ciziyor; servis cizmesin.
        StepService.appInForeground = true
        register()
    }

    override fun onPause() {
        unregister()
        StepService.appInForeground = false
        StepService.instance?.onAppBackground()
        super.onPause()
    }

    override fun onDestroy() {
        unregister()
        sink = null
        super.onDestroy()
    }
}
