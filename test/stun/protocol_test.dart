import 'package:test/test.dart';
import 'package:webrtc_dart/src/stun/protocol.dart';

void main() {
  group('StunBindingResult', () {
    test('construction with success', () {
      final result = StunBindingResult(
        success: true,
        mappedAddress: '203.0.113.5',
        mappedPort: 54321,
        localAddress: '192.168.1.100',
        localPort: 12345,
      );

      expect(result.success, isTrue);
      expect(result.mappedAddress, equals('203.0.113.5'));
      expect(result.mappedPort, equals(54321));
      expect(result.localAddress, equals('192.168.1.100'));
      expect(result.localPort, equals(12345));
      expect(result.errorCode, isNull);
      expect(result.errorReason, isNull);
    });

    test('construction with error', () {
      final result = StunBindingResult(
        success: false,
        errorCode: 401,
        errorReason: 'Unauthorized',
      );

      expect(result.success, isFalse);
      expect(result.errorCode, equals(401));
      expect(result.errorReason, equals('Unauthorized'));
      expect(result.mappedAddress, isNull);
      expect(result.mappedPort, isNull);
    });

    test('toString for success', () {
      final result = StunBindingResult(
        success: true,
        mappedAddress: '203.0.113.5',
        mappedPort: 54321,
        localAddress: '192.168.1.100',
        localPort: 12345,
      );

      final str = result.toString();
      expect(str, contains('success: true'));
      expect(str, contains('203.0.113.5'));
      expect(str, contains('54321'));
      expect(str, contains('192.168.1.100'));
      expect(str, contains('12345'));
    });

    test('toString for error', () {
      final result = StunBindingResult(
        success: false,
        errorCode: 438,
        errorReason: 'Stale Nonce',
      );

      final str = result.toString();
      expect(str, contains('success: false'));
      expect(str, contains('438'));
      expect(str, contains('Stale Nonce'));
    });

    test('construction with minimal params', () {
      final result = StunBindingResult(success: false);

      expect(result.success, isFalse);
      expect(result.mappedAddress, isNull);
      expect(result.mappedPort, isNull);
      expect(result.localAddress, isNull);
      expect(result.localPort, isNull);
      expect(result.errorCode, isNull);
      expect(result.errorReason, isNull);
    });
  });

  group('StunClient', () {
    test('construction with default port', () {
      final client = StunClient(
        serverHost: 'stun.example.com',
      );

      expect(client.serverHost, equals('stun.example.com'));
      expect(client.serverPort, equals(3478)); // Default STUN port
    });

    test('construction with custom port', () {
      final client = StunClient(
        serverHost: 'stun.example.com',
        serverPort: 5349,
      );

      expect(client.serverHost, equals('stun.example.com'));
      expect(client.serverPort, equals(5349));
    });
  });
}
