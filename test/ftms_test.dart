import 'package:flutter_test/flutter_test.dart';
import 'package:ridefollow_indoor/ridefollow_indoor.dart';

void main() {
  test('parses FTMS speed cadence power and heart rate', () {
    final data = FtmsBikeData.parse([
      0x44, 0x02, // cadence + power + heart-rate flags
      0xc4, 0x09, // 25.00 km/h
      0xb4, 0x00, // 90 rpm (180 / 2)
      0xfa, 0x00, // 250 W
      0x96, // 150 bpm
    ]);
    expect(data.speedKmh, 25);
    expect(data.cadenceRpm, 90);
    expect(data.powerWatts, 250);
    expect(data.heartRateBpm, 150);
  });

  test('encodes simulation grade', () {
    expect(FtmsBikeData.simulationParameters(5).sublist(0, 5),
        [0x11, 0, 0, 0xf4, 0x01]);
  });
}
