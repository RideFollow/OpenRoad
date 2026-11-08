import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridefollow_indoor/ridefollow_indoor.dart';

void main() {
  test('parses and interpolates a GPX route', () {
    final route = GpxRoute.parse(utf8.encode('''
      <gpx><trk><trkseg>
        <trkpt lat="45.0" lon="9.0"><ele>100</ele></trkpt>
        <trkpt lat="45.01" lon="9.0"><ele>150</ele></trkpt>
      </trkseg></trk></gpx>
    '''));
    expect(route.distanceKm, greaterThan(1));
    final middle = route.at(route.distanceKm / 2);
    expect(middle.point.latitude, closeTo(45.005, 0.0001));
    expect(middle.point.elevationM, closeTo(125, 1));
    expect(middle.progress, closeTo(0.5, 0.01));
  });
}
