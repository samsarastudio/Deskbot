import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Low-energy Android foreground keep-alive so BLE reconnect can run when
/// the UI is backgrounded. Shows a quiet persistent notification.
class NovaKeepAlive {
  NovaKeepAlive._();

  static bool _inited = false;
  static void Function(Object data)? _onTaskData;

  static void initCommunication() {
    FlutterForegroundTask.initCommunicationPort();
  }

  static void init() {
    if (_inited) return;
    _inited = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nova_ble_keepalive',
        channelName: 'NOVA nearby',
        channelDescription: 'Keeps a light link to your Deskbot while the app is closed.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Slow heartbeat — low energy; main isolate does actual BLE reconnect.
        eventAction: ForegroundTaskEventAction.repeat(20000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static void listen(void Function(Object data) onData) {
    if (_onTaskData != null) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData!);
    }
    _onTaskData = onData;
    FlutterForegroundTask.addTaskDataCallback(onData);
  }

  static void stopListening() {
    if (_onTaskData != null) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData!);
      _onTaskData = null;
    }
  }

  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final n = await FlutterForegroundTask.checkNotificationPermission();
    if (n != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
  }

  static Future<void> start({String status = 'Looking after NOVA nearby'}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    init();
    await ensurePermissions();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'NOVA',
        notificationText: status,
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 2601,
      notificationTitle: 'NOVA',
      notificationText: status,
      notificationIcon: null,
      callback: novaKeepAliveCallback,
      serviceTypes: const [ForegroundServiceTypes.connectedDevice],
    );
  }

  static Future<void> updateStatus(String status) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'NOVA',
      notificationText: status,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void novaKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_NovaKeepAliveHandler());
}

class _NovaKeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({'op': 'keepalive_start'});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Nudge the UI isolate to check BLE / reconnect if needed.
    FlutterForegroundTask.sendDataToMain({'op': 'keepalive_tick'});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}
