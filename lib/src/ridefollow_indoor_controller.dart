import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ftms.dart';
import 'gpx_route.dart';
import 'heart_rate.dart';
import 'openroad_engine.dart';
import 'zwift_click.dart';

class IndoorTrainerDevice {
  const IndoorTrainerDevice(this.id, this.name, this._device);
  final String id;
  final String name;
  final BluetoothDevice _device;
}

/// A standard Bluetooth Heart Rate Service device, including Garmin watches in
/// Broadcast Heart Rate mode and BLE chest straps.
class HeartRateDevice {
  const HeartRateDevice(this.id, this.name, this._device);
  final String id;
  final String name;
  final BluetoothDevice _device;
}

/// One discoverable controller in a Zwift Click V2 pair.
class ZwiftClickDevice {
  const ZwiftClickDevice(this.id, this.name, this.side, this._device);
  final String id;
  final String name;
  final ZwiftClickSide side;
  final BluetoothDevice _device;
}

/// A connection-state edge for one Click V2 controller.
class ZwiftClickConnectionEvent {
  const ZwiftClickConnectionEvent({
    required this.device,
    required this.connected,
  });
  final ZwiftClickDevice device;
  final bool connected;
}

/// The phase that failed while opening a Click V2 controller session.
enum ZwiftClickConnectionStage {
  bluetooth,
  services,
  characteristics,
  notifications,
  handshake,
}

/// A diagnostic error that lets host apps explain a failed Click V2 setup.
class ZwiftClickConnectionException implements Exception {
  const ZwiftClickConnectionException(this.stage, this.cause);

  final ZwiftClickConnectionStage stage;
  final Object cause;

  String get stageLabel => switch (stage) {
        ZwiftClickConnectionStage.bluetooth => 'Bluetooth connection',
        ZwiftClickConnectionStage.services => 'service discovery',
        ZwiftClickConnectionStage.characteristics => 'Click service discovery',
        ZwiftClickConnectionStage.notifications => 'controller notifications',
        ZwiftClickConnectionStage.handshake => 'controller handshake',
      };

  @override
  String toString() => 'Click V2 $stageLabel failed: $cause';
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
  static final Guid _heartRateService = Guid('180d');
  static final Guid _heartRateMeasurement = Guid('2a37');
  static final Guid _clickAsync = Guid('00000002-19ca-4651-86e5-fa29dcdd09d1');
  static final Guid _clickSyncRx = Guid('00000003-19ca-4651-86e5-fa29dcdd09d1');
  static final Guid _clickSyncTx = Guid('00000004-19ca-4651-86e5-fa29dcdd09d1');

  final _devices = StreamController<List<IndoorTrainerDevice>>.broadcast();
  final _samples = StreamController<IndoorRideSample>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final _heartRateDevices = StreamController<List<HeartRateDevice>>.broadcast();
  final _heartRate = StreamController<int>.broadcast();
  final _heartRateConnection = StreamController<bool>.broadcast();
  final _clickDevices = StreamController<List<ZwiftClickDevice>>.broadcast();
  final _clickButtons = StreamController<ZwiftClickButtonEvent>.broadcast();
  final _clickConnections =
      StreamController<ZwiftClickConnectionEvent>.broadcast();
  Stream<List<IndoorTrainerDevice>> get deviceUpdates => _devices.stream;
  Stream<IndoorRideSample> get samples => _samples.stream;
  Stream<List<HeartRateDevice>> get heartRateDeviceUpdates =>
      _heartRateDevices.stream;
  Stream<int> get heartRateUpdates => _heartRate.stream;
  Stream<bool> get heartRateConnectionUpdates => _heartRateConnection.stream;
  Stream<List<ZwiftClickDevice>> get controllerDeviceUpdates =>
      _clickDevices.stream;
  Stream<ZwiftClickButtonEvent> get controllerButtonUpdates =>
      _clickButtons.stream;
  Stream<ZwiftClickConnectionEvent> get controllerConnectionUpdates =>
      _clickConnections.stream;

  /// Emits `false` when the connected trainer drops (out of range, powered
  /// off, taken by another app) and `true` when a connection is established.
  /// A host-initiated [disconnect] does not emit.
  Stream<bool> get connectionUpdates => _connection.stream;

