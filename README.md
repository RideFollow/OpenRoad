# RideFollow Indoor

RideFollow Indoor turns a GPX file into a virtual road for an indoor bike trainer. It
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
final road = RideFollowIndoor();
final route = GpxRoute.parse(gpxBytes);
await road.scan();
final devices = await road.deviceUpdates.firstWhere((list) => list.isNotEmpty);
await road.connect(devices.first);
road.start(route);
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

## License

MIT

