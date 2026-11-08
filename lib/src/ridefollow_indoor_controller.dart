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
  });
  final RoutePosition position;
  final double speedKmh;
  final double? trainerSpeedKmh;
  final double? cadenceRpm;
  final int? powerWatts;
  final int? heartRateBpm;
  final double? resistanceLevel;
}

/// Bluetooth FTMS adapter around the pure [OpenRoadEngine].
class OpenRoad {
  static final Guid _ftms = Guid('1826');
  static final Guid _bikeData = Guid('2ad2');
  static final Guid _controlPoint = Guid('2ad9');

  final _devices = StreamController<List<IndoorTrainerDevice>>.broadcast();
  final _samples = StreamController<IndoorRideSample>.broadcast();
  Stream<List<IndoorTrainerDevice>> get deviceUpdates => _devices.stream;
  Stream<IndoorRideSample> get samples => _samples.stream;

  final Map<String, IndoorTrainerDevice> _found = {};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _dataSub;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  OpenRoadEngine? _engine;
  DateTime? _lastDataAt;
  double? _lastGrade;

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
    _device = selected._device;
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
    if (_control != null) {
      await _control!.setNotifyValue(true);
      await _control!.write([0x00]); // request control
      await _control!.write([0x07]); // start/resume
    }
  }

  void start(
    GpxRoute route, {
    OpenRoadParameters parameters = const OpenRoadParameters(),
  }) {
    _engine = OpenRoadEngine(route: route, parameters: parameters);
    _lastDataAt = null;
    _lastGrade = null;
  }

  void pause() => _lastDataAt = null;

  void _onBikeData(List<int> value) {
    final engine = _engine;
    if (engine == null) return;
    final bike = FtmsBikeData.parse(value);
    final now = DateTime.now();
    final elapsed =
        _lastDataAt == null ? Duration.zero : now.difference(_lastDataAt!);
    _lastDataAt = now;
    final frame = engine.advance(bike, elapsed);
    _samples.add(IndoorRideSample(
      position: frame.position,
      speedKmh: frame.virtualSpeedKmh,
      trainerSpeedKmh: frame.trainerSpeedKmh,
      cadenceRpm: frame.cadenceRpm,
      powerWatts: frame.powerWatts,
      heartRateBpm: frame.heartRateBpm,
      resistanceLevel: frame.resistanceLevel,
    ));
    if (_control != null &&
        (_lastGrade == null ||
            (frame.position.gradePercent - _lastGrade!).abs() >= 0.2)) {
      _lastGrade = frame.position.gradePercent;
      final parameters = engine.parameters;
      unawaited(
        _control!.write(
          FtmsBikeData.simulationParameters(
            frame.position.gradePercent,
            windSpeedMps: parameters.windSpeedMps,
            rollingResistance: parameters.rollingResistance,
            windResistanceKgM: parameters.ftmsWindResistanceKgM,
          ),
        ),
      );
    }
  }

  Future<void> disconnect() async {
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
  }
}

/// Backwards-compatible name for hosts that adopted the 0.1 preview.
typedef RideFollowIndoor = OpenRoad;