  final Map<String, IndoorTrainerDevice> _found = {};
  final Map<String, HeartRateDevice> _heartRateFound = {};
  final Map<String, ZwiftClickDevice> _clickFound = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<ScanResult>>? _heartRateScanSub;
  StreamSubscription<List<ScanResult>>? _clickScanSub;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  StreamSubscription<List<int>>? _heartRateDataSub;
  StreamSubscription<BluetoothConnectionState>? _heartRateStateSub;
  BluetoothDevice? _device;
  BluetoothDevice? _heartRateDevice;
  final Map<String, ZwiftClickDevice> _connectedClickDevices = {};
  final Map<String, BluetoothCharacteristic> _clickWrites = {};
  final Map<String, StreamSubscription<List<int>>> _clickButtonSubs = {};
  final Map<String, StreamSubscription<List<int>>> _clickSyncSubs = {};
  final Map<String, StreamSubscription<BluetoothConnectionState>>
      _clickStateSubs = {};
  final Map<String, Timer> _clickKeepalives = {};
  final Map<String, int> _clickPreviousBitmaps = {};
  final Map<String, Set<ZwiftClickButton>> _clickHeldByDevice = {};
  final Map<ZwiftClickButton, int> _clickHeldCounts = {};
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
  bool get heartRateConnected => _heartRateConnected;
  bool _heartRateConnected = false;
  bool get controllersConnected => _connectedClickDevices.isNotEmpty;
  Set<String> get connectedControllerIds =>
      Set.unmodifiable(_connectedClickDevices.keys);

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
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await _heartRateScanSub?.cancel();
    await _clickScanSub?.cancel();
    _heartRateScanSub = null;
    _clickScanSub = null;
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

