package com.piyush.upitrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Runs when any SMS arrives. Starts a small background Flutter engine on the
 * Dart entrypoint `smsBackground` (lib/main.dart), hands it the sender and
 * body, and tears the engine down once Dart has shown its notification.
 * Nothing is stored here; the app's inbox sync records the payment later.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val address = parts[0].displayOriginatingAddress ?: ""
        val body = parts.joinToString("") { it.messageBody ?: "" }

        val pending = goAsync()
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val engine = FlutterEngine(app)
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        lateinit var timeout: Runnable
        fun finish() {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            engine.destroy()
            pending.finish()
        }
        // Android ends a broadcast at 10 s; stop a little before that.
        timeout = Runnable { finish() }
        handler.postDelayed(timeout, 9_000)

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                result.success(null)
                channel.invokeMethod(
                    "sms",
                    mapOf("address" to address, "body" to body),
                    object : MethodChannel.Result {
                        override fun success(r: Any?) { finish() }
                        override fun error(code: String, msg: String?, details: Any?) { finish() }
                        override fun notImplemented() { finish() }
                    }
                )
            } else {
                result.notImplemented()
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "smsBackground")
        )
    }

    companion object {
        const val CHANNEL = "upitrack/sms_bg"
    }
}
