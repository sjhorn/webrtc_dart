import 'package:test/test.dart';
import 'package:webrtc_dart/src/turn/turn_client.dart';

void main() {
  group('TurnAllocation', () {
    test('tracks creation time', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.168.1.100', 50000),
        lifetime: 600,
      );

      expect(allocation.createdAt, isNotNull);
      expect(
          allocation.createdAt
              .isBefore(DateTime.now().add(Duration(seconds: 1))),
          isTrue);
    });

    test('calculates expiry correctly', () {
      // Create allocation that expires in 1 second
      final allocation = TurnAllocation(
        relayedAddress: ('192.168.1.100', 50000),
        lifetime: 1,
        createdAt: DateTime.now().subtract(Duration(milliseconds: 500)),
      );

      expect(allocation.isExpired, isFalse);
      expect(allocation.remainingLifetime, greaterThan(0));
      expect(allocation.remainingLifetime, lessThanOrEqualTo(1));
    });

    test('detects expired allocation', () {
      // Create allocation that expired 1 second ago
      final allocation = TurnAllocation(
        relayedAddress: ('192.168.1.100', 50000),
        lifetime: 1,
        createdAt: DateTime.now().subtract(Duration(seconds: 2)),
      );

      expect(allocation.isExpired, isTrue);
      expect(allocation.remainingLifetime, 0);
    });

    test('remaining lifetime never goes negative', () {
      final allocation = TurnAllocation(
        relayedAddress: ('192.168.1.100', 50000),
        lifetime: 1,
        createdAt: DateTime.now().subtract(Duration(seconds: 10)),
      );

      expect(allocation.remainingLifetime, 0);
      expect(allocation.remainingLifetime, greaterThanOrEqualTo(0));
    });

    test('stores relayed and mapped addresses', () {
      final relayedAddr = ('203.0.113.100', 50000);
      final mappedAddr = ('192.168.1.50', 54321);

      final allocation = TurnAllocation(
        relayedAddress: relayedAddr,
        mappedAddress: mappedAddr,
        lifetime: 600,
      );

      expect(allocation.relayedAddress, relayedAddr);
      expect(allocation.mappedAddress, mappedAddr);
    });

    test('mapped address is optional', () {
      final allocation = TurnAllocation(
        relayedAddress: ('203.0.113.100', 50000),
        lifetime: 600,
      );

      expect(allocation.mappedAddress, isNull);
    });

    test('handles typical TURN lifetime (600 seconds)', () {
      final allocation = TurnAllocation(
        relayedAddress: ('203.0.113.100', 50000),
        lifetime: 600,
      );

      expect(allocation.lifetime, 600);
      expect(allocation.remainingLifetime, lessThanOrEqualTo(600));
      expect(allocation.remainingLifetime,
          greaterThan(595)); // Allow some processing time
      expect(allocation.isExpired, isFalse);
    });
  });

  group('TurnTransport', () {
    test('UDP protocol value', () {
      expect(TurnTransport.udp.value, 17);
    });

    test('TCP protocol value', () {
      expect(TurnTransport.tcp.value, 6);
    });

    test('requestedTransport encodes correctly', () {
      // REQUESTED-TRANSPORT has protocol in upper 8 bits
      expect(TurnTransport.udp.requestedTransport, 17 << 24);
      expect(TurnTransport.tcp.requestedTransport, 6 << 24);
    });
  });

  group('TurnState', () {
    test('has all required states', () {
      expect(TurnState.values, contains(TurnState.idle));
      expect(TurnState.values, contains(TurnState.connecting));
      expect(TurnState.values, contains(TurnState.connected));
      expect(TurnState.values, contains(TurnState.failed));
      expect(TurnState.values, contains(TurnState.closed));
    });
  });

  group('TurnClient', () {
    test('initializes with correct defaults', () {
      final client = TurnClient(
        serverAddress: ('turn.example.com', 3478),
        username: 'user',
        password: 'pass',
      );

      expect(client.state, TurnState.idle);
      expect(client.allocation, isNull);
      expect(client.transport, TurnTransport.udp);
      expect(client.lifetime, 600);
    });

    test('can be configured with TCP transport', () {
      final client = TurnClient(
        serverAddress: ('turn.example.com', 3478),
        username: 'user',
        password: 'pass',
        transport: TurnTransport.tcp,
      );

      expect(client.transport, TurnTransport.tcp);
    });

    test('can be configured with custom lifetime', () {
      final client = TurnClient(
        serverAddress: ('turn.example.com', 3478),
        username: 'user',
        password: 'pass',
        lifetime: 300,
      );

      expect(client.lifetime, 300);
    });

    test('provides receive stream', () {
      final client = TurnClient(
        serverAddress: ('turn.example.com', 3478),
        username: 'user',
        password: 'pass',
      );

      expect(client.onReceive, isA<Stream>());
    });
  });
}
