import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/opus.dart';

void main() {
  group('OpusRtpPayload', () {
    test('deserializes payload', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);

      final opus = OpusRtpPayload.deserialize(payload);

      expect(opus.payload, equals(payload));
    });

    test('serializes payload', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final opus = OpusRtpPayload(payload: payload);

      final serialized = opus.serialize();

      expect(serialized, equals(payload));
    });

    test('round-trips payload', () {
      final original = Uint8List.fromList([10, 20, 30, 40, 50]);

      final opus = OpusRtpPayload.deserialize(original);
      final serialized = opus.serialize();

      expect(serialized, equals(original));
    });

    test('is always keyframe', () {
      final opus = OpusRtpPayload(payload: Uint8List(10));

      expect(opus.isKeyframe, isTrue);
    });

    test('creates codec private data', () {
      final codecPrivate = OpusRtpPayload.createCodecPrivate();

      // Should be 19 bytes
      expect(codecPrivate.length, 19);

      // Should start with "OpusHead" magic signature
      final signature = String.fromCharCodes(codecPrivate.sublist(0, 8));
      expect(signature, 'OpusHead');

      // Version should be 1
      expect(codecPrivate[8], 1);

      // Channel count should be 2 (stereo)
      expect(codecPrivate[9], 2);
    });

    test('creates codec private data with custom sample rate', () {
      final codecPrivate =
          OpusRtpPayload.createCodecPrivate(samplingFrequency: 24000);

      final view = ByteData.sublistView(codecPrivate);

      // Sample rate at offset 12 (little-endian)
      final sampleRate = view.getUint32(12, Endian.little);
      expect(sampleRate, 24000);
    });

    test('codec private data has correct structure', () {
      final codecPrivate = OpusRtpPayload.createCodecPrivate();
      final view = ByteData.sublistView(codecPrivate);

      // Pre-skip at offset 10 (little-endian) should be 312
      final preSkip = view.getUint16(10, Endian.little);
      expect(preSkip, 312);

      // Sample rate at offset 12 (little-endian) should be 48000
      final sampleRate = view.getUint32(12, Endian.little);
      expect(sampleRate, 48000);

      // Output gain at offset 16 (little-endian) should be 0
      final outputGain = view.getUint16(16, Endian.little);
      expect(outputGain, 0);

      // Channel mapping family at offset 18 should be 0
      expect(codecPrivate[18], 0);
    });

    test('handles empty payload', () {
      final opus = OpusRtpPayload(payload: Uint8List(0));

      expect(opus.payload.length, 0);
      expect(opus.serialize().length, 0);
    });

    test('handles large payload', () {
      final largePayload = Uint8List(1000);
      for (var i = 0; i < 1000; i++) {
        largePayload[i] = i % 256;
      }

      final opus = OpusRtpPayload.deserialize(largePayload);

      expect(opus.payload.length, 1000);
      expect(opus.serialize(), equals(largePayload));
    });
  });
}
