import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/processor/mute_handler.dart';

void main() {
  group('MuteHandler', () {
    test('creates with unique ID', () {
      final outputs = <MuteOutput>[];
      final handler = MuteHandler(
        output: outputs.add,
        options: MuteHandlerOptions(
          ptime: 20,
          dummyPacket: Uint8List.fromList([0xF8, 0xFF, 0xFE]),
        ),
      );

      expect(handler.id, isNotEmpty);
      expect(handler.id.length, equals(36)); // UUID format
      expect(handler.ended, isFalse);
    });

    test('processes first frame and initializes base time', () {
      final outputs = <MuteOutput>[];
      final handler = MuteHandler(
        output: outputs.add,
        options: MuteHandlerOptions(
          ptime: 20,
          dummyPacket: Uint8List.fromList([0xF8, 0xFF, 0xFE]),
        ),
      );

      final frame = MuteFrame(
        data: Uint8List.fromList([1, 2, 3]),
        isKeyframe: true,
        timeMs: 1000,
      );

      final result = handler.processInput(MuteInput(frame: frame));
      expect(result, isEmpty); // Buffered, not yet output
    });

    test('drops frames from the past', () {
      final outputs = <MuteOutput>[];
      final handler = MuteHandler(
        output: outputs.add,
        options: MuteHandlerOptions(
          ptime: 20,
          dummyPacket: Uint8List.fromList([0xF8, 0xFF, 0xFE]),
          interval: 100,
        ),
      );

      // First frame at 1000ms
      handler.processInput(MuteInput(
        frame: MuteFrame(data: Uint8List(10), isKeyframe: true, timeMs: 1000),
      ));

      // Advance time to trigger task execution
      handler.processInput(MuteInput(
        frame: MuteFrame(data: Uint8List(10), isKeyframe: false, timeMs: 1200),
      ));

      // Try to add frame from the past
      final result = handler.processInput(MuteInput(
        frame: MuteFrame(data: Uint8List(10), isKeyframe: false, timeMs: 900),
      ));

      expect(result, isEmpty); // Dropped
    });

    test('stops on null frame', () {
      final outputs = <MuteOutput>[];
      final handler = MuteHandler(
        output: outputs.add,
        options: MuteHandlerOptions(
          ptime: 20,
          dummyPacket: Uint8List.fromList([0xF8, 0xFF, 0xFE]),
        ),
      );

      final result = handler.processInput(MuteInput(frame: null, eol: true));
      expect(result.length, equals(1));
      expect(result.first.eol, isTrue);
      expect(handler.ended, isTrue);
    });

    test('returns empty after ended', () {
      final outputs = <MuteOutput>[];
      final handler = MuteHandler(
        output: outputs.add,
        options: MuteHandlerOptions(
          ptime: 20,
          dummyPacket: Uint8List.fromList([0xF8, 0xFF, 0xFE]),
        ),
      );

      // End the handler
      handler.processInput(MuteInput(frame: null, eol: true));

      // Try to add more frames
      final result = handler.processInput(MuteInput(
        frame: MuteFrame(data: Uint8List(10), isKeyframe: true, timeMs: 1000),
      ));

      expect(result, isEmpty);
    });

    test('toJson includes id', () {
      final outputs = <MuteOutput>[];
      final handler = MuteHandler(
        output: outputs.add,
        options: MuteHandlerOptions(
          ptime: 20,
          dummyPacket: Uint8List.fromList([0xF8, 0xFF, 0xFE]),
        ),
      );

      final json = handler.toJson();
      expect(json['id'], equals(handler.id));
    });
  });

  group('MuteHandlerOptions', () {
    test('has correct defaults', () {
      final options = MuteHandlerOptions(
        ptime: 20,
        dummyPacket: Uint8List(0),
      );

      expect(options.interval, equals(1000));
      expect(options.bufferLength, equals(10));
    });
  });

  group('MuteFrame', () {
    test('stores properties correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final frame = MuteFrame(
        data: data,
        isKeyframe: true,
        timeMs: 12345,
      );

      expect(frame.data, equals(data));
      expect(frame.isKeyframe, isTrue);
      expect(frame.timeMs, equals(12345));
    });
  });

  group('MuteInput', () {
    test('defaults eol to false', () {
      final input = MuteInput(
        frame: MuteFrame(data: Uint8List(5), isKeyframe: false, timeMs: 0),
      );

      expect(input.eol, isFalse);
    });

    test('supports null frame with eol', () {
      final input = MuteInput(frame: null, eol: true);
      expect(input.frame, isNull);
      expect(input.eol, isTrue);
    });
  });

  group('OpusMuteHandler', () {
    test('creates handler with Opus silence packet', () {
      final outputs = <MuteOutput>[];
      final handler = OpusMuteHandler.create(
        output: outputs.add,
        ptime: 20,
      );

      expect(handler.id, isNotEmpty);
      expect(handler.options.ptime, equals(20));
      // Opus silence packet is [0xF8, 0xFF, 0xFE]
      expect(handler.options.dummyPacket, equals([0xF8, 0xFF, 0xFE]));
    });

    test('accepts custom interval and buffer length', () {
      final outputs = <MuteOutput>[];
      final handler = OpusMuteHandler.create(
        output: outputs.add,
        interval: 500,
        bufferLength: 5,
      );

      expect(handler.options.interval, equals(500));
      expect(handler.options.bufferLength, equals(5));
    });
  });
}
