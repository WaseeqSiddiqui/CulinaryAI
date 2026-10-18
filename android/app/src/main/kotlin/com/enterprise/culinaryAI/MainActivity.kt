package com.enterprise.culinaryAI

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val LOCATION_CHANNEL = "com.enterprise.culinary_ai/location_permission"
        private const val LOCATION_REQUEST_CODE = 4107
    }

    private var tesseractOcrChannel: TesseractOcrChannel? = null
    private var locationChannel: MethodChannel? = null
    private var pendingLocationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tesseractOcrChannel = TesseractOcrChannel(this, flutterEngine)
        locationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCATION_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "requestLocationPermission") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                requestLocationPermission(result)
            }
        }
    }

    private fun hasLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (hasLocationPermission()) {
            result.success(true)
            return
        }
        if (pendingLocationResult != null) {
            result.error("request_in_progress", "A location permission request is already open.", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        pendingLocationResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            LOCATION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCATION_REQUEST_CODE) return
        pendingLocationResult?.success(hasLocationPermission())
        pendingLocationResult = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingLocationResult?.error(
            "activity_closed",
            "The location permission request was interrupted.",
            null,
        )
        pendingLocationResult = null
        locationChannel?.setMethodCallHandler(null)
        locationChannel = null
        tesseractOcrChannel?.close()
        tesseractOcrChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
