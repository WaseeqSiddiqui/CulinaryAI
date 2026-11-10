package com.enterprise.culinaryAI

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/** Resolves one foreground location; never stores it or changes a merchant address. */
class CurrentLocationResolver(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val cancellations = mutableListOf<CancellationSignal>()
    private var pending: MethodChannel.Result? = null
    private var resolvingAddress = false
    private var closed = false
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) = resolveAddress(location)
        @Deprecated("Legacy Android callback")
        override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }
    private val timeout = Runnable {
        finishError("location_timeout", "Location took too long. Move near a window or enter your address manually.")
    }

    @SuppressLint("MissingPermission")
    fun resolve(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("request_in_progress", "A location search is already running.", null)
            return
        }
        val permitted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!permitted) {
            result.error("location_permission_denied", "Allow location permission or enter your address manually.", null)
            return
        }
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .filter { manager.isProviderEnabled(it) }
        if (providers.isEmpty()) {
            result.error("location_disabled", "Turn on Location in your phone settings, then try again.", null)
            return
        }
        pending = result
        resolvingAddress = false
        handler.postDelayed(timeout, 25_000)
        try {
            // Only use a recent fix with a useful accuracy. Old saved addresses are never GPS fixes.
            val recent = providers.mapNotNull { manager.getLastKnownLocation(it) }
                .filter {
                    val age = (SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) / 1_000_000
                    age in 0..60_000 && it.hasAccuracy() && it.accuracy <= 200
                }.minByOrNull { it.accuracy }
            if (recent != null) {
                resolveAddress(recent)
                return
            }
            for (provider in providers) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val cancellation = CancellationSignal()
                    cancellations.add(cancellation)
                    manager.getCurrentLocation(provider, cancellation, context.mainExecutor) { location ->
                        if (location != null) resolveAddress(location)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                }
            }
        } catch (_: SecurityException) {
            finishError("location_permission_denied", "Location permission changed. Allow it and try again.")
        } catch (_: Exception) {
            finishError("location_unavailable", "The phone could not find its location. Enter your address manually.")
        }
    }

    private fun resolveAddress(location: Location) {
        if (pending == null || resolvingAddress || closed) return
        resolvingAddress = true
        stopLocationUpdates()
        val request = pending
        worker.execute {
            try {
                if (!Geocoder.isPresent()) error("No address provider")
                @Suppress("DEPRECATION")
                val addresses = Geocoder(context, Locale.ENGLISH)
                    .getFromLocation(location.latitude, location.longitude, 1)
                val address = addresses?.firstOrNull()
                val text = address?.getAddressLine(0)?.trim().orEmpty()
                if (text.isEmpty()) error("No address found")
                handler.post {
                    if (pending === request && !closed) {
                        handler.removeCallbacks(timeout)
                        pending = null
                        resolvingAddress = false
                        request?.success(mapOf(
                            "latitude" to location.latitude,
                            "longitude" to location.longitude,
                            "accuracy" to location.accuracy.toDouble(),
                            "address" to text,
                            "locality" to address?.locality,
                        ))
                    }
                }
            } catch (_: Exception) {
                handler.post {
                    if (pending === request) finishError(
                        "address_unavailable",
                        "GPS was found, but its street address could not be resolved. Enter the address manually and confirm the pin.",
                    )
                }
            }
        }
    }

    private fun stopLocationUpdates() {
        cancellations.forEach { it.cancel() }
        cancellations.clear()
        manager.removeUpdates(listener)
    }

    private fun finishError(code: String, message: String) {
        handler.removeCallbacks(timeout)
        stopLocationUpdates()
        val result = pending
        pending = null
        resolvingAddress = false
        result?.error(code, message, null)
    }

    fun close() {
        closed = true
        finishError("activity_closed", "The location search was interrupted.")
        worker.shutdown()
    }
}
