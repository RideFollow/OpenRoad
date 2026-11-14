import 'package:flutter_test/flutter_test.dart';
import 'package:ridefollow_indoor/ridefollow_indoor.dart';

void main() {
  group('ZwiftClickProtocol', () {
    test('identifies left and right pods from manufacturer data', () {
      expect(
        ZwiftClickProtocol.sideFromManufacturerData(const [0x0b]),
        ZwiftClickSide.left,
      );
      expect(
        ZwiftClickProtocol.sideFromManufacturerData(const [0x0a]),
        ZwiftClickSide.right,
      );
      expect(
        ZwiftClickProtocol.sideFromManufacturerData(const [0xff]),
        ZwiftClickSide.unknown,
      );
    });

    test('decodes protobuf button bitmap while skipping other fields', () {
      const bitmap = 0x11ff;
      final frame = <int>[
        ZwiftClickProtocol.buttonFrame,
        0x12,
        0x02,
        0xaa,
        0xbb,
        0x08,
        ..._varint(bitmap),
      ];
      expect(ZwiftClickProtocol.decodeBitmap(frame), bitmap);
      expect(ZwiftClickProtocol.decodeBitmap(const [0x19, 0x08, 0]), isNull);
    });

    test('emits press and release edges only once', () {
      final released = ZwiftClickProtocol.knownButtonMask;
      final plusPressed = released & ~0x01000;
      final down = ZwiftClickProtocol.transitions(
        released,
        plusPressed,
      ).single;
      expect(down.button, ZwiftClickButton.plus);
      expect(down.pressed, isTrue);
      expect(ZwiftClickProtocol.transitions(plusPressed, plusPressed), isEmpty);
      final up = ZwiftClickProtocol.transitions(plusPressed, released).single;
      expect(up.button, ZwiftClickButton.plus);
      expect(up.pressed, isFalse);
    });

    test('decodes B and minus as separate controller buttons', () {
      final released = ZwiftClickProtocol.knownButtonMask;
      final pressed = released & ~0x00020 & ~0x00100;
      final events = ZwiftClickProtocol.transitions(released, pressed);
      expect(
        events.map((event) => event.button),
        containsAll([ZwiftClickButton.b, ZwiftClickButton.minus]),
      );
      expect(events.every((event) => event.pressed), isTrue);
    });

    test('connection errors identify the failing setup stage', () {
      const error = ZwiftClickConnectionException(
        ZwiftClickConnectionStage.notifications,
        'notifications unavailable',
      );
      expect(error.stageLabel, 'controller notifications');
      expect(error.toString(), contains('notifications unavailable'));
    });
  });
}

List<int> _varint(int value) {
  final result = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) byte |= 0x80;
    result.add(byte);
  } while (remaining != 0);
  return result;
}
