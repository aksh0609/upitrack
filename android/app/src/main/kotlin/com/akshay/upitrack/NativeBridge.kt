package com.akshay.upitrack

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * A small key-value store and the home-screen widget, for both the app's
 * engine (MainActivity) and the background SMS engine (SmsReceiver), which
 * cannot write the app's database. Dart side: lib/util/native_bridge.dart.
 */
object NativeBridge {
    private const val CHANNEL = "upitrack/native"
    const val PREFS = "upitrack_native"

    fun attach(messenger: BinaryMessenger, context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(prefs.getString(call.argument<String>("key"), null))
                "set" -> {
                    prefs.edit()
                        .putString(call.argument<String>("key"), call.argument<String>("value"))
                        .apply()
                    result.success(null)
                }
                "widget" -> {
                    prefs.edit().putString(SpendWidget.KEY, call.argument<String>("state")).apply()
                    SpendWidget.refresh(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
