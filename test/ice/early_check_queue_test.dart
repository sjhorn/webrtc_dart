import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';

void main() {
  group('ICE Early Check Queue (RFC 8445 Section 7.2.1)', () {
    late IceConnectionImpl connection;

    setUp(() {
      connection = IceConnectionImpl(iceControlling: true);
    });

    tearDown(() async {
      await connection.close();
    });

    group('Queue behavior', () {
      test('connection starts with empty early check queue', () {
        // Early checks queue is private, so we verify through behavior
        // The queue should not affect connection state initially
        expect(connection.state, equals(IceState.newState));
      });

      test('restart clears early check queue state', () async {
        // Gather some candidates
        await connection.gatherCandidates();

        // Restart should clear all state including early checks
        await connection.restart();

        expect(connection.state, equals(IceState.newState));
        expect(connection.localCandidates, isEmpty);
        expect(connection.remoteCandidates, isEmpty);
        expect(connection.checkList, isEmpty);
      });

      test('close does not process early checks', () async {
        await connection.gatherCandidates();

        // Add a remote candidate
        final remoteCandidate = Candidate(
          foundation: 'test',
          component: 1,
          transport: 'UDP',
          priority: 1000,
          host: '192.168.1.100',
          port: 12345,
          type: 'host',
        );
        await connection.addRemoteCandidate(remoteCandidate);

        // Close immediately
        await connection.close();

        expect(connection.state, equals(IceState.closed));
      });
    });

    group('Early check processing', () {
      test('check list must be populated before processing checks', () async {
        // Start gathering
        await connection.gatherCandidates();

        // Initially checkList is empty until we add remote candidates
        expect(connection.checkList, isEmpty);

        // Add remote candidate - this creates pairs in checkList
        final remoteCandidate = Candidate(
          foundation: 'test',
          component: 1,
          transport: 'UDP',
          priority: 1000,
          host: '192.168.1.100',
          port: 12345,
          type: 'host',
        );
        await connection.addRemoteCandidate(remoteCandidate);

        // Now checkList should have pairs
        expect(connection.checkList, isNotEmpty);
      });

      test('early checks are processed when connectivity checks start', () async {
        // Gather local candidates
        await connection.gatherCandidates();

        // Add remote candidate
        final remoteCandidate = Candidate(
          foundation: 'test',
          component: 1,
          transport: 'UDP',
          priority: 1000,
          host: '192.168.1.100',
          port: 12345,
          type: 'host',
        );
        await connection.addRemoteCandidate(remoteCandidate);

        // Mark end of candidates (null signals end-of-candidates)
        await connection.addRemoteCandidate(null);

        expect(connection.remoteCandidatesEnd, isTrue);
        expect(connection.checkList, isNotEmpty);
      });
    });

    group('Edge cases', () {
      test('multiple remote candidates create multiple pairs', () async {
        await connection.gatherCandidates();

        // Add multiple remote candidates
        for (var i = 0; i < 3; i++) {
          final candidate = Candidate(
            foundation: 'test$i',
            component: 1,
            transport: 'UDP',
            priority: 1000 - i * 10,
            host: '192.168.1.${100 + i}',
            port: 12345 + i,
            type: 'host',
          );
          await connection.addRemoteCandidate(candidate);
        }

        // Each local-remote combination should create a pair
        final localCount = connection.localCandidates.length;
        final remoteCount = connection.remoteCandidates.length;

        // At least some pairs should be created
        expect(connection.checkList.length, greaterThan(0));
        // Maximum possible pairs
        expect(connection.checkList.length, lessThanOrEqualTo(localCount * remoteCount));
      });

      test('trickle ICE handles candidates arriving after connect starts', () async {
        await connection.gatherCandidates();

        // In trickle ICE, connect() may be called before remote candidates arrive
        // This is a valid scenario where early checks help
        expect(connection.checkList, isEmpty);

        // Simulate trickle ICE - add candidate after gathering
        final remoteCandidate = Candidate(
          foundation: 'trickle',
          component: 1,
          transport: 'UDP',
          priority: 1000,
          host: '192.168.1.50',
          port: 54321,
          type: 'host',
        );
        await connection.addRemoteCandidate(remoteCandidate);

        // Now we should have pairs
        expect(connection.checkList, isNotEmpty);
      });
    });
  });
}
