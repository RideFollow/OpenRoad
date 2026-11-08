import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridefollow_indoor/ridefollow_indoor.dart';

GpxRoute routeWithClimb(double elevationGain) => GpxRoute.parse(utf8.encode('''
  <gpx><trk><trkseg>
    <trkpt lat="45.0" lon="9.0"><ele>100</ele></trkpt>
    <trkpt lat="45.01" lon="9.0"><ele>${100 + elevationGain}</ele></trkpt>
  </trkseg></trk></gpx>
'''));

void main() {
  test('moves along a GPX route using power and rider parameters', () {
    final engine = OpenRoadEngine(
      route: routeWithClimb(0),
      parameters: const OpenRoadParameters(
        riderWeightKg: 70,
        bikeWeightKg: 8,
      ),
    );
    const trainer = FtmsBikeData(
      powerWatts: 250,
      cadenceRpm: 90,
      speedKmh: 30,
    );

    OpenRoadFrame? frame;
    for (var i = 0; i < 20; i++) {
      frame = engine.advance(trainer, const Duration(seconds: 1));
    }

    expect(frame!.virtualSpeedKmh, greaterThan(10));
    expect(frame.position.distanceKm, greaterThan(0));
    expect(frame.powerWatts, 250);
    expect(frame.cadenceRpm, 90);
  });

  test('same power is slower uphill than on a flat route', () {
    final flat = OpenRoadEngine(route: routeWithClimb(0));
    final climb = OpenRoadEngine(route: routeWithClimb(100));
    const trainer = FtmsBikeData(powerWatts: 220);

    for (var i = 0; i < 30; i++) {
      flat.advance(trainer, const Duration(seconds: 1));
      climb.advance(trainer, const Duration(seconds: 1));
    }

    expect(climb.virtualSpeedKmh, lessThan(flat.virtualSpeedKmh));
    expect(climb.distanceKm, lessThan(flat.distanceKm));
  });

  test('falls back to trainer speed when power is unavailable', () {
    final engine = OpenRoadEngine(route: routeWithClimb(0));
    final frame = engine.advance(
      const FtmsBikeData(speedKmh: 24),
      const Duration(seconds: 1),
    );
    expect(frame.virtualSpeedKmh, 24);
  });
}
