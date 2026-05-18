package com.example.todo_ai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

class TodoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                updateWidget(context, appWidgetManager, appWidgetId)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    companion object {
        // Nom du fichier SharedPreferences utilisé par home_widget 0.9.x
        private const val PREFS_NAME = "HomeWidgetPreferences"

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.todo_widget)

            // Nombre de tâches
            val count = prefs.getString("task_count", "0") ?: "0"
            views.setTextViewText(R.id.widget_count, "$count tâche(s)")

            // IDs des TextViews de tâches
            val taskViewIds = intArrayOf(
                R.id.widget_task_0,
                R.id.widget_task_1,
                R.id.widget_task_2,
                R.id.widget_task_3
            )

            var hasAnyTask = false
            for (i in taskViewIds.indices) {
                val title    = prefs.getString("task_$i", "") ?: ""
                val priority = prefs.getString("priority_$i", "normal") ?: "normal"
                if (title.isNotEmpty()) {
                    hasAnyTask = true
                    val prefix = when (priority) {
                        "high" -> "[!] "
                        "low"  -> "[v] "
                        else   -> "[ ] "
                    }
                    views.setTextViewText(taskViewIds[i], "$prefix$title")
                    views.setViewVisibility(taskViewIds[i], View.VISIBLE)
                } else {
                    views.setViewVisibility(taskViewIds[i], View.GONE)
                }
            }

            // État vide
            views.setViewVisibility(
                R.id.widget_empty,
                if (hasAnyTask) View.GONE else View.VISIBLE
            )

            // Clic sur le widget → ouvrir l'app
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
