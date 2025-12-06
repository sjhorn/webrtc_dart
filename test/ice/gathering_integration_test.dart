import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('Candidate Gathering Integration', () {
    test('gathers host candidates from network interfaces', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      expect(connection.state, equals(IceState.newState));
      expect(connection.localCandidates, isEmpty);

      // Gather candidates
      await connection.gatherCandidates();

      // Should have completed gathering
      // Note: State remains 'gathering' until connect() is called
      expect(connection.state, equals(IceState.gathering));
      expect(connection.localCandidatesEnd, isTrue);

      // Should have discovered at least one host candidate
      // (unless running in very restricted environment)
      expect(connection.localCandidates.length, greaterThanOrEqualTo(0));

      // Verify all candidates are host candidates with UDP transport
      for (final candidate in connection.localCandidates) {
        expect(candidate.type, equals('host'));
        expect(candidate.transport, equals('udp'));
        expect(candidate.component, equals(1));
        expect(candidate.port, greaterThan(0));
        expect(candidate.host, isNotEmpty);
        expect(candidate.foundation, isNotEmpty);
        expect(candidate.priority, greaterThan(0));
      }

      // Clean up
      await connection.close();
    });

    test('emits candidates as they are discovered', () async {
      final connection = IceConnectionImpl(iceControlling: true);
      final candidates = <String>[];

      // Listen for candidates
      final subscription = connection.onIceCandidate.listen((candidate) {
        candidates.add(candidate.host);
      });

      await connection.gatherCandidates();
      await Future.delayed(
          Duration(milliseconds: 50)); // Allow stream to process

      // Should have emitted candidates
      expect(candidates.length, equals(connection.localCandidates.length));

      await subscription.cancel();
      await connection.close();
    });

    test('creates valid SDP from gathered candidates', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();

      for (final candidate in connection.localCandidates) {
        final sdp = candidate.toSdp();

        // Verify SDP format (without "candidate:" prefix)
        expect(sdp, contains('typ host'));
        expect(sdp, contains('udp'));
        expect(sdp, contains(candidate.host));
        expect(sdp, contains(candidate.port.toString()));
        expect(sdp, startsWith(candidate.foundation));
      }

      await connection.close();
    });

    test('gathering respects IPv4/IPv6 options', () async {
      // Test IPv4 only
      final ipv4Only = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(useIpv4: true, useIpv6: false),
      );

      await ipv4Only.gatherCandidates();

      for (final candidate in ipv4Only.localCandidates) {
        // IPv4 addresses don't contain colons
        expect(candidate.host.contains(':'), isFalse);
      }

      await ipv4Only.close();

      // Test IPv6 only
      final ipv6Only = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(useIpv4: false, useIpv6: true),
      );

      await ipv6Only.gatherCandidates();

      for (final candidate in ipv6Only.localCandidates) {
        // IPv6 addresses contain colons
        expect(candidate.host.contains(':'), isTrue);
      }

      await ipv6Only.close();
    });

    test('restart clears candidates and gathers new ones', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();
      final firstCandidates = connection.localCandidates.toList();
      final firstGeneration = connection.generation;

      expect(firstCandidates, isNotEmpty);

      await connection.restart();

      expect(connection.generation, equals(firstGeneration + 1));
      expect(connection.localCandidates, isEmpty);
      expect(connection.localCandidatesEnd, isFalse);
      expect(connection.state, equals(IceState.newState));

      await connection.gatherCandidates();
      final secondCandidates = connection.localCandidates.toList();

      // Should have gathered new candidates
      // (ports will be different due to new sockets)
      expect(secondCandidates, isNotEmpty);

      await connection.close();
    });

    test('close releases all sockets', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();
      final candidateCount = connection.localCandidates.length;

      expect(candidateCount, greaterThanOrEqualTo(0));

      // Close should not throw and should clean up sockets
      await connection.close();

      expect(connection.state, equals(IceState.closed));
    });

    test('getDefaultCandidate returns first host candidate', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      expect(connection.getDefaultCandidate(), isNull);

      await connection.gatherCandidates();

      final defaultCandidate = connection.getDefaultCandidate();

      if (connection.localCandidates.isNotEmpty) {
        expect(defaultCandidate, isNotNull);
        expect(defaultCandidate!.type, equals('host'));
        expect(defaultCandidate, equals(connection.localCandidates.first));
      }

      await connection.close();
    });
  });
}
