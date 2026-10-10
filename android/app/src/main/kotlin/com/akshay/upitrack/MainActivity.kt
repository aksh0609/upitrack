package com.akshay.upitrack

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Hosts the Flutter app and exposes one method to Dart:
 * readInbox(sinceMillis) -> list of {id, address, body, date}.
 *
 * SMS are read on a background thread and handed to Dart; they are never
 * sent anywhere else.
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readInbox" -> {
                        val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                        executor.execute {
                            try {
                                val messages = readInbox(since)
                                runOnUiThread { result.success(messages) }
                            } catch (e: SecurityException) {
                                runOnUiThread {
                                    result.error("PERMISSION_DENIED", e.message, null)
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("READ_FAILED", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readInbox(sinceMillis: Long): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val cursor = contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("_id", "address", "body", "date"),
            "date > ?",
            arrayOf(sinceMillis.toString()),
            "date DESC"
        ) ?: return out

        cursor.use { c ->
            val id = c.getColumnIndexOrThrow("_id")
            val address = c.getColumnIndexOrThrow("address")
            val body = c.getColumnIndexOrThrow("body")
            val date = c.getColumnIndexOrThrow("date")
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(id),
                        "address" to c.getString(address),
                        "body" to c.getString(body),
                        "date" to c.getLong(date)
                    )
                )
            }
        }
        return out
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "upitrack/sms"
    }
}
