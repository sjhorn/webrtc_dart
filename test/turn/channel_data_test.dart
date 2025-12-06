import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/turn/channel_data.dart';

void main() {
  group('ChannelData', () {
    test('encode and decode', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final channelData = ChannelData(
        channelNumber: 0x4000,
        data: data,
      );

      final encoded = channelData.encode();
      expect(encoded.length, 4 + 5); // header + data

      final decoded = ChannelData.decode(encoded);
      expect(decoded.channelNumber, 0x4000);
      expect(decoded.data, data);
    });

    test('validates channel number range', () {
      expect(
        () => ChannelData(channelNumber: 0x3FFF, data: Uint8List(0)),
        throwsArgumentError,
      );

      expect(
        () => ChannelData(channelNumber: 0x8000, data: Uint8List(0)),
        throwsArgumentError,
      );

      // Valid range
      expect(
        () => ChannelData(channelNumber: 0x4000, data: Uint8List(0)),
        returnsNormally,
      );

      expect(
        () => ChannelData(channelNumber: 0x7FFF, data: Uint8List(0)),
        returnsNormally,
      );
    });

    test('isChannelData detection', () {
      // Valid ChannelData (starts with 0x40)
      final channelDataBytes =
          Uint8List.fromList([0x40, 0x00, 0x00, 0x05, 1, 2, 3, 4, 5]);
      expect(ChannelData.isChannelData(channelDataBytes), isTrue);

      // STUN message (starts with 0x00 or 0x01)
      final stunBytes = Uint8List.fromList([0x00, 0x01, 0x00, 0x00]);
      expect(ChannelData.isChannelData(stunBytes), isFalse);

      // Too short
      final shortBytes = Uint8List.fromList([0x40, 0x00]);
      expect(ChannelData.isChannelData(shortBytes), isFalse);
    });

    test('handles different data lengths', () {
      // Empty data
      var cd = ChannelData(channelNumber: 0x4000, data: Uint8List(0));
      var encoded = cd.encode();
      var decoded = ChannelData.decode(encoded);
      expect(decoded.data.length, 0);

      // Large data
      cd = ChannelData(channelNumber: 0x5000, data: Uint8List(1500));
      encoded = cd.encode();
      decoded = ChannelData.decode(encoded);
      expect(decoded.data.length, 1500);
      expect(decoded.channelNumber, 0x5000);
    });

    test('encode produces correct format', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final cd = ChannelData(channelNumber: 0x4123, data: data);

      final encoded = cd.encode();

      // Check channel number (bytes 0-1)
      expect(encoded[0], 0x41);
      expect(encoded[1], 0x23);

      // Check length (bytes 2-3)
      expect(encoded[2], 0x00);
      expect(encoded[3], 0x03);

      // Check data (bytes 4+)
      expect(encoded[4], 0xAA);
      expect(encoded[5], 0xBB);
      expect(encoded[6], 0xCC);
    });

    test('decode validates channel number', () {
      // Invalid channel number in data
      final invalid = Uint8List.fromList([0x3F, 0xFF, 0x00, 0x00]);
      expect(() => ChannelData.decode(invalid), throwsArgumentError);
    });

    test('decode validates data length', () {
      // Says it has 10 bytes but only provides 5
      final incomplete = Uint8List.fromList([
        0x40, 0x00, // channel
        0x00, 0x0A, // length = 10
        1, 2, 3, 4, 5 // only 5 bytes
      ]);
      expect(() => ChannelData.decode(incomplete), throwsArgumentError);
    });

    test('toString provides useful info', () {
      final cd = ChannelData(
        channelNumber: 0x4ABC,
        data: Uint8List(123),
      );
      final str = cd.toString();
      expect(str, contains('0x4abc'));
      expect(str, contains('123'));
    });
  });
}
