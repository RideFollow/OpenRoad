/// The two physical sides in a Zwift Click V2 pair.
enum ZwiftClickSide { left, right, unknown }

/// Buttons exposed by the Click V2 protocol.
enum ZwiftClickButton {
  left,
  up,
  right,
  down,
  a,
  b,
  y,
  z,
  minus,
  plus,
}

/// One edge from a Click V2 button.
class ZwiftClickButtonEvent {
  const ZwiftClickButtonEvent({
    required this.button,
    required this.pressed,
  });

  final ZwiftClickButton button;
  final bool pressed;
}

/// Protocol facts and pure decoders for Zwift Click V2 controllers.
///
/// Zwift does not publish this protocol. These values are based on the
/// interoperable, MIT-licensed `zwiftboard` implementation. The decoder is
/// intentionally kept independent from Bluetooth so hosts can test it without
/// controller hardware.
abstract final class ZwiftClickProtocol {
  static const int companyId = 0x094a;
  static const int rightDeviceId = 0x0a;
  static const int leftDeviceId = 0x0b;
  static const int buttonFrame = 0x23;

  static const List<int> activate = <int>[
    0x52,
    0x69,
    0x64,
    0x65,
    0x4f,
    0x6e,
    0x02,
    0x03,
  ];
  static const List<int> rideOn = <int>[
    0x52,
    0x69,
    0x64,
    0x65,
    0x4f,
    0x6e,
  ];
  static const List<int> setupOne = <int>[0x00, 0x08, 0x00];
  static const List<int> setupTwo = <int>[0x00, 0x08, 0x10];
  static const List<int> challengeAck = <int>[0xff, 0x04, 0x00];

  static const Map<int, ZwiftClickButton> buttonBits = {
    0x00001: ZwiftClickButton.left,
    0x00002: ZwiftClickButton.up,
    0x00004: ZwiftClickButton.right,
    0x00008: ZwiftClickButton.down,
    0x00010: ZwiftClickButton.a,
    0x00020: ZwiftClickButton.b,
    0x00040: ZwiftClickButton.y,
    0x00080: ZwiftClickButton.z,
    0x00100: ZwiftClickButton.minus,
    0x01000: ZwiftClickButton.plus,
  };

  static int get knownButtonMask =>
      buttonBits.keys.fold(0, (mask, bit) => mask | bit);

  static ZwiftClickSide sideFromManufacturerData(List<int>? data) {
    if (data == null || data.isEmpty) return ZwiftClickSide.unknown;
    return switch (data.first) {
      leftDeviceId => ZwiftClickSide.left,
      rightDeviceId => ZwiftClickSide.right,
      _ => ZwiftClickSide.unknown,
    };
  }

  /// Extract protobuf field 1 (a varint button bitmap) from a 0x23 frame.
  /// A zero button bit means pressed.
  static int? decodeBitmap(List<int> frame) {
    if (frame.isEmpty || frame.first != buttonFrame) return null;
    var index = 1;
    while (index < frame.length) {
      final tag = _readVarint(frame, index);
      if (tag == null) return null;
      index = tag.next;
      final field = tag.value >> 3;
      final wireType = tag.value & 7;
      switch (wireType) {
        case 0:
          final value = _readVarint(frame, index);
          if (value == null) return null;
          index = value.next;
          if (field == 1) return value.value;
        case 1:
          index += 8;
        case 2:
          final length = _readVarint(frame, index);
          if (length == null) return null;
          index = length.next + length.value;
        case 5:
          index += 4;
        default:
          return null;
      }
      if (index > frame.length) return null;
    }
    return null;
  }

  /// Return only the button edges between two Click V2 bitmaps.
  static List<ZwiftClickButtonEvent> transitions(int previous, int current) {
    final changed = (previous ^ current) & knownButtonMask;
    if (changed == 0) return const [];
    final events = <ZwiftClickButtonEvent>[];
    for (final entry in buttonBits.entries) {
      if (changed & entry.key == 0) continue;
      events.add(
        ZwiftClickButtonEvent(
          button: entry.value,
          pressed: current & entry.key == 0,
        ),
      );
    }
    return events;
  }

  static _Varint? _readVarint(List<int> bytes, int start) {
    var value = 0;
    var shift = 0;
    for (var index = start; index < bytes.length && shift < 70; index++) {
      final byte = bytes[index];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return _Varint(value, index + 1);
      shift += 7;
    }
    return null;
  }
}

class _Varint {
  const _Varint(this.value, this.next);
  final int value;
  final int next;
}
