import 'dart:typed_data';

class FtmsBikeData {
  const FtmsBikeData({
    this.speedKmh,
    this.cadenceRpm,
    this.powerWatts,
    this.resistanceLevel,
    this.heartRateBpm,
  });
  final double? speedKmh;
  final double? cadenceRpm;
  final int? powerWatts;
  final double? resistanceLevel;
  final int? heartRateBpm;

  static FtmsBikeData parse(List<int> value) {
    if (value.length < 2) return const FtmsBikeData();
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final flags = data.getUint16(0, Endian.little);
    var offset = 2;
    double? speed;
    double? cadence;
    int? power;
    double? resistance;
    int? heartRate;
    bool available(int bytes) => offset + bytes <= value.length;
    // Bit 0 means instantaneous speed is NOT present.
    if ((flags & 0x0001) == 0 && available(2)) {
      speed = data.getUint16(offset, Endian.little) / 100;
      offset += 2;
    }
    if ((flags & 0x0002) != 0 && available(2)) offset += 2; // avg speed
    if ((flags & 0x0004) != 0 && available(2)) {
      cadence = data.getUint16(offset, Endian.little) / 2;
      offset += 2;
    }
    if ((flags & 0x0008) != 0 && available(2)) offset += 2; // avg cadence
    if ((flags & 0x0010) != 0 && available(3)) offset += 3; // total distance
    if ((flags & 0x0020) != 0 && available(2)) {
      resistance = data.getInt16(offset, Endian.little) / 10;
      offset += 2;
    }
    if ((flags & 0x0040) != 0 && available(2)) {
      power = data.getInt16(offset, Endian.little);
      offset += 2;
    }
    if ((flags & 0x0080) != 0 && available(2)) offset += 2; // avg power
    if ((flags & 0x0100) != 0 && available(5)) offset += 5; // energy
    if ((flags & 0x0200) != 0 && available(1)) {
      heartRate = data.getUint8(offset);
      offset += 1;
    }
    return FtmsBikeData(
      speedKmh: speed,
      cadenceRpm: cadence,
      powerWatts: power,
      resistanceLevel: resistance,
      heartRateBpm: heartRate,
    );
  }

  /// FTMS Set Indoor Bike Simulation Parameters (opcode 0x11).
  static List<int> simulationParameters(
    double gradePercent, {
    double windSpeedMps = 0,
    double rollingResistance = 0.004,
    double windResistanceKgM = 0.5,
  }) {
    final out = ByteData(7);
    out.setUint8(0, 0x11);
    out.setInt16(
      1,
      (windSpeedMps.clamp(-32.768, 32.767) * 1000).round(),
      Endian.little,
    );
    out.setInt16(3, (gradePercent.clamp(-20, 20) * 100).round(), Endian.little);
    out.setUint8(5, (rollingResistance.clamp(0, 0.0255) * 10000).round());
    out.setUint8(6, (windResistanceKgM.clamp(0, 2.55) * 100).round());
    return out.buffer.asUint8List();
  }
}
