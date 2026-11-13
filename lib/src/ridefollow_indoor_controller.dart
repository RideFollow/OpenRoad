import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ftms.dart';
import 'gpx_route.dart';
import 'openroad_engine.dart';

class IndoorTrainerDevice {
  const IndoorTrainerDevice(this.id, this.name, this._device);
  final String id;
  final String name;
  final BluetoothDevice _device;
}

class IndoorRideSample {
  const IndoorRideSample({
    required this.position,
    required this.speedKmh,
    this.trainerSpeedKmh,
    this.cadenceRpm,
    this.powerWatts,
    this.heartRateBpm,
    this.resistanceLevel,
    required this.virtualGear,
    required this.trainerGradePercent,
  });
  final RoutePosition position;
  final double speedKmh;
  final double? trainerSpeedKmh;
  final double? cadenceRpm;
  final int? powerWatts;
  final int? heartRateBpm;
  final double? resistanceLevel;
  final int virtualGear;
  final double trainerGradePercent;
}

/// Bluetooth FTMS adapter around the pure [OpenRoadEngine].
class OpenRoad {
  static final Guid _ftms = Guid('1826');
  static final Guid _bikeData = Guid('2ad2');
  static final Guid _controlPoint = Guid('2ad9');

  final _devices = StreamController<List<IndoorTrainerDevice>>.broadcast();
  final _samples = StreamController<IndoorRideSample>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  Stream<List<IndoorTrainerDevice>> get deviceUpdates => _devices.stream;
  Stream<IndoorRideSample> get samples => _samples.stream;

  /// Emits `false` when the connected trainer drops (out of range, powered
  /// off, taken by another app) and `true` when a connection is established.
  /// A host-initiated [disconnect] does not emit.
  Stream<bool> get connectionUpdates => _connection.stream;

  final Map<String, IndoorTrainerDevice> _found = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  OpenRoadEngine? _engine;
  DateTime? _lastDataAt;
  double? _lastGrade;
  int _virtualGear = OpenRoadVirtualGearing.neutralGear;
  bool _paused = false;

  int get virtualGear => _virtualGear;

  /// Whether the virtual rider is held in place (see [pause]).
  bool get paused => _paused;

  /// Whether a trainer is currently connected.
  bool get connected => _connected;
  bool _connected = false;

  void setVirtualGear(int gear) {
    final next = OpenRoadVirtualGearing.clamp(gear);
    if (next == _virtualGear) return;
    _virtualGear = next;
    _lastGrade = null;
    _applyTrainerSimulation();
  }

  void shiftUp() => setVirtualGear(_virtualGear + 1);
  void shiftDown() => setVirtualGear(_virtualGear - 1);

