import 'package:test/test.dart';
import 'package:webrtc_dart/src/turn/turn_client.dart';

void main() {
  group('TurnTransport', () {
    test('udp has correct value', () {
      expect(TurnTransport.udp.value, equals(17));
    });

    test('tcp has correct value', () {
      expect(TurnTransport.tcp.value, equals(6));
    });

    test('requestedTransport for udp shifts value correctly', () {
      // UDP protocol (17) should be in upper 8 bits
      expect(TurnTransport.udp.requestedTransport, equals(17 << 24));
    });

    test('requestedTransport for tcp shifts value correctly', () {
      // TCP protocol (6) should be in upper 8 bits
      expect(TurnTransport.tcp.requestedTransport, equals(6 << 24));
    });
  });

  group('TurnState', () {
    test('enum has all expected values', () {
      expect(
          TurnState.values,
          containsAll([
            TurnState.idle,
            TurnState.connecting,
            TurnState.connected,
            TurnState.failed,
            TurnState.closed,
          ]));
    });
  });

  group('TurnAllocation', () {
    test('construction with required values', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        lifetime: 600,
      );

      expect(allocation.relayedAddress, equals(('192.0.2.15', 49152)));
      expect(allocation.lifetime, equals(600));
      expect(allocation.mappedAddress, isNull);
      expect(allocation.createdAt, isNotNull);
    });

    test('construction with all values', () {
      final createdAt = DateTime(2024, 1, 1, 12, 0, 0);
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        mappedAddress: ('203.0.113.5', 54321),
        lifetime: 600,
        createdAt: createdAt,
      );

      expect(allocation.relayedAddress, equals(('192.0.2.15', 49152)));
      expect(allocation.mappedAddress, equals(('203.0.113.5', 54321)));
      expect(allocation.lifetime, equals(600));
      expect(allocation.createdAt, equals(createdAt));
    });

    test('isExpired returns false when within lifetime', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        lifetime: 600,
        createdAt: DateTime.now(),
      );

      expect(allocation.isExpired, isFalse);
    });

    test('isExpired returns true when past lifetime', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        lifetime: 60,
        createdAt: DateTime.now().subtract(Duration(seconds: 120)),
      );

      expect(allocation.isExpired, isTrue);
    });

    test('remainingLifetime returns correct value', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        lifetime: 600,
        createdAt: DateTime.now(),
      );

      // Should be close to 600 (minus a few milliseconds for test execution)
      expect(allocation.remainingLifetime, greaterThan(595));
      expect(allocation.remainingLifetime, lessThanOrEqualTo(600));
    });

    test('remainingLifetime returns 0 when expired', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        lifetime: 60,
        createdAt: DateTime.now().subtract(Duration(seconds: 120)),
      );

      expect(allocation.remainingLifetime, equals(0));
    });

    test('remainingLifetime is clamped to 0', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.0.2.15', 49152),
        lifetime: 30,
        createdAt: DateTime.now().subtract(Duration(seconds: 1000)),
      );

      expect(allocation.remainingLifetime, equals(0));
    });
  });

  group('TurnClient construction', () {
    test('construction with required parameters', () {
      final client = TurnClient(
        serverAddress: ('turn.example.com', 3478),
        username: 'user1',
        password: 'pass123',
      );

      expect(client.serverAddress, equals(('turn.example.com', 3478)));
      expect(client.username, equals('user1'));
      expect(client.password, equals('pass123'));
      expect(client.transport, equals(TurnTransport.udp)); // default
      expect(client.lifetime, equals(600)); // default 10 minutes
      expect(client.state, equals(TurnState.idle));
      expect(client.allocation, isNull);
    });

    test('construction with custom transport and lifetime', () {
      final client = TurnClient(
        serverAddress: ('turn.example.com', 443),
        username: 'user1',
        password: 'pass123',
        transport: TurnTransport.tcp,
        lifetime: 3600,
      );

      expect(client.transport, equals(TurnTransport.tcp));
      expect(client.lifetime, equals(3600));
    });
  });

  group('parseTurnUrl', () {
    test('parses simple turn URL', () {
      final result = parseTurnUrl('turn:turn.example.com');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(3478)); // default TURN port
      expect(transport, equals(TurnTransport.udp));
      expect(secure, isFalse);
    });

    test('parses turn URL with port', () {
      final result = parseTurnUrl('turn:turn.example.com:3478');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(3478));
      expect(transport, equals(TurnTransport.udp));
      expect(secure, isFalse);
    });

    test('parses turn URL with custom port', () {
      final result = parseTurnUrl('turn:turn.example.com:5000');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(5000));
    });

    test('parses turns URL (secure)', () {
      final result = parseTurnUrl('turns:turn.example.com');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(5349)); // default TURNS port
      expect(transport, equals(TurnTransport.udp));
      expect(secure, isTrue);
    });

    test('parses turns URL with port', () {
      final result = parseTurnUrl('turns:turn.example.com:443');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(443));
      expect(secure, isTrue);
    });

    test('parses turn URL with tcp transport', () {
      final result = parseTurnUrl('turn:turn.example.com:3478?transport=tcp');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(3478));
      expect(transport, equals(TurnTransport.tcp));
      expect(secure, isFalse);
    });

    test('parses turn URL with transport without port', () {
      final result = parseTurnUrl('turn:turn.example.com?transport=tcp');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('turn.example.com'));
      expect(port, equals(3478));
      expect(transport, equals(TurnTransport.tcp));
    });

    test('parses IPv4 address', () {
      final result = parseTurnUrl('turn:192.168.1.100:3478');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('192.168.1.100'));
      expect(port, equals(3478));
    });

    test('parses IPv6 address in brackets', () {
      final result = parseTurnUrl('turn:[2001:db8::1]:3478');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('2001:db8::1'));
      expect(port, equals(3478));
    });

    test('parses IPv6 address in brackets without port', () {
      final result = parseTurnUrl('turn:[2001:db8::1]');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(host, equals('2001:db8::1'));
      expect(port, equals(3478)); // default
    });

    test('returns null for empty string', () {
      final result = parseTurnUrl('');
      expect(result, isNull);
    });

    test('returns null for invalid scheme', () {
      final result = parseTurnUrl('stun:stun.example.com');
      expect(result, isNull);
    });

    test('returns null for missing colon', () {
      final result = parseTurnUrl('turnexamplecom');
      expect(result, isNull);
    });

    test('returns null for empty host in IPv6', () {
      final result = parseTurnUrl('turn:[]:3478');
      expect(result, isNull);
    });

    test('returns null for unclosed IPv6 bracket', () {
      final result = parseTurnUrl('turn:[2001:db8::1');
      expect(result, isNull);
    });

    test('returns null for invalid format after IPv6 bracket', () {
      final result = parseTurnUrl('turn:[2001:db8::1]abc');
      expect(result, isNull);
    });

    test('handles multiple query parameters', () {
      final result =
          parseTurnUrl('turn:turn.example.com?transport=tcp&foo=bar');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(transport, equals(TurnTransport.tcp));
    });

    test('ignores unknown transport values', () {
      final result = parseTurnUrl('turn:turn.example.com?transport=udp');

      expect(result, isNotNull);
      final (host, port, transport, secure) = result!;
      expect(transport, equals(TurnTransport.udp)); // stays as default udp
    });
  });
}
