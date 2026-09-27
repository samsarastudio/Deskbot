import 'dart:async';
import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../sync/sync_engine.dart';

/// Mirrors calendar + (Android) phone notifications onto Deskbot via DISPLAY.
class DeskMirror {
  DeskMirror(this._sync);

  final SyncEngine _sync;
  final _calPlugin = DeviceCalendarPlugin();
  StreamSubscription? _notifSub;
  Timer? _calTimer;
  String? _lastCalKey;
  String? _lastNotifKey;
  bool _started = false;

  static const _notifChannel = EventChannel('com.nova.nova_companion/notifications');
  static const _notifMethods = MethodChannel('com.nova.nova_companion/notifications_ctl');

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _sync.pushTimeSync();
    await refreshCalendar();
    _calTimer = Timer.periodic(const Duration(minutes: 2), (_) => refreshCalendar());
    if (Platform.isAndroid) {
      await _startAndroidNotifications();
    }
  }

  Future<void> stop() async {
    _started = false;
    _calTimer?.cancel();
    _calTimer = null;
    await _notifSub?.cancel();
    _notifSub = null;
  }

  Future<void> refreshCalendar() async {
    try {
      var status = await Permission.calendarFullAccess.request();
      if (!status.isGranted && !status.isLimited) {
        status = await Permission.calendarWriteOnly.request();
      }
      if (!status.isGranted && !status.isLimited) {
        // Older permission_handler / platforms.
        try {
          // ignore: deprecated_member_use
          status = await Permission.calendar.request();
        } catch (_) {}
      }
      if (!status.isGranted && !status.isLimited) {
        return;
      }
      final calendars = await _calPlugin.retrieveCalendars();
      if (!(calendars.isSuccess) || calendars.data == null) return;
      final now = DateTime.now();
      final end = now.add(const Duration(hours: 36));
      Event? next;
      DateTime? nextStart;
      for (final cal in calendars.data!) {
        if (cal.id == null) continue;
        final result = await _calPlugin.retrieveEvents(
          cal.id!,
          RetrieveEventsParams(startDate: now, endDate: end),
        );
        if (!(result.isSuccess) || result.data == null) continue;
        for (final e in result.data!) {
          final start = e.start;
          if (start == null) continue;
          final startDt = DateTime.fromMillisecondsSinceEpoch(start.millisecondsSinceEpoch);
          if (startDt.isBefore(now)) continue;
          if (nextStart == null || startDt.isBefore(nextStart)) {
            next = e;
            nextStart = startDt;
          }
        }
      }
      if (next == null || nextStart == null || next.title == null || next.title!.isEmpty) {
        if (_lastCalKey != null) {
          _lastCalKey = null;
          await _sync.pushCalendar();
        }
        return;
      }
      final when = DateFormat('h:mma').format(nextStart).toLowerCase();
      final key = '${next.eventId}|$when|${next.title}';
      if (key == _lastCalKey) return;
      _lastCalKey = key;
      await _sync.pushCalendar(title: next.title, when: when);
    } catch (e) {
      debugPrint('calendar mirror: $e');
    }
  }

  Future<void> pushManualNotify(String title, String body) {
    return _sync.pushNotify(title: title, body: body);
  }

  Future<void> _startAndroidNotifications() async {
    try {
      final enabled = await _notifMethods.invokeMethod<bool>('isEnabled') ?? false;
      if (!enabled) {
        await _notifMethods.invokeMethod('openSettings');
        return;
      }
      _notifSub = _notifChannel.receiveBroadcastStream().listen((event) async {
        if (event is! Map) return;
        final title = (event['title'] ?? event['app'] ?? 'Alert').toString();
        final body = (event['text'] ?? '').toString();
        if (body.isEmpty && title == 'Alert') return;
        final key = '$title|$body';
        if (key == _lastNotifKey) return;
        _lastNotifKey = key;
        // Skip our own keep-alive.
        if (title == 'NOVA') return;
        await _sync.pushNotify(
          title: title.length > 24 ? title.substring(0, 24) : title,
          body: body.length > 80 ? body.substring(0, 80) : body,
        );
      });
    } catch (e) {
      debugPrint('notif mirror: $e');
    }
  }

  Future<void> openNotificationAccess() async {
    if (!Platform.isAndroid) return;
    await _notifMethods.invokeMethod('openSettings');
  }
}