  /// Find Garmin watches in Broadcast Heart Rate mode and other standard BLE
  /// heart-rate sensors. This is separate from trainer discovery so either can
  /// be refreshed without changing an established connection.
  Future<void> scanHeartRateMonitors({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _heartRateFound.clear();
    await FlutterBluePlus.stopScan();
    await _heartRateScanSub?.cancel();
    await _scanSub?.cancel();
    await _clickScanSub?.cancel();
    _scanSub = null;
    _clickScanSub = null;
    _heartRateScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!result.advertisementData.serviceUuids.contains(
          _heartRateService,
        )) {
          continue;
        }
        final name = result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : result.device.platformName;
        _heartRateFound[result.device.remoteId.str] = HeartRateDevice(
          result.device.remoteId.str,
          name.isEmpty ? 'Heart-rate monitor' : name,
          result.device,
        );
      }
      _heartRateDevices.add(List.unmodifiable(_heartRateFound.values));
    });
    await FlutterBluePlus.startScan(
      withServices: [_heartRateService],
      timeout: timeout,
    );
  }

  /// Find the left and right pods in a Zwift Click V2 pair.
  ///
  /// Press any controller button before scanning so sleeping pods advertise.
  Future<void> scanControllers({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _clickFound.clear();
    await FlutterBluePlus.stopScan();
    await _clickScanSub?.cancel();
    await _scanSub?.cancel();
    await _heartRateScanSub?.cancel();
    _scanSub = null;
    _heartRateScanSub = null;
    _clickScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advertisement = result.advertisementData;
        final manufacturer =
            advertisement.manufacturerData[ZwiftClickProtocol.companyId];
        final name = advertisement.advName.isNotEmpty
            ? advertisement.advName
            : result.device.platformName;
        final side = ZwiftClickProtocol.sideFromManufacturerData(manufacturer);
        final isClick = side != ZwiftClickSide.unknown ||
            name.toLowerCase().contains('click');
        if (!isClick) continue;
        final sideName = switch (side) {
          ZwiftClickSide.left => 'Left',
          ZwiftClickSide.right => 'Right',
          ZwiftClickSide.unknown => 'Controller',
        };
        final displayName = name.isEmpty ? 'Zwift Click V2 · $sideName' : name;
        _clickFound[result.device.remoteId.str] = ZwiftClickDevice(
          result.device.remoteId.str,
          displayName,
          side,
          result.device,
        );
      }
      _clickDevices.add(List.unmodifiable(_clickFound.values));
    });
    // Some controller firmware omits the custom service from advertisements,
    // so scan broadly and filter by Zwift's company ID/name as a fallback.
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> connect(IndoorTrainerDevice selected) async {
    await disconnect();
    // The D100 and many budget FTMS trainers expose only one Bluetooth link.
    // Stop discovery before connecting so iOS is not still scanning while it
    // negotiates that single link.
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    await _clickScanSub?.cancel();
    _clickScanSub = null;
    await _heartRateScanSub?.cancel();
    _heartRateScanSub = null;
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

  Future<void> connectHeartRate(HeartRateDevice selected) async {
    await disconnectHeartRate();
    await FlutterBluePlus.stopScan();
    await _heartRateScanSub?.cancel();
    _heartRateScanSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await _clickScanSub?.cancel();
    _clickScanSub = null;
    _heartRateDevice = selected._device;
    try {
      await _heartRateDevice!.connect(timeout: const Duration(seconds: 12));
      final services = await _heartRateDevice!.discoverServices();
      BluetoothCharacteristic? measurement;
      for (final service in services.where(
        (s) => s.uuid == _heartRateService,
      )) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _heartRateMeasurement) {
            measurement = characteristic;
          }
        }
      }
      if (measurement == null) {
        throw StateError('Device does not expose Heart Rate Measurement');
      }
      _heartRateDataSub = measurement.onValueReceived.listen((value) {
        final bpm = HeartRateMeasurement.parse(value);
        if (bpm != null) _heartRate.add(bpm);
      });
      await measurement.setNotifyValue(true);
      _heartRateStateSub = _heartRateDevice!.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        if (connected == _heartRateConnected) return;
        _heartRateConnected = connected;
        _heartRateConnection.add(connected);
      });
      _heartRateConnected = true;
      _heartRateConnection.add(true);
    } catch (_) {
      await disconnectHeartRate();
      rethrow;
    }
  }

  /// Connect one pod from a Zwift Click V2 pair. Call once for each discovered
  /// pod; existing trainer and heart-rate connections remain untouched.
  Future<void> connectController(ZwiftClickDevice selected) async {
    if (_connectedClickDevices.containsKey(selected.id)) return;
    await FlutterBluePlus.stopScan();
    await _clickScanSub?.cancel();
    _clickScanSub = null;
    final device = selected._device;
    var stage = ZwiftClickConnectionStage.bluetooth;
    try {
      await device.connect(timeout: const Duration(seconds: 12));
      stage = ZwiftClickConnectionStage.services;
      final services = await device.discoverServices();
      BluetoothCharacteristic? asyncButtons;
      BluetoothCharacteristic? syncRx;
      BluetoothCharacteristic? syncTx;
      stage = ZwiftClickConnectionStage.characteristics;
      // Match the characteristic UUIDs across every service. Some Bluetooth
      // stacks briefly return the proprietary service with a stale or partial
      // service identity after reconnecting a pod, while the characteristics
      // themselves are already available.
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _clickAsync) asyncButtons = characteristic;
          if (characteristic.uuid == _clickSyncRx) syncRx = characteristic;
          if (characteristic.uuid == _clickSyncTx) syncTx = characteristic;
        }
      }
      if (asyncButtons == null || syncRx == null) {
        throw StateError('Controller does not expose the Click V2 service');
      }

      _connectedClickDevices[selected.id] = selected;
      _clickWrites[selected.id] = syncRx;
      _clickPreviousBitmaps[selected.id] = 0xffffffff;
      _clickHeldByDevice[selected.id] = <ZwiftClickButton>{};
      _clickButtonSubs[selected.id] = asyncButtons.onValueReceived.listen((
        value,
      ) {
        // Click V2 sends its 0xff 0x03 unlock challenge on the async
        // characteristic, alongside button frames. It does not arrive on
        // sync-tx. The empty acknowledgement preserves an unlock previously
        // granted by Zwift and is harmless on the always-available right pod.
        if (value.length >= 2 && value[0] == 0xff && value[1] == 0x03) {
          unawaited(
            _writeClick(
              syncRx!,
              ZwiftClickProtocol.challengeAck,
            ).catchError((Object _) {}),
          );
        }
        _onControllerFrame(selected.id, value);
      });
      if (syncTx != null) {
        _clickSyncSubs[selected.id] = syncTx.onValueReceived.listen((_) {});
      }
      _clickStateSubs[selected.id] = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          unawaited(_controllerDropped(selected.id));
        }
      });
      stage = ZwiftClickConnectionStage.notifications;
      await asyncButtons.setNotifyValue(true);
      // sync-tx only carries the optional RideOn echo. Missing or unsupported
      // indications must not prevent buttons on the async characteristic.
      if (syncTx != null) {
        try {
          await syncTx.setNotifyValue(true);
        } catch (_) {
          await _clickSyncSubs.remove(selected.id)?.cancel();
        }
      }

      stage = ZwiftClickConnectionStage.handshake;
      await _writeClick(syncRx, ZwiftClickProtocol.activate);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _writeClick(syncRx, ZwiftClickProtocol.setupOne);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _writeClick(syncRx, ZwiftClickProtocol.setupTwo);

      _clickKeepalives[selected.id] = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_keepControllerAlive(selected.id)),
      );
      _clickConnections.add(
        ZwiftClickConnectionEvent(device: selected, connected: true),
      );
    } catch (error) {
      if (_connectedClickDevices.containsKey(selected.id)) {
        await disconnectController(selected.id);
      } else {
        await device.disconnect();
      }
      if (error is ZwiftClickConnectionException) rethrow;
      throw ZwiftClickConnectionException(stage, error);
    }
  }

  Future<void> _writeClick(
    BluetoothCharacteristic characteristic,
    List<int> value,
  ) async {
    final properties = characteristic.properties;
    Object? withoutResponseError;
    if (properties.writeWithoutResponse) {
      try {
        await characteristic.write(value, withoutResponse: true);
        return;
      } catch (error) {
        withoutResponseError = error;
      }
    }
    if (properties.write) {
      await characteristic.write(value, withoutResponse: false);
      return;
    }
    throw StateError(
      'Click V2 sync-rx is not writable'
      '${withoutResponseError == null ? '' : ': $withoutResponseError'}',
    );
  }

  Future<void> _keepControllerAlive(String id) async {
    final write = _clickWrites[id];
    if (write == null) return;
    try {
      await _writeClick(write, ZwiftClickProtocol.rideOn);
    } catch (_) {
      await _controllerDropped(id);
    }
  }

  void _onControllerFrame(String id, List<int> frame) {
    final current = ZwiftClickProtocol.decodeBitmap(frame);
    if (current == null) return;
    final previous = _clickPreviousBitmaps[id] ?? 0xffffffff;
    _clickPreviousBitmaps[id] = current;
    final held = _clickHeldByDevice[id];
    if (held == null) return;
    for (final event in ZwiftClickProtocol.transitions(previous, current)) {
      if (event.pressed) {
        if (!held.add(event.button)) continue;
        final count = (_clickHeldCounts[event.button] ?? 0) + 1;
        _clickHeldCounts[event.button] = count;
        // The pair mirrors each edge. Emit only the first press observed.
        if (count == 1) _clickButtons.add(event);
      } else {
        if (!held.remove(event.button)) continue;
        final count = (_clickHeldCounts[event.button] ?? 1) - 1;
        if (count <= 0) {
          _clickHeldCounts.remove(event.button);
          _clickButtons.add(event);
        } else {
          _clickHeldCounts[event.button] = count;
        }
      }
    }
  }

  Future<void> _controllerDropped(String id) async {
    await _tearDownController(id, disconnectDevice: false);
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
    _samples.add(
      IndoorRideSample(
        position: frame.position,
        speedKmh: frame.virtualSpeedKmh,
        trainerSpeedKmh: frame.trainerSpeedKmh,
        cadenceRpm: frame.cadenceRpm,
        powerWatts: frame.powerWatts,
        heartRateBpm: frame.heartRateBpm,
        resistanceLevel: frame.resistanceLevel,
        virtualGear: _virtualGear,
        trainerGradePercent: trainerGrade,
      ),
    );
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

  Future<void> disconnectHeartRate() async {
    await _heartRateStateSub?.cancel();
    _heartRateStateSub = null;
    _heartRateConnected = false;
    await _heartRateDataSub?.cancel();
    _heartRateDataSub = null;
    final device = _heartRateDevice;
    _heartRateDevice = null;
    if (device != null) await device.disconnect();
  }

  /// Disconnect one Click V2 pod and release any button it still reported as
  /// held, preventing a mirrored edge from remaining stuck.
  Future<void> disconnectController(String id) =>
      _tearDownController(id, disconnectDevice: true);

  Future<void> disconnectControllers() async {
    for (final id in List<String>.of(_connectedClickDevices.keys)) {
      await disconnectController(id);
    }
  }

  Future<void> _tearDownController(
    String id, {
    required bool disconnectDevice,
  }) async {
    final selected = _connectedClickDevices.remove(id);
    if (selected == null) return;
    _clickKeepalives.remove(id)?.cancel();
    await _clickButtonSubs.remove(id)?.cancel();
    await _clickSyncSubs.remove(id)?.cancel();
    await _clickStateSubs.remove(id)?.cancel();
    _clickWrites.remove(id);
    _clickPreviousBitmaps.remove(id);

    final held = _clickHeldByDevice.remove(id) ?? const <ZwiftClickButton>{};
    for (final button in held) {
      final count = (_clickHeldCounts[button] ?? 1) - 1;
      if (count <= 0) {
        _clickHeldCounts.remove(button);
        _clickButtons.add(
          ZwiftClickButtonEvent(button: button, pressed: false),
        );
      } else {
        _clickHeldCounts[button] = count;
      }
    }
    _clickConnections.add(
      ZwiftClickConnectionEvent(device: selected, connected: false),
    );
    if (disconnectDevice) await selected._device.disconnect();
  }

  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _heartRateScanSub?.cancel();
    await _clickScanSub?.cancel();
    await disconnect();
    await disconnectHeartRate();
    await disconnectControllers();
    await _devices.close();
    await _samples.close();
    await _connection.close();
    await _heartRateDevices.close();
    await _heartRate.close();
    await _heartRateConnection.close();
    await _clickDevices.close();
    await _clickButtons.close();
    await _clickConnections.close();
  }
}

/// Backwards-compatible name for hosts that adopted the 0.1 preview.
typedef RideFollowIndoor = OpenRoad;
