import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/header_extension.dart';

void main() {
  group('RTP Header Extensions', () {
    group('SDES MID', () {
      test('serialize', () {
        final data = serializeSdesMid('0');
        expect(data, equals(Uint8List.fromList([0x30]))); // ASCII '0'
      });

      test('deserialize', () {
        final mid = deserializeSdesMid(Uint8List.fromList([0x30]));
        expect(mid, equals('0'));
      });

      test('round-trip', () {
        final original = 'test-mid-123';
        final serialized = serializeSdesMid(original);
        final deserialized = deserializeSdesMid(serialized);
        expect(deserialized, equals(original));
      });
    });

    group('SDES RTP Stream ID (RID)', () {
      test('serialize', () {
        final data = serializeSdesRtpStreamId('high');
        expect(data, equals(Uint8List.fromList([0x68, 0x69, 0x67, 0x68])));
      });

      test('deserialize', () {
        final rid = deserializeSdesRtpStreamId(
            Uint8List.fromList([0x68, 0x69, 0x67, 0x68]));
        expect(rid, equals('high'));
      });

      test('round-trip', () {
        final original = 'low';
        final serialized = serializeSdesRtpStreamId(original);
        final deserialized = deserializeSdesRtpStreamId(serialized);
        expect(deserialized, equals(original));
      });
    });

    group('Transport-Wide CC', () {
      test('serialize', () {
        final data = serializeTransportWideCC(0x1234);
        expect(data, equals(Uint8List.fromList([0x12, 0x34])));
      });

      test('deserialize', () {
        final seqNum =
            deserializeTransportWideCC(Uint8List.fromList([0x12, 0x34]));
        expect(seqNum, equals(0x1234));
      });

      test('round-trip', () {
        for (final value in [0, 1, 255, 256, 65534, 65535]) {
          final serialized = serializeTransportWideCC(value);
          final deserialized = deserializeTransportWideCC(serialized);
          expect(deserialized, equals(value));
        }
      });

      test('wraparound', () {
        final data = serializeTransportWideCC(65536);
        expect(deserializeTransportWideCC(data), equals(0)); // Wraps
      });
    });

    group('Audio Level', () {
      test('serialize with voice', () {
        final data = serializeAudioLevel(voice: true, level: 50);
        expect(data, equals(Uint8List.fromList([0xB2]))); // 1 bit + 50
      });

      test('serialize without voice', () {
        final data = serializeAudioLevel(voice: false, level: 50);
        expect(data, equals(Uint8List.fromList([0x32]))); // 0 bit + 50
      });

      test('deserialize', () {
        final result = deserializeAudioLevel(Uint8List.fromList([0xB2]));
        expect(result.voice, isTrue);
        expect(result.level, equals(50));
      });

      test('round-trip', () {
        for (final voice in [true, false]) {
          for (final level in [0, 1, 63, 127]) {
            final serialized = serializeAudioLevel(voice: voice, level: level);
            final result = deserializeAudioLevel(serialized);
            expect(result.voice, equals(voice));
            expect(result.level, equals(level));
          }
        }
      });
    });

    group('Absolute Send Time', () {
      test('serialize', () {
        final data = serializeAbsoluteSendTime(0x123456);
        expect(data, equals(Uint8List.fromList([0x12, 0x34, 0x56])));
      });

      test('deserialize', () {
        final timestamp =
            deserializeAbsoluteSendTime(Uint8List.fromList([0x12, 0x34, 0x56]));
        expect(timestamp, equals(0x123456));
      });

      test('round-trip', () {
        for (final value in [0, 1, 0xFFFFFF, 0x800000]) {
          final serialized = serializeAbsoluteSendTime(value);
          final deserialized = deserializeAbsoluteSendTime(serialized);
          expect(deserialized, equals(value));
        }
      });
    });

    group('parseRtpExtensions', () {
      test('parse MID extension', () {
        // One-byte header: ID=1, L=0 (length=1), data='0'
        final extData = Uint8List.fromList([0x10, 0x30, 0x00, 0x00]);
        final idToUri = {1: RtpExtensionUri.sdesMid};

        final extensions = parseRtpExtensions(extData, idToUri);

        expect(extensions[RtpExtensionUri.sdesMid], equals('0'));
      });

      test('parse RID extension', () {
        // One-byte header: ID=2, L=3 (length=4), data='high'
        final extData = Uint8List.fromList(
            [0x23, 0x68, 0x69, 0x67, 0x68, 0x00, 0x00, 0x00]);
        final idToUri = {2: RtpExtensionUri.sdesRtpStreamId};

        final extensions = parseRtpExtensions(extData, idToUri);

        expect(extensions[RtpExtensionUri.sdesRtpStreamId], equals('high'));
      });

      test('parse TWCC extension', () {
        // One-byte header: ID=3, L=1 (length=2), data=0x1234
        final extData = Uint8List.fromList([0x31, 0x12, 0x34, 0x00]);
        final idToUri = {3: RtpExtensionUri.transportWideCC};

        final extensions = parseRtpExtensions(extData, idToUri);

        expect(extensions[RtpExtensionUri.transportWideCC], equals(0x1234));
      });

      test('parse multiple extensions', () {
        // MID=1 ('0'), RID=2 ('hi'), TWCC=3 (0x0001)
        final extData = Uint8List.fromList([
          0x10, 0x30, // MID: ID=1, L=0, '0'
          0x21, 0x68, 0x69, // RID: ID=2, L=1, 'hi'
          0x31, 0x00, 0x01, // TWCC: ID=3, L=1, 0x0001
          0x00, // padding
        ]);
        final idToUri = {
          1: RtpExtensionUri.sdesMid,
          2: RtpExtensionUri.sdesRtpStreamId,
          3: RtpExtensionUri.transportWideCC,
        };

        final extensions = parseRtpExtensions(extData, idToUri);

        expect(extensions[RtpExtensionUri.sdesMid], equals('0'));
        expect(extensions[RtpExtensionUri.sdesRtpStreamId], equals('hi'));
        expect(extensions[RtpExtensionUri.transportWideCC], equals(1));
      });

      test('skip unknown extensions', () {
        // Unknown ID=5
        final extData = Uint8List.fromList([0x50, 0xFF, 0x00, 0x00]);
        final idToUri = {1: RtpExtensionUri.sdesMid};

        final extensions = parseRtpExtensions(extData, idToUri);

        expect(extensions, isEmpty);
      });

      test('handle padding bytes', () {
        // MID followed by padding
        final extData = Uint8List.fromList([0x10, 0x30, 0x00, 0x00]);
        final idToUri = {1: RtpExtensionUri.sdesMid};

        final extensions = parseRtpExtensions(extData, idToUri);

        expect(extensions[RtpExtensionUri.sdesMid], equals('0'));
      });
    });

    group('buildRtpExtensions', () {
      test('build MID extension', () {
        final extensions = {RtpExtensionUri.sdesMid: '0'};
        final uriToId = {RtpExtensionUri.sdesMid: 1};

        final data = buildRtpExtensions(extensions, uriToId);

        // ID=1, L=0, '0', padding
        expect(data, equals(Uint8List.fromList([0x10, 0x30, 0x00, 0x00])));
      });

      test('build TWCC extension', () {
        final extensions = {RtpExtensionUri.transportWideCC: 0x1234};
        final uriToId = {RtpExtensionUri.transportWideCC: 3};

        final data = buildRtpExtensions(extensions, uriToId);

        // ID=3, L=1, 0x12, 0x34
        expect(data, equals(Uint8List.fromList([0x31, 0x12, 0x34, 0x00])));
      });

      test('build multiple extensions', () {
        final extensions = {
          RtpExtensionUri.sdesMid: 'a',
          RtpExtensionUri.transportWideCC: 1,
        };
        final uriToId = {
          RtpExtensionUri.sdesMid: 1,
          RtpExtensionUri.transportWideCC: 3,
        };

        final data = buildRtpExtensions(extensions, uriToId);

        expect(data.length % 4, equals(0)); // Must be 4-byte aligned
        expect(data.length, greaterThan(0));
      });

      test('round-trip', () {
        final original = {
          RtpExtensionUri.sdesMid: 'test',
          RtpExtensionUri.sdesRtpStreamId: 'high',
          RtpExtensionUri.transportWideCC: 12345,
        };
        final mapping = {
          RtpExtensionUri.sdesMid: 1,
          RtpExtensionUri.sdesRtpStreamId: 2,
          RtpExtensionUri.transportWideCC: 3,
        };
        final reverseMapping = {
          1: RtpExtensionUri.sdesMid,
          2: RtpExtensionUri.sdesRtpStreamId,
          3: RtpExtensionUri.transportWideCC,
        };

        final built = buildRtpExtensions(original, mapping);
        final parsed = parseRtpExtensions(built, reverseMapping);

        expect(parsed[RtpExtensionUri.sdesMid], equals('test'));
        expect(parsed[RtpExtensionUri.sdesRtpStreamId], equals('high'));
        expect(parsed[RtpExtensionUri.transportWideCC], equals(12345));
      });
    });
  });
}
