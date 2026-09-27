import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../desk/desk_mirror.dart';
import '../desk/scenery_encode.dart';
import '../storage/deskbot_store.dart';
import '../sync/rssi_filter.dart';
import '../sync/sync_engine.dart';
import 'framing.dart';
import 'nova_keepalive.dart';
import 'uuids.dart';

enum BleLinkPhase {
  idle,
  scanning,
  found,
  connecting,
  registering,
  authenticating,
  syncing,
  connected,
  reconnecting,
  away,
  recovery,
}

class BleUiState {
  const BleUiState({
    this.phase = BleLinkPhase.idle,
    this.status = '',
    this.devices = const [],
    this.confirmCode,
    this.proximity = ProximityBand.away,
    this.rssi,
    this.error,
    this.registered,
  });

  final BleLinkPhase phase;
  final String status;
  final List<ScanResult> devices;
  final String? confirmCode;
  final ProximityBand proximity;
  final int? rssi;
  final String? error;
  final RegisteredDeskbot? registered;

  BleUiState copyWith({
    BleLinkPhase? phase,
    String? status,
    List<ScanResult>? devices,
    String? confirmCode,
    ProximityBand? proximity,
    int? rssi,
    String? error,
    RegisteredDeskbot? registered,
    bool clearError = false,
    bool clearCode = false,
  }) {
    return BleUiState(
      phase: phase ?? this.phase,
      status: status ?? this.status,
      devices: devices ?? this.devices,
      confirmCode: clearCode ? null : (confirmCode ?? this.confirmCode),
      proximity: proximity ?? this.proximity,
      rssi: rssi ?? this.rssi,
      error: clearError ? null : (error ?? this.error),
      registered: registered ?? this.registered,
    );
  }
}

final deskbotStoreProvider = Provider((_) => DeskbotStore());
final bleControllerProvider = StateNotifierProvider<BleController, BleUiState>((ref) {
  return BleController(ref.watch(deskbotStoreProvider));
});

class BleController extends StateNotifier<BleUiState> {
  BleController(this._store) : super(const BleUiState()) {
    NovaKeepAlive.listen(_onKeepAliveData);
    _bootstrap();
  }

  final DeskbotStore _store;
  final FragAssembler _assembler = FragAssembler();
  final RssiFilter _rssi = RssiFilter();
  final _uuid = const Uuid();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmd;
  BluetoothCharacteristic? _evt;
  BluetoothCharacteristic? _session;
  SyncEngine? _sync;
  DeskMirror? _mirror;
  StreamSubscription? _scanSub;
  StreamSubscription? _connSub;
  StreamSubscription? _notifySub;
  int _msgId = 1;
  bool _reconnectIntent = false;
  Timer? _rssiTimer;
  bool _connecting = false;

  Future<void> _bootstrap() async {
    final reg = await _store.load();
    if (reg != null) {
      state = state.copyWith(registered: reg, phase: BleLinkPhase.away, status: 'Will reconnect automatically');
      _reconnectIntent = true;
      await NovaKeepAlive.start(status: 'Keeping NOVA nearby');
      await startScan(autoConnectRegistered: true);
    }
  }

  void _onKeepAliveData(Object data) {
    if (data is! Map) return;
    final op = data['op']?.toString();
    if (op == 'keepalive_tick' || op == 'keepalive_start') {
      _ensureLinkFromBackground();
    }
  }

  Future<void> _ensureLinkFromBackground() async {
    if (!_reconnectIntent || state.registered == null) return;
    if (_connecting) return;
    final connected = state.phase == BleLinkPhase.connected ||
        state.phase == BleLinkPhase.authenticating ||
        state.phase == BleLinkPhase.syncing ||
        state.phase == BleLinkPhase.connecting;
    if (connected) {
      await NovaKeepAlive.updateStatus(
        state.phase == BleLinkPhase.connected ? 'Connected to NOVA' : 'Linking…',
      );
      return;
    }
    if (state.phase == BleLinkPhase.scanning || state.phase == BleLinkPhase.reconnecting) {
      return;
    }
    state = state.copyWith(phase: BleLinkPhase.reconnecting, status: 'Reconnecting…', clearError: true);
    await NovaKeepAlive.updateStatus('Looking for NOVA…');
    await startScan(autoConnectRegistered: true);
  }

  Future<void> onAppBackgrounded() async {
    if (state.registered == null) return;
    _reconnectIntent = true;
    await NovaKeepAlive.start(
      status: state.phase == BleLinkPhase.connected ? 'Connected to NOVA' : 'Keeping NOVA nearby',
    );
  }

