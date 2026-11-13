# RideFollow Indoor

RideFollow Indoor provides the **OpenRoad** engine, which turns a GPX file into a virtual road for an indoor bike trainer. It
reads speed, cadence and power from any Bluetooth FTMS trainer and sends the
route's current gradient back as trainer resistance. The rider therefore moves
along the uploaded route without emitting fake GPS from the phone.

It can also connect to a standard Bluetooth Heart Rate Service (`0x180D`),
including Garmin watches with **Broadcast Heart Rate** enabled and BLE straps.

The Van Rysel D100 is the reference device. Any trainer advertising the
standard FTMS service (`0x1826`) should work.

Zwift Hub, Zwift Ready, and Zwift Cog Compatible trainers can be used when they
expose Bluetooth FTMS. OpenRoad includes independent 24-speed virtual gearing
for fixed-sprocket/Cog setups. Zwift Click V2 controller pairs are supported as
separate Bluetooth accessories. Zwift Play and Ride controllers are not yet
claimed as compatible.

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

// Optional Garmin watch / BLE heart-rate monitor.
final nextHeartRateDevices =
    road.heartRateDeviceUpdates.firstWhere((list) => list.isNotEmpty);
await road.scanHeartRateMonitors();
final heartRateDevices = await nextHeartRateDevices;
await road.connectHeartRate(heartRateDevices.first);
road.heartRateUpdates.listen((bpm) => print('$bpm bpm'));

// Optional Zwift Click V2 pair. Wake both pods before scanning, then connect
// each discovered side. The pair mirrors frames; OpenRoad emits one edge.
final nextControllers =
    road.controllerDeviceUpdates.firstWhere((list) => list.isNotEmpty);
await road.scanControllers();
for (final controller in await nextControllers) {
  await road.connectController(controller);
}
road.controllerButtonUpdates.listen((event) {
  if (!event.pressed) return;
  if (event.button == ZwiftClickButton.plus) road.shiftUp();
  if (event.button == ZwiftClickButton.minus ||
      event.button == ZwiftClickButton.b) {
    road.shiftDown();
  }
});
```

On Android the host app must request Bluetooth scan/connect permissions. On
iOS it must provide `NSBluetoothAlwaysUsageDescription`.

## Status

`0.6.0` supports FTMS Indoor Bike Data, the FTMS simulation-parameters control
command, standard BLE heart-rate monitors, and Zwift Click V2 controller pairs.
Trainers commonly allow only one Bluetooth controller at a time, so disconnect
Zwift or another training app before connecting RideFollow Indoor.

Click V2 interoperability follows the public protocol facts documented by the
MIT-licensed [zwiftboard](https://github.com/thomaschampagne/zwiftboard)
project. It does not bypass or reproduce Zwift's server-signed left-pod unlock;
the right pod's `+` and `B` buttons provide reliable two-way shifting without
that service.

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

