package com.nova.nova_companion

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ctlChannel = "com.nova.nova_companion/notifications_ctl"
    private val eventChannelName = "com.nova.nova_companion/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ctlChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(isNotificationServiceEnabled())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NovaNotificationListener.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    NovaNotificationListener.sink = null
                }
            }
        )
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val cn = ComponentName(this, NovaNotificationListener::class.java)
        return flat.split(':').any {
            ComponentName.unflattenFromString(it)?.flattenToString() == cn.flattenToString()
        }
    }
}

class NovaNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.isOngoing) return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString()
            ?: packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        val text = extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString()
            ?: ""
        if (sbn.packageName == packageName) return
        sink?.success(
            mapOf(
                "title" to title,
                "text" to text,
                "app" to sbn.packageName,
            )
        )
    }

    companion object {
        @JvmField
        var sink: EventChannel.EventSink? = null
    }
}
