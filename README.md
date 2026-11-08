# RideFollow Indoor

RideFollow Indoor provides the **OpenRoad** engine, which turns a GPX file into a virtual road for an indoor bike trainer. It
reads speed, cadence and power from any Bluetooth FTMS trainer and sends the
route's current gradient back as trainer resistance. The rider therefore moves
along the uploaded route without emitting fake GPS from the phone.

The Van Rysel D100 is the reference device. Any trainer advertising the
standard FTMS service (`0x1826`) should work.

## Principles

- local-first: GPX and trainer data do not need a cloud service
- standards-based: Bluetooth FTMS, with no D100-specific lock-in
- embeddable: use the package from Flutter apps such as RideFollow
- honest telemetry: generated positions are explicitly marked indoor/virtual

## Usage

```dart
final road = OpenRoad();
final route = GpxRoute.parse(gpxBytes);
final nextDevices = road.deviceUpdates.firstWhere((list) => list.isNotEmpty);
await road.scan();
final devices = await nextDevices;
await road.connect(devices.first);
road.start(
  route,
  parameters: const OpenRoadParameters(
    riderWeightKg: 72,
    bikeWeightKg: 8.5,
    dragAreaM2: 0.31,
    rollingResistance: 0.004,
  ),
);
road.samples.listen((sample) {
  print('${sample.powerWatts} W at ${sample.position.gradePercent}%');
});
```

On Android the host app must request Bluetooth scan/connect permissions. On
iOS it must provide `NSBluetoothAlwaysUsageDescription`.

## Status

`0.1.0` is an integration preview. It supports FTMS Indoor Bike Data and the
FTMS simulation-parameters control command. Trainers commonly allow only one
Bluetooth controller at a time, so disconnect Zwift or another training app
before connecting RideFollow Indoor.

## Physics model

OpenRoad calculates virtual speed from measured trainer power instead of using
flywheel speed as road speed. It accounts for combined rider/bike mass, GPX
gradient, gravity, rolling resistance, aerodynamic drag, drivetrain efficiency,
air density, and wind. When a trainer does not report power, the FTMS trainer
speed is used as a fallback.

Bluetooth is only an adapter. `OpenRoadEngine` is a pure Dart API and can be
fed from FTMS, recorded data, tests, or a future ANT+ bridge.

## License

MIT

