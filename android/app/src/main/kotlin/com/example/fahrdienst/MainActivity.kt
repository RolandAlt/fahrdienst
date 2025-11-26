package com.example.fahrdienst

import android.bluetooth.BluetoothAdapter
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    // 1) Neuer Channel: liefert ANDROID_ID als stabile Geräte-ID
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.device/ids")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getAndroidId" -> {
            try {
              val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
              result.success(id ?: "")
            } catch (_: Exception) {
              result.success("")
            }
          }
          else -> result.notImplemented()
        }
      }

    // 2) Bestehender Channel: freundlicher Gerätename (belassen)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.device/friendlyname")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "friendlyName" -> {
            val cr = applicationContext.contentResolver

            // 1) Primär: Bluetooth-Name (entspricht auf vielen Geräten dem sichtbaren Gerätenamen)
            val btName = try {
              BluetoothAdapter.getDefaultAdapter()?.name
            } catch (_: SecurityException) {
              null // Android 12+ kann BLUETOOTH_CONNECT erfordern → wir fallen dann zurück
            } catch (_: Exception) {
              null
            }

            // 2) Fallbacks je nach OEM/ROM
            val globalName = try { Settings.Global.getString(cr, "device_name") } catch (_: Exception) { null }
            val secureBt   = try { Settings.Secure.getString(cr, "bluetooth_name") } catch (_: Exception) { null }
            val systemName = try { Settings.System.getString(cr, "device_name") } catch (_: Exception) { null }

            val friendly = sequenceOf(btName, globalName, secureBt, systemName)
              .firstOrNull { !it.isNullOrBlank() }
              ?: ""  // niemals null nach Dart geben

            result.success(friendly)
          }
          else -> result.notImplemented()
        }
      }
  }
}
