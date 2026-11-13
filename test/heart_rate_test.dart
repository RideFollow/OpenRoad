import 'package:flutter_test/flutter_test.dart';
import 'package:ridefollow_indoor/ridefollow_indoor.dart';

void main() {
  group('HeartRateMeasurement', () {
    test('parses an 8-bit BPM value', () {
      expect(HeartRateMeasurement.parse([0x00, 147]), 147);
    });

    test('parses a 16-bit BPM value', () {
      expect(HeartRateMeasurement.parse([0x01, 0x2c, 0x01]), 300);
    });

    test('rejects empty, truncated and zero values', () {
      expect(HeartRateMeasurement.parse(const []), isNull);
      expect(HeartRateMeasurement.parse(const [0x01, 0x2c]), isNull);
      expect(HeartRateMeasurement.parse(const [0x00, 0x00]), isNull);
    });
  });
}
