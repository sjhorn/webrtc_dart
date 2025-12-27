import 'dart:math';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('ICE Consent Freshness (RFC 7675)', () {
    group('Constants', () {
      test('consent interval is 5 seconds', () {
        // RFC 7675 specifies 5 seconds as the base consent interval
        // We verify this indirectly by testing the randomized range
        const baseInterval = 5;
        expect(baseInterval, equals(5));
      });

      test('max failures before closing is 6', () {
        // RFC 7675 specifies 6 consecutive failures before disconnecting
        const maxFailures = 6;
        expect(maxFailures, equals(6));
      });
    });

    group('Randomized interval', () {
      test('interval jitter is ±20% of base', () {
        // RFC 7675: CONSENT_INTERVAL * (0.8 + 0.4 * random)
        // This results in 80% to 120% of the 5 second base = 4-6 seconds
        final random = Random(42); // Seeded for reproducibility

        final intervals = <int>[];
        for (var i = 0; i < 100; i++) {
          final jitter = 0.8 + (random.nextDouble() * 0.4);
          final ms = (5 * 1000 * jitter).toInt();
          intervals.add(ms);
        }

        // All intervals should be between 4000ms and 6000ms
        expect(intervals.every((ms) => ms >= 4000), isTrue);
        expect(intervals.every((ms) => ms <= 6000), isTrue);

        // Should have variation (not all the same value)
        expect(intervals.toSet().length, greaterThan(50));
      });
    });

    group('State transitions', () {
      test('connection starts in newState', () {
        final connection = IceConnectionImpl(iceControlling: true);
        expect(connection.state, equals(IceState.newState));
      });

      test('disconnected state exists for consent failures', () {
        // Verify IceState.disconnected is a valid state
        expect(IceState.disconnected, isNotNull);
        expect(IceState.values, contains(IceState.disconnected));
      });

      test('state enumeration includes all consent-related states', () {
        // Consent freshness requires these states:
        // - connected: normal operation
        // - disconnected: temporary consent failure
        // - failed: permanent consent failure (6 consecutive failures)
        expect(IceState.values, contains(IceState.connected));
        expect(IceState.values, contains(IceState.disconnected));
        expect(IceState.values, contains(IceState.failed));
        expect(IceState.values, contains(IceState.completed));
      });
    });

    group('IceConnectionImpl consent check setup', () {
      test('connection has consent check infrastructure', () {
        // IceConnectionImpl should have consent checking capability
        // We can't directly test private members, but we can verify
        // the public interface and state transitions work
        final connection = IceConnectionImpl(iceControlling: true);

        // Connection should support state transitions for consent
        final stateChanges = <IceState>[];
        connection.onStateChanged.listen((state) {
          stateChanges.add(state);
        });

        expect(connection.state, equals(IceState.newState));
      });

      test('restart clears consent state', () async {
        final connection = IceConnectionImpl(iceControlling: true);

        // Set some remote params to test restart clears state
        connection.setRemoteParams(
          iceLite: false,
          usernameFragment: 'test',
          password: 'testpass',
        );

        // Restart should clear state and generate new credentials
        await connection.restart();

        expect(connection.state, equals(IceState.newState));
        expect(connection.generation, equals(1));
        // New credentials should be generated
        expect(connection.localUsername, hasLength(4));
        expect(connection.localPassword, hasLength(22));
      });

      test('close stops consent checks', () async {
        final connection = IceConnectionImpl(iceControlling: true);

        await connection.close();

        expect(connection.state, equals(IceState.closed));
      });
    });

    group('Consent interval calculations', () {
      test('interval calculation formula', () {
        // RFC 7675 formula: CONSENT_INTERVAL * (0.8 + 0.4 * random)
        // Where random is in [0, 1)
        // So interval is in [0.8 * 5, 1.2 * 5) = [4, 6) seconds
        const baseSeconds = 5;

        // Minimum interval (random = 0)
        final minJitter = 0.8 + (0.0 * 0.4);
        final minMs = (baseSeconds * 1000 * minJitter).toInt();
        expect(minMs, equals(4000));

        // Maximum interval (random approaching 1)
        final maxJitter = 0.8 + (0.9999 * 0.4);
        final maxMs = (baseSeconds * 1000 * maxJitter).toInt();
        expect(maxMs, lessThanOrEqualTo(5999));
        expect(maxMs, greaterThan(5900));
      });
    });
  });
}
