import 'dart:typed_data';

class FtmsBikeData {
  const FtmsBikeData({this.speedKmh, this.cadenceRpm, this.powerWatts});
  final double? speedKmh;
  final double? cadenceRpm;
  final int? powerWatts;

  static FtmsBikeData parse(List<int> value) {
    if (value.length < 2) return const FtmsBikeData();
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final flags = data.getUint16(0, Endian.little);
    var offset = 2;
    double? speed;
    double? cadence;
    int? power;
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
    if ((flags & 0x0020) != 0 && available(2)) offset += 2; // resistance
    if ((flags & 0x0040) != 0 && available(2)) {
      power = data.getInt16(offset, Endian.little);
    }
    return FtmsBikeData(
        speedKmh: speed, cadenceRpm: cadence, powerWatts: power);
  }

  /// FTMS Set Indoor Bike Simulation Parameters (opcode 0x11).
  static List<int> simulationParameters(double gradePercent) {
    final out = ByteData(7);
    out.setUint8(0, 0x11);
    out.setInt16(1, 0, Endian.little); // wind speed, 0.001 m/s
    out.setInt16(3, (gradePercent.clamp(-20, 20) * 100).round(), Endian.little);
    out.setUint8(5, 40); // rolling resistance coefficient 0.004
    out.setUint8(6, 50); // wind resistance coefficient 0.50 kg/m
    return out.buffer.asUint8List();
  }
}
