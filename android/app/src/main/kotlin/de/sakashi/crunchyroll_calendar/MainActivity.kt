package de.sakashi.crunchyroll_calendar

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "de.sakashi.crunchyroll_calendar/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "isBackgroundRestricted" -> {
                    result.success(isBackgroundRestricted())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun openBatteryOptimizationSettings() {
        try {
            // Versuche zuerst die App-spezifische Akku-Seite zu öffnen
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } else {
                // Fallback für ältere Android-Versionen
                val intent = Intent(Settings.ACTION_SETTINGS)
                startActivity(intent)
            }
        } catch (e: Exception) {
            // Fallback: Öffne allgemeine Akku-Einstellungen
            try {
                val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                // Letzter Fallback: Allgemeine Einstellungen
                val intent = Intent(Settings.ACTION_SETTINGS)
                startActivity(intent)
            }
        }
    }
    
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            return powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return true // Vor Android M war keine Akku-Optimierung vorhanden
    }

    private fun isBackgroundRestricted(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                activityManager.isBackgroundRestricted
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }
}
