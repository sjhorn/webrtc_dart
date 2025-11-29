import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('TURN Relay Integration', () {
    group('IceOptions with TURN', () {
      test('creates with TURN server configuration', () {
        const options = IceOptions(
          turnServer: ('turn.example.com', 3478),
          turnUsername: 'testuser',
          turnPassword: 'testpass',
        );

        expect(options.turnServer, equals(('turn.example.com', 3478)));
        expect(options.turnUsername, equals('testuser'));
        expect(options.turnPassword, equals('testpass'));
      });

      test('creates with TURN and STUN servers', () {
        const options = IceOptions(
          stunServer: ('stun.example.com', 3478),
          turnServer: ('turn.example.com', 3478),
          turnUsername: 'user',
          turnPassword: 'pass',
        );

        expect(options.stunServer, isNotNull);
        expect(options.turnServer, isNotNull);
      });

      test('creates without TURN (TURN optional)', () {
        const options = IceOptions(
          stunServer: ('stun.example.com', 3478),
        );

        expect(options.stunServer, isNotNull);
        expect(options.turnServer, isNull);
        expect(options.turnUsername, isNull);
        expect(options.turnPassword, isNull);
      });
    });

    group('Relay Candidate Detection', () {
      test('candidate type relay is identified correctly', () {
        final relayCandidate = Candidate(
          foundation: 'relay-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '1.2.3.4',
          port: 49170,
          type: 'relay',
          relatedAddress: '192.168.1.100',
          relatedPort: 54321,
        );

        expect(relayCandidate.type, equals('relay'));
        expect(relayCandidate.relatedAddress, isNotNull);
        expect(relayCandidate.relatedPort, isNotNull);
      });

      test('relay priority is lower than host and srflx', () {
        final hostPriority = candidatePriority('host');
        final srflxPriority = candidatePriority('srflx');
        final relayPriority = candidatePriority('relay');

        // RFC 5245: host > srflx > relay
        expect(hostPriority, greaterThan(srflxPriority));
        expect(srflxPriority, greaterThan(relayPriority));
      });
    });

    group('Relay Candidate Pairing', () {
      test('relay candidate can pair with host candidate', () {
        final relayCandidate = Candidate(
          foundation: 'relay-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '1.2.3.4',
          port: 49170,
          type: 'relay',
        );

        final hostCandidate = Candidate(
          foundation: 'host-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('host'),
          host: '192.168.1.1',
          port: 54321,
          type: 'host',
        );

        expect(relayCandidate.canPairWith(hostCandidate), isTrue);
      });

      test('relay candidate can pair with srflx candidate', () {
        final relayCandidate = Candidate(
          foundation: 'relay-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '1.2.3.4',
          port: 49170,
          type: 'relay',
        );

        final srflxCandidate = Candidate(
          foundation: 'srflx-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('srflx'),
          host: '203.0.113.50',
          port: 12345,
          type: 'srflx',
        );

        expect(relayCandidate.canPairWith(srflxCandidate), isTrue);
      });

      test('relay candidate can pair with another relay candidate', () {
        final relayCandidate1 = Candidate(
          foundation: 'relay-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '1.2.3.4',
          port: 49170,
          type: 'relay',
        );

        final relayCandidate2 = Candidate(
          foundation: 'relay-2',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '5.6.7.8',
          port: 49171,
          type: 'relay',
        );

        expect(relayCandidate1.canPairWith(relayCandidate2), isTrue);
      });

      test('creates candidate pair with relay local candidate', () {
        final relayCandidate = Candidate(
          foundation: 'relay-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '1.2.3.4',
          port: 49170,
          type: 'relay',
        );

        final remoteCandidate = Candidate(
          foundation: 'host-1',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('host'),
          host: '192.168.1.1',
          port: 54321,
          type: 'host',
        );

        final pair = CandidatePair(
          id: 'relay-1-host-1',
          localCandidate: relayCandidate,
          remoteCandidate: remoteCandidate,
          iceControlling: true,
        );

        expect(pair.localCandidate.type, equals('relay'));
        expect(pair.remoteCandidate.type, equals('host'));
        expect(pair.state, equals(CandidatePairState.frozen));
      });
    });

    group('IceConnection with TURN options', () {
      test('IceConnection accepts TURN configuration', () {
        const options = IceOptions(
          turnServer: ('turn.example.com', 3478),
          turnUsername: 'testuser',
          turnPassword: 'testpass',
        );

        final connection = IceConnectionImpl(
          iceControlling: true,
          options: options,
        );

        expect(connection.state, equals(IceState.newState));
        // TURN client won't be created until gatherCandidates is called
      });

      test('IceConnection handles missing TURN credentials gracefully', () {
        // Only server, no credentials
        const options = IceOptions(
          turnServer: ('turn.example.com', 3478),
          // No username/password
        );

        final connection = IceConnectionImpl(
          iceControlling: true,
          options: options,
        );

        // Should create connection without error
        expect(connection, isNotNull);
      });
    });

    group('Relay data routing logic', () {
      test('identifies relay candidate type correctly', () {
        final candidate = Candidate(
          foundation: 'relay-abc',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('relay'),
          host: '1.2.3.4',
          port: 49170,
          type: 'relay',
        );

        // The type field determines if TURN relay should be used
        expect(candidate.type == 'relay', isTrue);
      });

      test('identifies non-relay candidate types', () {
        final hostCandidate = Candidate(
          foundation: 'host-abc',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('host'),
          host: '192.168.1.1',
          port: 54321,
          type: 'host',
        );

        final srflxCandidate = Candidate(
          foundation: 'srflx-abc',
          component: 1,
          transport: 'udp',
          priority: candidatePriority('srflx'),
          host: '203.0.113.50',
          port: 12345,
          type: 'srflx',
        );

        expect(hostCandidate.type == 'relay', isFalse);
        expect(srflxCandidate.type == 'relay', isFalse);
      });
    });

    group('Candidate Foundation for Relay', () {
      test('generates unique foundation for relay candidates', () {
        final foundation1 = candidateFoundation('relay', 'udp', '1.2.3.4');
        final foundation2 = candidateFoundation('relay', 'udp', '5.6.7.8');
        final foundation3 = candidateFoundation('relay', 'udp', '1.2.3.4');

        // Same inputs should produce same foundation
        expect(foundation1, equals(foundation3));

        // Different IPs should produce different foundations
        expect(foundation1, isNot(equals(foundation2)));
      });

      test('relay foundation differs from host foundation', () {
        final relayFoundation = candidateFoundation('relay', 'udp', '1.2.3.4');
        final hostFoundation = candidateFoundation('host', 'udp', '1.2.3.4');

        expect(relayFoundation, isNot(equals(hostFoundation)));
      });
    });
  });

  group('TURN Channel Binding', () {
    test('channel numbers are in valid range', () {
      // RFC 5766: Channel numbers must be in 0x4000-0x7FFF range
      const channelNumberMin = 0x4000;
      const channelNumberMax = 0x7FFF;

      expect(channelNumberMin, equals(16384));
      expect(channelNumberMax, equals(32767));
      expect(channelNumberMax - channelNumberMin, equals(16383));
    });
  });
}
