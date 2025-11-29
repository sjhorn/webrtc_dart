import 'package:test/test.dart';
import 'package:webrtc_dart/src/turn/turn_client.dart';

void main() {
  group('parseTurnUrl', () {
    test('parses basic TURN URL with default port', () {
      final result = parseTurnUrl('turn:example.com');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'example.com');
      expect(port, 3478); // Default TURN port
      expect(transport, TurnTransport.udp);
      expect(secure, isFalse);
    });

    test('parses TURN URL with explicit port', () {
      final result = parseTurnUrl('turn:example.com:3479');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'example.com');
      expect(port, 3479);
      expect(transport, TurnTransport.udp);
      expect(secure, isFalse);
    });

    test('parses TURNS URL (secure)', () {
      final result = parseTurnUrl('turns:example.com');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'example.com');
      expect(port, 5349); // Default TURNS port
      expect(transport, TurnTransport.udp);
      expect(secure, isTrue);
    });

    test('parses TURN URL with TCP transport', () {
      final result = parseTurnUrl('turn:example.com?transport=tcp');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'example.com');
      expect(port, 3478);
      expect(transport, TurnTransport.tcp);
      expect(secure, isFalse);
    });

    test('parses TURN URL with port and transport', () {
      final result = parseTurnUrl('turn:example.com:3479?transport=tcp');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'example.com');
      expect(port, 3479);
      expect(transport, TurnTransport.tcp);
      expect(secure, isFalse);
    });

    test('parses TURNS URL with TCP transport', () {
      final result = parseTurnUrl('turns:example.com?transport=tcp');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'example.com');
      expect(port, 5349);
      expect(transport, TurnTransport.tcp);
      expect(secure, isTrue);
    });

    test('handles IP address', () {
      final result = parseTurnUrl('turn:192.168.1.1:3478');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, '192.168.1.1');
      expect(port, 3478);
    });

    test('handles IPv6 address', () {
      final result = parseTurnUrl('turn:[2001:db8::1]:3478');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, '2001:db8::1');
      expect(port, 3478);
    });

    test('returns null for invalid scheme', () {
      expect(parseTurnUrl('http://example.com'), isNull);
      expect(parseTurnUrl('stun:example.com'), isNull);
      expect(parseTurnUrl('ftp://example.com'), isNull);
    });

    test('returns null for malformed URL', () {
      expect(parseTurnUrl('not a url'), isNull);
      expect(parseTurnUrl(''), isNull);
      expect(parseTurnUrl('turn:'), isNull);
    });

    test('handles public TURN server URLs', () {
      final result = parseTurnUrl('turn:numb.viagenie.ca');
      expect(result, isNotNull);

      final (host, port, transport, secure) = result!;
      expect(host, 'numb.viagenie.ca');
      expect(port, 3478);
    });
  });
}
