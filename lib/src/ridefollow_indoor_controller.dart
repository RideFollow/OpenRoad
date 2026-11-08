import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ftms.dart';
import 'gpx_route.dart';

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
    this.cadenceRpm,
    this.powerWatts,
  });
  final RoutePosition position;
  final double speedKmh;
  final double? cadenceRpm;
  final int? powerWatts;
}

class RideFollowIndoor {
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
  GpxRoute? _route;
  double _distanceKm = 0;
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

  void start(GpxRoute route) {
    _route = route;
    _distanceKm = 0;
    _lastDataAt = null;
    _lastGrade = null;
  }

  void pause() => _lastDataAt = null;

  void _onBikeData(List<int> value) {
    final route = _route;
    if (route == null) return;
    final bike = FtmsBikeData.parse(value);
    final now = DateTime.now();
    final dt = _lastDataAt == null
        ? 0.0
        : now.difference(_lastDataAt!).inMilliseconds.clamp(0, 3000) / 1000;
    _lastDataAt = now;
    final speed = bike.speedKmh ?? 0;
    _distanceKm = (_distanceKm + speed * dt / 3600).clamp(0, route.distanceKm);
    final position = route.at(_distanceKm);
    _samples.add(IndoorRideSample(
      position: position,
      speedKmh: speed,
      cadenceRpm: bike.cadenceRpm,
      powerWatts: bike.powerWatts,
    ));
    if (_control != null &&
        (_lastGrade == null ||
            (position.gradePercent - _lastGrade!).abs() >= 0.2)) {
      _lastGrade = position.gradePercent;
      unawaited(_control!.write(
        FtmsBikeData.simulationParameters(position.gradePercent),
      ));
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
