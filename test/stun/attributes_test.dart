import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/stun/attributes.dart';
import 'package:webrtc_dart/src/stun/const.dart';

void main() {
  group('STUN Attributes', () {
    group('Address packing/unpacking', () {
      test('packs and unpacks IPv4 address', () {
        final address = ('192.168.1.1', 8080);
        final packed = packAddress(address);

        expect(packed, hasLength(8)); // 4 header + 4 address
        expect(packed[1], equals(ipv4Protocol));

        final unpacked = unpackAddress(packed);
        expect(unpacked.$1, equals('192.168.1.1'));
        expect(unpacked.$2, equals(8080));
      });

      test('packs and unpacks IPv6 address', () {
        final address = ('2001:db8::1', 9000);
        final packed = packAddress(address);

        expect(packed, hasLength(20)); // 4 header + 16 address
        expect(packed[1], equals(ipv6Protocol));

        final unpacked = unpackAddress(packed);
        expect(unpacked.$1, equals('2001:db8::1'));
        expect(unpacked.$2, equals(9000));
      });

      test('throws on invalid address data', () {
        final tooShort = Uint8List(3);
        expect(() => unpackAddress(tooShort), throwsArgumentError);
      });
    });

    group('XOR address', () {
      test('XORs address correctly', () {
        final transactionId = Uint8List.fromList(
          List.generate(12, (i) => i),
        );
        final address = ('192.168.1.100', 8080);

        final packed = packAddress(address);
        final xored = xorAddress(packed, transactionId);

        // First 2 bytes should be unchanged
        expect(xored[0], equals(packed[0]));
        expect(xored[1], equals(packed[1]));

        // Rest should be XORed
        expect(xored[2], isNot(equals(packed[2])));

        // Double XOR should return original
        final unxored = xorAddress(xored, transactionId);
        expect(unxored, equals(packed));
      });

      test('packs and unpacks XOR-MAPPED-ADDRESS', () {
        final transactionId = Uint8List.fromList([
          0x01, 0x02, 0x03, 0x04, 0x05, 0x06,
          0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C,
        ]);
        final address = ('10.0.0.1', 3478);

        final packed = packXorAddress(address, transactionId);
        final unpacked = unpackXorAddress(packed, transactionId);

        expect(unpacked.$1, equals('10.0.0.1'));
        expect(unpacked.$2, equals(3478));
      });
    });

    group('Error code', () {
      test('packs and unpacks error code', () {
        final errorCode = (401, 'Unauthorized');
        final packed = packErrorCode(errorCode);

        expect(packed.length, greaterThanOrEqualTo(4));

        final unpacked = unpackErrorCode(packed);
        expect(unpacked.$1, equals(401));
        expect(unpacked.$2, equals('Unauthorized'));
      });

      test('handles different error codes', () {
        final testCases = [
          (300, 'Try Alternate'),
          (400, 'Bad Request'),
          (420, 'Unknown Attribute'),
          (500, 'Server Error'),
        ];

        for (final testCase in testCases) {
          final packed = packErrorCode(testCase);
          final unpacked = unpackErrorCode(packed);
          expect(unpacked.$1, equals(testCase.$1));
          expect(unpacked.$2, equals(testCase.$2));
        }
      });

      test('throws on invalid error code data', () {
        final tooShort = Uint8List(3);
        expect(() => unpackErrorCode(tooShort), throwsArgumentError);
      });
    });

    group('Unsigned integers', () {
      test('packs and unpacks 32-bit unsigned', () {
        final values = [0, 12345, 0xFFFFFFFF];

        for (final value in values) {
          final packed = packUnsigned(value);
          expect(packed, hasLength(4));

          final unpacked = unpackUnsigned(packed);
          expect(unpacked, equals(value));
        }
      });

      test('packs and unpacks 16-bit unsigned', () {
        final values = [0, 1234, 0xFFFF];

        for (final value in values) {
          final packed = packUnsignedShort(value);
          expect(packed, hasLength(4)); // Padded to 4 bytes

          final unpacked = unpackUnsignedShort(packed);
          expect(unpacked, equals(value));
        }
      });

      test('packs and unpacks 64-bit unsigned', () {
        final values = [0, 0x123456789ABCDEF0, 0xFFFFFFFFFFFFFFFF];

        for (final value in values) {
          final packed = packUnsigned64(value);
          expect(packed, hasLength(8));

          final unpacked = unpackUnsigned64(packed);
          expect(unpacked, equals(value));
        }
      });
    });

    group('String attributes', () {
      test('packs and unpacks string', () {
        final values = ['', 'test', 'user@example.com', 'TestString123'];

        for (final value in values) {
          final packed = packString(value);
          final unpacked = unpackString(packed);
          expect(unpacked, equals(value));
        }
      });
    });

    group('Bytes attributes', () {
      test('packs and unpacks bytes', () {
        final values = [
          Uint8List(0),
          Uint8List.fromList([1, 2, 3, 4, 5]),
          Uint8List.fromList(List.generate(256, (i) => i % 256)),
        ];

        for (final value in values) {
          final packed = packBytes(value);
          expect(packed, equals(value));

          final unpacked = unpackBytes(packed);
          expect(unpacked, equals(value));
        }
      });
    });

    group('None attributes (flags)', () {
      test('packs and unpacks none', () {
        final packed = packNone(null);
        expect(packed, hasLength(0));

        final unpacked = unpackNone(packed);
        expect(unpacked, isNull);
      });
    });

    group('Padding', () {
      test('calculates correct padding length', () {
        expect(paddingLength(0), equals(0));
        expect(paddingLength(1), equals(3));
        expect(paddingLength(2), equals(2));
        expect(paddingLength(3), equals(1));
        expect(paddingLength(4), equals(0));
        expect(paddingLength(5), equals(3));
        expect(paddingLength(8), equals(0));
      });
    });

    group('Attribute definitions', () {
      test('all attribute types have definitions', () {
        final requiredTypes = [
          StunAttributeType.username,
          StunAttributeType.messageIntegrity,
          StunAttributeType.fingerprint,
          StunAttributeType.xorMappedAddress,
          StunAttributeType.priority,
          StunAttributeType.useCandidate,
          StunAttributeType.iceControlling,
          StunAttributeType.iceControlled,
        ];

        for (final type in requiredTypes) {
          expect(attributeDefinitions.containsKey(type), isTrue,
              reason: 'Missing definition for ${type.name}');
        }
      });

      test('fromValue returns correct enum', () {
        expect(StunAttributeType.fromValue(0x0001), equals(StunAttributeType.mappedAddress));
        expect(StunAttributeType.fromValue(0x0006), equals(StunAttributeType.username));
        expect(StunAttributeType.fromValue(0x0020), equals(StunAttributeType.xorMappedAddress));
        expect(StunAttributeType.fromValue(0x8028), equals(StunAttributeType.fingerprint));
        expect(StunAttributeType.fromValue(0xFFFF), isNull);
      });
    });

    group('Round-trip tests', () {
      test('round-trips various attribute types', () {
        final transactionId = Uint8List.fromList(List.generate(12, (i) => i));

        final testCases = [
          (StunAttributeType.username, 'testuser', unpackString),
          (StunAttributeType.priority, 98765, unpackUnsigned),
          (StunAttributeType.lifetime, 600, unpackUnsigned),
          (StunAttributeType.software, 'MySTUN/1.0', unpackString),
          (StunAttributeType.iceControlling, BigInt.from(0x123456789ABC), unpackUnsigned64BigInt),
        ];

        for (final (type, value, _) in testCases) {
          final def = attributeDefinitions[type]!;
          final packed = def.pack(value);
          final unpacked = def.unpack(packed, transactionId);
          expect(unpacked, equals(value), reason: 'Failed for ${type.name}');
        }
      });

      test('round-trips address attributes', () {
        final transactionId = Uint8List.fromList(List.generate(12, (i) => i));

        final addresses = [
          ('127.0.0.1', 1234),
          ('192.168.1.1', 8080),
          ('10.0.0.1', 3478),
        ];

        for (final address in addresses) {
          // Regular address
          final packed = packAddress(address);
          final unpacked = unpackAddress(packed);
          expect(unpacked, equals(address));

          // XOR address
          final xorPacked = packXorAddress(address, transactionId);
          final xorUnpacked = unpackXorAddress(xorPacked, transactionId);
          expect(xorUnpacked, equals(address));
        }
      });
    });
  });
}
