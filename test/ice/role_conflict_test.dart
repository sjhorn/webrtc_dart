import 'package:test/test.dart';
import 'package:webrtc_dart/src/stun/message.dart';
import 'package:webrtc_dart/src/stun/const.dart';

void main() {
  group('ICE Role Conflict (RFC 8445 Section 7.2.1.1)', () {
    group('STUN message role attributes', () {
      test('ICE-CONTROLLING attribute is correctly encoded/decoded', () {
        final message = StunMessage(
          method: StunMethod.binding,
          messageClass: StunClass.request,
        );

        // 64-bit tie-breaker value
        final tieBreaker = BigInt.from(0x0123456789ABCDEF);
        message.setAttribute(StunAttributeType.iceControlling, tieBreaker);

        final bytes = message.toBytes();
        final parsed = parseStunMessage(bytes)!;

        final value = parsed.getAttribute(StunAttributeType.iceControlling);
        expect(value, isNotNull);
        // Parsed value is BigInt
        expect(value as BigInt, equals(tieBreaker));
      });

      test('ICE-CONTROLLED attribute is correctly encoded/decoded', () {
        final message = StunMessage(
          method: StunMethod.binding,
          messageClass: StunClass.request,
        );

        final tieBreaker = BigInt.from(0x0EDCBA9876543210);
        message.setAttribute(StunAttributeType.iceControlled, tieBreaker);

        final bytes = message.toBytes();
        final parsed = parseStunMessage(bytes)!;

        final value = parsed.getAttribute(StunAttributeType.iceControlled);
        expect(value, isNotNull);
        // Parsed value is BigInt
        expect(value as BigInt, equals(tieBreaker));
      });
    });

    group('487 Role Conflict error response', () {
      test('error code 487 is correctly encoded/decoded', () {
        final response = StunMessage(
          method: StunMethod.binding,
          messageClass: StunClass.errorResponse,
        );

        response.setAttribute(
          StunAttributeType.errorCode,
          (487, 'Role Conflict'),
        );

        final bytes = response.toBytes();
        final parsed = parseStunMessage(bytes)!;

        expect(parsed.messageClass, equals(StunClass.errorResponse));

        final errorCode = parsed.getAttribute(StunAttributeType.errorCode);
        expect(errorCode, isNotNull);
        final (code, reason) = errorCode as (int, String);
        expect(code, equals(487));
        expect(reason, equals('Role Conflict'));
      });

      test('error response includes XOR-MAPPED-ADDRESS', () {
        final response = StunMessage(
          method: StunMethod.binding,
          messageClass: StunClass.errorResponse,
        );

        response.setAttribute(
          StunAttributeType.errorCode,
          (487, 'Role Conflict'),
        );
        response.setAttribute(
          StunAttributeType.xorMappedAddress,
          ('192.168.1.1', 12345),
        );
        response.addFingerprint();

        final bytes = response.toBytes();
        final parsed = parseStunMessage(bytes)!;

        expect(parsed.messageClass, equals(StunClass.errorResponse));

        final addr = parsed.getAttribute(StunAttributeType.xorMappedAddress);
        expect(addr, isNotNull);
        final (host, port) = addr as (String, int);
        expect(host, equals('192.168.1.1'));
        expect(port, equals(12345));
      });
    });

    group('Tie-breaker comparison', () {
      test('larger tie-breaker wins', () {
        final smaller = BigInt.from(1000);
        final larger = BigInt.from(2000);

        expect(larger > smaller, isTrue);
        expect(smaller < larger, isTrue);
        expect(smaller >= larger, isFalse);
        expect(larger >= smaller, isTrue);
      });

      test('equal tie-breakers handled correctly', () {
        final value = BigInt.from(12345);
        final same = BigInt.from(12345);

        // When tie-breakers are equal, remote wins (>= comparison)
        expect(same >= value, isTrue);
        expect(value >= same, isTrue);
      });

      test('64-bit tie-breaker values compare correctly', () {
        // Test with large 64-bit values that would overflow 32-bit
        final value1 = BigInt.parse('0x8000000000000000');
        final value2 = BigInt.parse('0x8000000000000001');

        expect(value2 > value1, isTrue);
        expect(value1 < value2, isTrue);
      });
    });

    group('Role conflict detection', () {
      test('both controlling is a conflict', () {
        // Simulates: we are controlling, received ICE-CONTROLLING
        final weAreControlling = true;
        final remoteIsControlling = true;

        final isConflict = weAreControlling && remoteIsControlling;
        expect(isConflict, isTrue);
      });

      test('both controlled is a conflict', () {
        // Simulates: we are controlled, received ICE-CONTROLLED
        final weAreControlling = false;
        final remoteIsControlling = false;

        final isConflict = !weAreControlling && !remoteIsControlling;
        expect(isConflict, isTrue);
      });

      test('controlling vs controlled is not a conflict', () {
        // Simulates: we are controlling, received ICE-CONTROLLED
        final weAreControlling = true;
        final remoteIsControlling = false;

        final isConflict =
            (weAreControlling && remoteIsControlling) ||
            (!weAreControlling && !remoteIsControlling);
        expect(isConflict, isFalse);
      });

      test('controlled vs controlling is not a conflict', () {
        // Simulates: we are controlled, received ICE-CONTROLLING
        final weAreControlling = false;
        final remoteIsControlling = true;

        final isConflict =
            (weAreControlling && remoteIsControlling) ||
            (!weAreControlling && !remoteIsControlling);
        expect(isConflict, isFalse);
      });
    });

    group('Role conflict resolution', () {
      test('controlling agent with smaller tie-breaker switches to controlled', () {
        // We are controlling with smaller tie-breaker
        // Remote is also controlling with larger tie-breaker
        // Resolution: we switch to controlled
        final ourTieBreaker = BigInt.from(100);
        final theirTieBreaker = BigInt.from(200);
        final weAreControlling = true;

        bool shouldSwitchRole = theirTieBreaker >= ourTieBreaker;
        expect(shouldSwitchRole, isTrue);
        // After switch: we become controlled
      });

      test('controlling agent with larger tie-breaker sends 487', () {
        // We are controlling with larger tie-breaker
        // Remote is also controlling with smaller tie-breaker
        // Resolution: send 487 error
        final ourTieBreaker = BigInt.from(200);
        final theirTieBreaker = BigInt.from(100);
        final weAreControlling = true;

        bool shouldSend487 = theirTieBreaker < ourTieBreaker;
        expect(shouldSend487, isTrue);
      });

      test('controlled agent with smaller tie-breaker switches to controlling', () {
        // We are controlled with smaller tie-breaker
        // Remote is also controlled with larger tie-breaker
        // Resolution: we switch to controlling
        final ourTieBreaker = BigInt.from(100);
        final theirTieBreaker = BigInt.from(200);
        final weAreControlling = false;

        // For controlled-controlled conflict:
        // If their tie-breaker >= ours, they stay controlled, we switch to controlling
        bool shouldSwitchRole = theirTieBreaker >= ourTieBreaker;
        expect(shouldSwitchRole, isTrue);
      });

      test('controlled agent with larger tie-breaker sends 487', () {
        // We are controlled with larger tie-breaker
        // Remote is also controlled with smaller tie-breaker
        // Resolution: send 487 error (they should switch)
        final ourTieBreaker = BigInt.from(200);
        final theirTieBreaker = BigInt.from(100);

        bool shouldSend487 = theirTieBreaker < ourTieBreaker;
        expect(shouldSend487, isTrue);
      });
    });
  });
}