  Future<void> onAppResumed() async {
    if (state.registered == null) return;
    _reconnectIntent = true;
    await NovaKeepAlive.start(status: 'Looking after NOVA');
    await _ensureLinkFromBackground();
    if (state.phase == BleLinkPhase.connected) {
      await _mirror?.refreshCalendar();
    }
  }

  Future<void> startScan({bool autoConnectRegistered = false}) async {
    if (_connecting) return;
    state = state.copyWith(
      phase: autoConnectRegistered ? BleLinkPhase.reconnecting : BleLinkPhase.scanning,
      status: autoConnectRegistered ? 'Reconnecting…' : 'Looking for your Deskbot…',
      clearError: true,
    );
    await FlutterBluePlus.adapterState.where((s) => s == BluetoothAdapterState.on).first.timeout(
          const Duration(seconds: 8),
          onTimeout: () => BluetoothAdapterState.off,
        );
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      state = state.copyWith(phase: BleLinkPhase.recovery, error: 'Bluetooth is required', status: 'Turn on Bluetooth');
      return;
    }
    await _scanSub?.cancel();
    final found = <String, ScanResult>{};
    await FlutterBluePlus.startScan(
      withServices: [Guid(DeskbotBle.serviceUuid)],
      timeout: const Duration(seconds: 12),
    );
    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        found[r.device.remoteId.str] = r;
      }
      final list = found.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      if (!autoConnectRegistered) {
        state = state.copyWith(devices: list, phase: list.isEmpty ? BleLinkPhase.scanning : BleLinkPhase.found);
      } else {
        state = state.copyWith(devices: list);
      }

      if (autoConnectRegistered && state.registered != null) {
        ScanResult? target;
        final rid = state.registered!.remoteId;
        if (rid != null) {
          target = list.cast<ScanResult?>().firstWhere(
                (r) => r?.device.remoteId.str == rid,
                orElse: () => null,
              );
        }
        target ??= list.isNotEmpty ? list.first : null;
        if (target != null) {
          await FlutterBluePlus.stopScan();
          await connect(target.device, existing: state.registered);
        }
        return;
      }

      if (!autoConnectRegistered && list.length == 1) {
        state = state.copyWith(status: 'Deskbot found');
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
  }

  Future<void> connect(BluetoothDevice device, {RegisteredDeskbot? existing}) async {
    if (_connecting) return;
    _connecting = true;
    await stopScan();
    _device = device;
    state = state.copyWith(phase: BleLinkPhase.connecting, status: 'Connecting');
    try {
      // autoConnect helps Android keep a low-energy retry path in background.
      // Direct connect after scan is more reliable than autoConnect race;
      // background keep-alive + scan handles re-link when the app is closed.
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
      try {
        await device.requestMtu(247);
      } catch (_) {}
      final services = await device.discoverServices();
      final svc = services.firstWhere((s) => s.uuid == Guid(DeskbotBle.serviceUuid));
      _cmd = svc.characteristics.firstWhere((c) => c.uuid == Guid(DeskbotBle.cmdRxUuid));
      _evt = svc.characteristics.firstWhere((c) => c.uuid == Guid(DeskbotBle.evtTxUuid));
      _session = svc.characteristics.firstWhere((c) => c.uuid == Guid(DeskbotBle.sessionUuid));
      await _evt!.setNotifyValue(true);
      _assembler.reset();
      await _notifySub?.cancel();
      _notifySub = _evt!.onValueReceived.listen(_onNotify);

      final token = existing?.ownerToken ?? _uuid.v4().replaceAll('-', '');
      final deviceId = existing?.deviceId ?? 'pending';
      _sync = SyncEngine(
        sendJson: _writeJson,
        ownerToken: token,
        deviceId: deviceId,
      );

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      _rssiTimer?.cancel();
      _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final r = await device.readRssi();
          final band = _rssi.push(r);
          state = state.copyWith(rssi: _rssi.smoothed, proximity: band);
        } catch (_) {}
      });

      if (existing == null) {
        state = state.copyWith(phase: BleLinkPhase.registering, status: 'Linking your Deskbot…');
        await _session?.write(utf8.encode(jsonEncode({'op': 'show_code'})), withoutResponse: false);
        final sess = utf8.decode(await _session!.read());
        final map = jsonDecode(sess) as Map<String, dynamic>;
        final code = map['code']?.toString() ?? '0000';
        state = state.copyWith(confirmCode: code);
      } else {
        state = state.copyWith(phase: BleLinkPhase.authenticating, status: 'Authenticating');
        await NovaKeepAlive.updateStatus('Authenticating…');
        await _sync!.sendHello();
      }
    } catch (e) {
      state = state.copyWith(phase: BleLinkPhase.recovery, error: '$e', status: 'Connection failed');
    } finally {
      _connecting = false;
    }
  }

  Future<void> confirmSetup(String confirmCode) async {
    final device = _device;
    if (device == null || _sync == null) return;
    final code = confirmCode.trim();
    if (code.length != 4) {
      state = state.copyWith(status: 'Enter the 4-digit code on the desk');
      return;
    }
    final token = _sync!.ownerToken;
    state = state.copyWith(phase: BleLinkPhase.registering, status: 'Registering…', clearError: true);
    try {
      await _session?.write(
        utf8.encode(jsonEncode({'op': 'register', 'owner_token': token, 'confirm': code})),
        withoutResponse: false,
      );
      // Wait for real ACK/CAPABILITIES — do not fake success (desyncs phone vs desk tokens).
      Future<void>.delayed(const Duration(seconds: 12), () async {
        if (state.phase == BleLinkPhase.registering && state.registered == null) {
          state = state.copyWith(
            phase: BleLinkPhase.recovery,
            error: 'Deskbot did not confirm setup',
            status: 'Try again',
          );
        }
      });
    } catch (e) {
      state = state.copyWith(phase: BleLinkPhase.recovery, error: '$e', status: 'Setup failed');
    }
  }

  Future<void> _finishRegistration({required String status}) async {
    if (_sync == null || _device == null) return;
    if (state.registered != null && state.phase == BleLinkPhase.connected) return;
    final deviceId = await _readDeviceId();
    final reg = RegisteredDeskbot(
      deviceId: deviceId,
      ownerToken: _sync!.ownerToken,
      remoteId: _device!.remoteId.str,
    );
    _sync = SyncEngine(sendJson: _writeJson, ownerToken: reg.ownerToken, deviceId: reg.deviceId);
    await _store.save(reg);
    state = state.copyWith(
      phase: BleLinkPhase.syncing,
      status: 'Syncing…',
      registered: reg,
      clearCode: true,
    );
    _reconnectIntent = true;
    await NovaKeepAlive.start(status: 'Connected to NOVA');
    try {
      await _sync!.sendStateVersion();
    } catch (_) {}
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (state.registered != null &&
          (state.phase == BleLinkPhase.syncing || state.phase == BleLinkPhase.registering)) {
        state = state.copyWith(phase: BleLinkPhase.connected, status: status);
      }
    });
  }

  Future<String> _readDeviceId() async {
    try {
      final device = _device;
      if (device == null) return 'nova-desk';
      final services = await device.discoverServices();
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.uuid == Guid(DeskbotBle.infoUuid)) {
            final raw = utf8.decode(await c.read());
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final id = map['device_id']?.toString();
            if (id != null && id.isNotEmpty) return id;
          }
        }
      }
    } catch (_) {}
    if (_sync != null && _sync!.deviceId != 'pending') return _sync!.deviceId;
    return 'nova-desk';
  }

  Future<void> _writeJson(String json) async {
    if (_cmd == null) return;
    final frags = fragBuild(_msgId++, utf8.encode(json));
    for (final f in frags) {
      await _cmd!.write(f, withoutResponse: true);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  Future<void> _onNotify(List<int> value) async {
    final complete = _assembler.feed(Uint8List.fromList(value));
    if (complete == null) return;
    try {
      final msg = jsonDecode(utf8.decode(complete)) as Map<String, dynamic>;
      final hint = await _sync?.onMessage(msg);
      final type = msg['type'];
      if (type == 'ACK' || type == 'STATE_SNAPSHOT' || type == 'DELTA' || type == 'CAPABILITIES') {
        // DISPLAY op ACKs return null hint — ignore once already linked.
        if (type == 'ACK' && hint == null && state.phase == BleLinkPhase.connected) {
          return;
        }
        if (state.registered == null || state.phase == BleLinkPhase.registering) {
          if (type == 'CAPABILITIES' || type == 'ACK') {
            await _finishRegistration(status: hint ?? 'Linked');
            return;
          }
        }
        final reg = RegisteredDeskbot(
          deviceId: (_sync?.deviceId == 'pending')
              ? ((msg['body'] as Map?)?['device_id']?.toString() ?? state.registered?.deviceId ?? 'nova-unknown')
              : _sync!.deviceId,
          ownerToken: _sync!.ownerToken,
          remoteId: _device?.remoteId.str,
        );
        await _store.save(reg);
        state = state.copyWith(
          phase: BleLinkPhase.connected,
          status: hint ?? 'Connected',
          registered: reg,
          clearCode: true,
          clearError: true,
        );
        _reconnectIntent = true;
        await NovaKeepAlive.updateStatus('Connected to NOVA');
        await _startMirror();
      } else if (type == 'UI_HINT') {
        state = state.copyWith(confirmCode: hint);
      } else if (type == 'NACK') {
        if (hint == 'Retrying auth…') {
          state = state.copyWith(phase: BleLinkPhase.authenticating, status: hint!, clearError: true);
        } else {
          // Token mismatch or desk owned by another phone — stop looping.
          state = state.copyWith(
            phase: BleLinkPhase.recovery,
            error: 'Auth failed — remove Deskbot and set up again (or factory-reset the desk).',
            status: 'Open recovery',
          );
          await NovaKeepAlive.updateStatus('Needs attention');
        }
      } else if (type == 'HELLO') {
        final body = (msg['body'] as Map?)?.cast<String, dynamic>();
        final id = body?['device_id']?.toString();
        // Update id in place — do NOT recreate SyncEngine (that reset auth retry state).
        if (id != null && id.isNotEmpty) {
          _sync?.deviceId = id;
        }
        if (state.phase != BleLinkPhase.connected && state.phase != BleLinkPhase.syncing) {
          state = state.copyWith(phase: BleLinkPhase.authenticating, status: 'Authenticating');
        }
      } else if (hint != null && hint.length == 4) {
        state = state.copyWith(confirmCode: hint);
      }
    } catch (e) {
      debugPrint('notify parse $e');
    }
  }

  void _onDisconnected() {
    _mirror?.stop();
    _mirror = null;
    _rssiTimer?.cancel();
    state = state.copyWith(
      phase: _reconnectIntent && state.registered != null ? BleLinkPhase.reconnecting : BleLinkPhase.away,
      status: _reconnectIntent ? 'Reconnecting…' : 'Deskbot away',
    );
    NovaKeepAlive.updateStatus(_reconnectIntent ? 'Looking for NOVA…' : 'NOVA away');
    if (_reconnectIntent && state.registered != null) {
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        startScan(autoConnectRegistered: true);
      });
    }
  }

  Future<void> _startMirror() async {
    final sync = _sync;
    if (sync == null || !sync.authed) return;
    await _mirror?.stop();
    _mirror = DeskMirror(sync);
    await _mirror!.start();
  }

  Future<void> pushNotify(String title, String body) async {
    await _sync?.pushNotify(title: title, body: body);
  }

  Future<void> uploadScenery(Uint8List imageBytes) async {
    final sync = _sync;
    if (sync == null || !sync.authed) {
      throw StateError('Connect to Deskbot first');
    }
    final size = scenerySize();
    final pixels = encodeSceneryRgb565(imageBytes, maxW: size.w, maxH: size.h);
    await sync.uploadSceneryRgb565(pixels, w: size.w, h: size.h);
  }

  Future<void> clearScenery() => _sync?.clearScenery() ?? Future.value();

  Future<void> openNotificationAccess() =>
      _mirror?.openNotificationAccess() ?? Future.value();

  Future<void> refreshCalendar() => _mirror?.refreshCalendar() ?? Future.value();

  Future<void> removeDeskbot() async {
    _reconnectIntent = false;
    await _mirror?.stop();
    _mirror = null;
    await NovaKeepAlive.stop();
    await _device?.disconnect();
    await _store.clear();
    state = const BleUiState(phase: BleLinkPhase.idle, status: '');
  }

  Future<void> factoryResetRemote() async {
    try {
      // Works even when auth failed — desk accepts this in recovery.
      await _session?.write(
        utf8.encode(jsonEncode({'op': 'factory_reset'})),
        withoutResponse: false,
      );
    } catch (_) {
      try {
        await _writeJson(envelopeJson('FACTORY_RESET', {}));
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await removeDeskbot();
  }

  @override
  void dispose() {
    NovaKeepAlive.stopListening();
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    _rssiTimer?.cancel();
    super.dispose();
  }
}
