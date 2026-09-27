import 'dart:collection';

/// Smooth RSSI with hysteresis for Near / Weak / Away UI only.
enum ProximityBand { near, weak, away }

class RssiFilter {
  RssiFilter({
    this.window = 7,
    this.nearEnter = -65,
    this.nearExit = -72,
    this.weakEnter = -82,
    this.weakExit = -88,
    this.minDwellMs = 1200,
  });

  final int window;
  final int nearEnter;
  final int nearExit;
  final int weakEnter;
  final int weakExit;
  final int minDwellMs;

  final ListQueue<int> _samples = ListQueue<int>();
  ProximityBand _band = ProximityBand.away;
  DateTime _since = DateTime.now();

  int? get smoothed {
    if (_samples.isEmpty) return null;
    final sorted = _samples.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }

  ProximityBand get band => _band;

  ProximityBand push(int rssi) {
    _samples.addLast(rssi);
    while (_samples.length > window) {
      _samples.removeFirst();
    }
    final v = smoothed!;
    final now = DateTime.now();
    ProximityBand next = _band;
    switch (_band) {
      case ProximityBand.near:
        if (v < nearExit) next = ProximityBand.weak;
        break;
      case ProximityBand.weak:
        if (v >= nearEnter) {
          next = ProximityBand.near;
        } else if (v < weakExit) {
          next = ProximityBand.away;
        }
        break;
      case ProximityBand.away:
        if (v >= weakEnter) next = ProximityBand.weak;
        if (v >= nearEnter) next = ProximityBand.near;
        break;
    }
    if (next != _band && now.difference(_since).inMilliseconds >= minDwellMs) {
      _band = next;
      _since = now;
    }
    return _band;
  }
}
