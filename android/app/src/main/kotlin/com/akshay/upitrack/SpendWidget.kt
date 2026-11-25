package com.akshay.upitrack

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widget: what went out today and this month. Dart stores the
 * totals as JSON under [KEY] ({"day":"2026-11-25","month":"2026-11",
 * "today":125000,"total":1840000}, paise) whenever the app loads the
 * current month and when a bank SMS arrives; a stored day or month that
 * has passed shows as zero, and the system redraws every 30 minutes.
 */
class SpendWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
    }

    companion object {
        const val KEY = "widget"

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, SpendWidget::class.java))
            if (ids.isNotEmpty()) draw(context, manager, ids)
        }

        private fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val json = context.getSharedPreferences(NativeBridge.PREFS, Context.MODE_PRIVATE)
                .getString(KEY, null)
            val state = try {
                if (json == null) JSONObject() else JSONObject(json)
            } catch (e: Exception) {
                JSONObject()
            }
            val now = Date()
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)
            val month = SimpleDateFormat("yyyy-MM", Locale.US).format(now)
            val todayPaise = if (state.optString("day") == today) state.optLong("today") else 0L
            val monthPaise = if (state.optString("month") == month) state.optLong("total") else 0L

            val rupees = NumberFormat.getCurrencyInstance(Locale.forLanguageTag("en-IN")).apply {
                maximumFractionDigits = 0
            }
            val monthName = SimpleDateFormat("MMMM", Locale.getDefault()).format(now)
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.spend_widget)
                views.setTextViewText(R.id.widget_today, rupees.format(todayPaise / 100.0))
                views.setTextViewText(
                    R.id.widget_month, "$monthName ${rupees.format(monthPaise / 100.0)}"
                )
                views.setOnClickPendingIntent(R.id.widget_root, open)
                manager.updateAppWidget(id, views)
            }
        }
    }
}