  /// Whether Bluetooth is supported and switched on. Waits briefly for the
  /// adapter to report its state (it is `unknown` right after launch).
  static Future<bool> bluetoothOn() async {
    if (!await FlutterBluePlus.isSupported) return false;
    final state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => BluetoothAdapterState.unknown,
        );
    // On Android an `off`/`unauthorized` adapter can't scan; treat unknown as
    // "try anyway" so a slow adapter report never blocks a working scan.
    return state == BluetoothAdapterState.on ||
        state == BluetoothAdapterState.unknown;
  }

  Future<void> scan({Duration timeout = const Duration(seconds: 8)}) async {
    _found.clear();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertised = result.advertisementData.serviceUuids;
        if (!advertised.contains(_ftms)) continue;
        final name = result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : result.device.platformName;
        _found[result.device.remoteId.str] = IndoorTrainerDevice(
          result.device.remoteId.str,
          name.isEmpty ? 'FTMS trainer' : name,
          result.device,
        );
      }
      _devices.add(List.unmodifiable(_found.values));
    });
    await FlutterBluePlus.startScan(withServices: [_ftms], timeout: timeout);
  }

  Future<void> connect(IndoorTrainerDevice selected) async {
    await disconnect();
    // The D100 and many budget FTMS trainers expose only one Bluetooth link.
    // Stop discovery before connecting so iOS is not still scanning while it
    // negotiates that single link.
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _device = selected._device;
    try {
      await _device!.connect(timeout: const Duration(seconds: 12));
      final services = await _device!.discoverServices();
      BluetoothCharacteristic? bikeData;
      for (final service in services.where((s) => s.uuid == _ftms)) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _bikeData) bikeData = characteristic;
          if (characteristic.uuid == _controlPoint) _control = characteristic;
        }
      }
      if (bikeData == null) {
        throw StateError('Trainer does not expose FTMS Indoor Bike Data');
      }
      _dataSub = bikeData.onValueReceived.listen(_onBikeData);
      await bikeData.setNotifyValue(true);
      _stateSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _lastDataAt = null;
          _connected = false;
          _connection.add(false);
        } else if (state == BluetoothConnectionState.connected) {
          _connected = true;
          _connection.add(true);
        }
      });
      if (_control != null) {
        await _control!.setNotifyValue(true);
        await _control!.write([0x00]); // request control
        await _control!.write([0x07]); // start/resume
      }
    } catch (_) {
      // Do not leave a half-connected peripheral holding the trainer's only
      // Bluetooth slot after service discovery or control negotiation fails.
      await disconnect();
      rethrow;
    }
  }

  void start(
    GpxRoute route, {
    OpenRoadParameters parameters = const OpenRoadParameters(),
  }) {
    _engine = OpenRoadEngine(route: route, parameters: parameters);
    _virtualGear = OpenRoadVirtualGearing.neutralGear;
    _lastDataAt = null;
    _lastGrade = null;
    _paused = false;
  }

  /// Hold the virtual rider in place. Trainer data keeps flowing as samples
  /// (live power/cadence), but the route position does not advance until
  /// [resume].
  void pause() {
    _paused = true;
    _lastDataAt = null;
  }

  void resume() {
    _paused = false;
    _lastDataAt = null;
  }

  /// End the virtual ride. The trainer stays connected for the next one.
  void stop() {
    _engine = null;
    _paused = false;
    _lastDataAt = null;
  }

  void _onBikeData(List<int> value) {
    final engine = _engine;
    if (engine == null) return;
    final bike = FtmsBikeData.parse(value);
    final now = DateTime.now();
    final elapsed = _paused || _lastDataAt == null
        ? Duration.zero
        : now.difference(_lastDataAt!);
    _lastDataAt = _paused ? null : now;
    final frame = engine.advance(bike, elapsed);
    final trainerGrade = OpenRoadVirtualGearing.effectiveGrade(
      frame.position.gradePercent,
      _virtualGear,
    );
    _samples.add(IndoorRideSample(
      position: frame.position,
      speedKmh: frame.virtualSpeedKmh,
      trainerSpeedKmh: frame.trainerSpeedKmh,
      cadenceRpm: frame.cadenceRpm,
      powerWatts: frame.powerWatts,
      heartRateBpm: frame.heartRateBpm,
      resistanceLevel: frame.resistanceLevel,
      virtualGear: _virtualGear,
      trainerGradePercent: trainerGrade,
    ));
    if (_control != null &&
        (_lastGrade == null || (trainerGrade - _lastGrade!).abs() >= 0.2)) {
      _applyTrainerSimulation();
    }
  }

  void _applyTrainerSimulation() {
    final control = _control;
    final engine = _engine;
    if (control == null || engine == null) return;
    final grade = OpenRoadVirtualGearing.effectiveGrade(
      engine.position.gradePercent,
      _virtualGear,
    );
    _lastGrade = grade;
    final parameters = engine.parameters;
    unawaited(
      control.write(
        FtmsBikeData.simulationParameters(
          grade,
          windSpeedMps: parameters.windSpeedMps,
          rollingResistance: parameters.rollingResistance,
          windResistanceKgM: parameters.ftmsWindResistanceKgM,
        ),
      ),
    );
  }

  Future<void> disconnect() async {
    await _stateSub?.cancel();
    _stateSub = null;
    _connected = false;
    await _dataSub?.cancel();
    _dataSub = null;
    final device = _device;
    _device = null;
    _control = null;
    if (device != null) await device.disconnect();
  }

  Future<void> dispose() async {
    await _scanSub?.cancel();
    await disconnect();
    await _devices.close();
    await _samples.close();
    await _connection.close();
  }
}

/// Backwards-compatible name for hosts that adopted the 0.1 preview.
typedef RideFollowIndoor = OpenRoad;
