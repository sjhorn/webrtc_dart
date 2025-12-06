import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/stun/attributes.dart';
import 'package:webrtc_dart/src/stun/const.dart';
import 'package:webrtc_dart/src/stun/message.dart';

void main() {
  group('STUN Message', () {
    test('creates message with random transaction ID', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      expect(msg.transactionId, hasLength(12));
      expect(msg.method, equals(StunMethod.binding));
      expect(msg.messageClass, equals(StunClass.request));
    });

    test('creates message with specific transaction ID', () {
      final tid = Uint8List.fromList(List.generate(12, (i) => i));
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
        transactionId: tid,
      );

      expect(msg.transactionId, equals(tid));
      expect(msg.transactionIdHex, equals('000102030405060708090a0b'));
    });

    test('computes correct message type', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      expect(msg.messageType, equals(0x0001)); // BINDING REQUEST
    });

    test('sets and gets attributes', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      msg.setAttribute(StunAttributeType.username, 'testuser');
      expect(msg.getAttribute(StunAttributeType.username), equals('testuser'));
      expect(msg.hasAttribute(StunAttributeType.username), isTrue);

      msg.removeAttribute(StunAttributeType.username);
      expect(msg.hasAttribute(StunAttributeType.username), isFalse);
    });

    test('serializes simple binding request', () {
      final tid = Uint8List.fromList([
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0A,
        0x0B,
        0x0C,
      ]);

      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
        transactionId: tid,
      );

      final bytes = msg.toBytes();

      expect(bytes, hasLength(20)); // Header only, no attributes
      expect(bytes[0], equals(0x00)); // Message type high byte
      expect(bytes[1], equals(0x01)); // Message type low byte (BINDING REQUEST)
      expect(bytes[2], equals(0x00)); // Length high byte
      expect(bytes[3], equals(0x00)); // Length low byte (no attributes)

      // Verify magic cookie
      expect(bytes[4], equals(0x21));
      expect(bytes[5], equals(0x12));
      expect(bytes[6], equals(0xA4));
      expect(bytes[7], equals(0x42));

      // Verify transaction ID
      expect(bytes.sublist(8, 20), equals(tid));
    });

    test('serializes message with attributes', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      msg.setAttribute(StunAttributeType.username, 'user');
      msg.setAttribute(StunAttributeType.priority, 12345);

      final bytes = msg.toBytes();

      expect(bytes.length, greaterThan(20)); // Header + attributes

      // Parse it back
      final parsed = parseStunMessage(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.method, equals(StunMethod.binding));
      expect(parsed.messageClass, equals(StunClass.request));
      expect(parsed.getAttribute(StunAttributeType.username), equals('user'));
      expect(parsed.getAttribute(StunAttributeType.priority), equals(12345));
    });

    test('parses binding request from RFC test vector', () {
      // Simplified RFC 5769 test vector (without authentication)
      final bytes = Uint8List.fromList([
        0x00, 0x01, // Message Type: Binding Request
        0x00, 0x00, // Message Length: 0 (no attributes)
        0x21, 0x12, 0xA4, 0x42, // Magic Cookie
        0xB7, 0xE7, 0xA7, 0x01, // Transaction ID
        0xBC, 0x34, 0xD6, 0x86,
        0xFA, 0x87, 0xDF, 0xAE,
      ]);

      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.method, equals(StunMethod.binding));
      expect(parsed.messageClass, equals(StunClass.request));
      expect(parsed.transactionId, hasLength(12));
    });

    test('round-trips message serialization', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
      );

      msg.setAttribute(StunAttributeType.username, 'testuser');
      msg.setAttribute(StunAttributeType.priority, 98765);
      msg.setAttribute(StunAttributeType.useCandidate, null);

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.method, equals(msg.method));
      expect(parsed.messageClass, equals(msg.messageClass));
      expect(parsed.transactionId, equals(msg.transactionId));
      expect(
          parsed.getAttribute(StunAttributeType.username), equals('testuser'));
      expect(parsed.getAttribute(StunAttributeType.priority), equals(98765));
      expect(parsed.hasAttribute(StunAttributeType.useCandidate), isTrue);
    });

    test('rejects message with invalid length', () {
      final bytes = Uint8List.fromList([
        0x00, 0x01, // Message Type
        0x00, 0x10, // Length: 16 (but data is shorter)
        0x21, 0x12, 0xA4, 0x42, // Magic Cookie
        0x01, 0x02, 0x03, 0x04,
        0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C,
        // Missing attribute data
      ]);

      final parsed = parseStunMessage(bytes);
      expect(parsed, isNull);
    });

    test('rejects message with invalid magic cookie', () {
      final bytes = Uint8List.fromList([
        0x00, 0x01, // Message Type
        0x00, 0x00, // Length
        0xFF, 0xFF, 0xFF, 0xFF, // Wrong magic cookie
        0x01, 0x02, 0x03, 0x04,
        0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C,
      ]);

      final parsed = parseStunMessage(bytes);
      expect(parsed, isNull);
    });

    test('handles XOR-MAPPED-ADDRESS attribute', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
      );

      msg.setAttribute(
          StunAttributeType.xorMappedAddress, ('192.168.1.100', 8080));

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      final addr =
          parsed!.getAttribute(StunAttributeType.xorMappedAddress) as Address;
      expect(addr.$1, equals('192.168.1.100'));
      expect(addr.$2, equals(8080));
    });

    test('computes CRC32 correctly', () {
      // Test with known CRC32 value
      final data = Uint8List.fromList('123456789'.codeUnits);
      final crc = computeCrc32(data);

      // Known CRC32 for "123456789" is 0xCBF43926
      expect(crc, equals(0xCBF43926));
    });

    test('adds and verifies FINGERPRINT', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      msg.setAttribute(StunAttributeType.username, 'test');
      msg.addFingerprint();

      expect(msg.hasAttribute(StunAttributeType.fingerprint), isTrue);

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.hasAttribute(StunAttributeType.fingerprint), isTrue);
    });

    test('adds and verifies MESSAGE-INTEGRITY', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      msg.setAttribute(StunAttributeType.username, 'test');

      final key = Uint8List.fromList('secret'.codeUnits);
      msg.addMessageIntegrity(key);

      expect(msg.hasAttribute(StunAttributeType.messageIntegrity), isTrue);

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes, integrityKey: key);

      expect(parsed, isNotNull);
      expect(parsed!.hasAttribute(StunAttributeType.messageIntegrity), isTrue);
    });

    test('rejects message with invalid MESSAGE-INTEGRITY', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      final key = Uint8List.fromList('secret'.codeUnits);
      msg.addMessageIntegrity(key);

      final bytes = msg.toBytes();

      // Try to parse with wrong key
      final wrongKey = Uint8List.fromList('wrong'.codeUnits);
      final parsed = parseStunMessage(bytes, integrityKey: wrongKey);

      expect(parsed, isNull); // Should fail integrity check
    });

    test('handles error response with ERROR-CODE', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.errorResponse,
      );

      msg.setAttribute(StunAttributeType.errorCode, (401, 'Unauthorized'));

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      final errorCode =
          parsed!.getAttribute(StunAttributeType.errorCode) as (int, String);
      expect(errorCode.$1, equals(401));
      expect(errorCode.$2, equals('Unauthorized'));
    });

    test('handles ICE-CONTROLLING attribute', () {
      final msg = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      final tieBreaker = BigInt.parse('123456789ABCDEF0', radix: 16);
      msg.setAttribute(StunAttributeType.iceControlling, tieBreaker);

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      expect(
        parsed!.getAttribute(StunAttributeType.iceControlling),
        equals(tieBreaker),
      );
    });

    test('handles multiple address attributes', () {
      final msg = StunMessage(
        method: StunMethod.allocate,
        messageClass: StunClass.successResponse,
      );

      msg.setAttribute(StunAttributeType.xorMappedAddress, ('10.0.0.1', 3478));
      msg.setAttribute(StunAttributeType.xorRelayedAddress, ('20.0.0.2', 5000));

      final bytes = msg.toBytes();
      final parsed = parseStunMessage(bytes);

      expect(parsed, isNotNull);
      final mapped =
          parsed!.getAttribute(StunAttributeType.xorMappedAddress) as Address;
      final relayed =
          parsed.getAttribute(StunAttributeType.xorRelayedAddress) as Address;

      expect(mapped.$1, equals('10.0.0.1'));
      expect(mapped.$2, equals(3478));
      expect(relayed.$1, equals('20.0.0.2'));
      expect(relayed.$2, equals(5000));
    });
  });
}
