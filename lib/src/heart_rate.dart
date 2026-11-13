import 'dart:typed_data';

/// Parser for the Bluetooth Heart Rate Measurement characteristic (0x2A37).
class HeartRateMeasurement {
  const HeartRateMeasurement._();

  /// Returns the reported beats per minute, or `null` for a truncated/invalid
  /// packet. Bit 0 selects the Bluetooth-defined 8- or 16-bit value format.
  static int? parse(List<int> value) {
    if (value.length < 2) return null;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    final sixteenBit = (data.getUint8(0) & 0x01) != 0;
    if (sixteenBit && value.length < 3) return null;
    final bpm =
        sixteenBit ? data.getUint16(1, Endian.little) : data.getUint8(1);
    return bpm > 0 ? bpm : null;
  }
}
