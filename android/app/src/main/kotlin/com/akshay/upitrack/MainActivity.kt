package com.akshay.upitrack

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts the Flutter app and exposes two methods to Dart:
 * readInbox(sinceMillis) -> list of {id, address, body, date}, and
 * install(path), which opens Android's installer on a downloaded APK.
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(File(path))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Hands [file] to the package installer, which asks the user to confirm. */
    private fun installApk(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
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
        private const val UPDATE_CHANNEL = "upitrack/update"
    }
}
