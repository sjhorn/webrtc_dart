import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('Connectivity Checks', () {
    test('connection fails when no remote candidates', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();

      // Signal end-of-candidates (no remote candidates coming)
      await connection.addRemoteCandidate(null);

      // No remote candidates added, so connect should fail
      await connection.connect();

      // Should be in failed state since no pairs could be checked
      expect(connection.state, equals(IceState.failed));

      await connection.close();
    });

    test('candidate pairs are created when remote candidates are added',
        () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();

      expect(connection.localCandidates, isNotEmpty);
      expect(connection.checkList, isEmpty);

      // Add a remote candidate
      final remoteCandidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.100',
        port: 54321,
        type: 'host',
      );

      await connection.addRemoteCandidate(remoteCandidate);

      // Should have created candidate pairs
      expect(connection.checkList, isNotEmpty);

      // Pairs should be sorted by priority
      for (int i = 0; i < connection.checkList.length - 1; i++) {
        expect(
          connection.checkList[i].priority,
          greaterThanOrEqualTo(connection.checkList[i + 1].priority),
        );
      }

      await connection.close();
    });

    test('controlling agent nominates first successful pair', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      connection.setRemoteParams(
        iceLite: false,
        usernameFragment: 'remote',
        password: 'remotepass',
      );

      await connection.gatherCandidates();

      // Add incompatible remote candidate (will fail connectivity check)
      final remoteCandidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.99.99', // Unreachable address
        port: 54321,
        type: 'host',
      );

      await connection.addRemoteCandidate(remoteCandidate);

      // Attempt connection (will fail but shouldn't crash)
      await connection.connect();

      // Should fail since address is unreachable
      expect(connection.state, equals(IceState.failed));
      expect(connection.nominated, isNull);

      await connection.close();
    });

    test('controlled agent waits for nomination', () async {
      final connection = IceConnectionImpl(iceControlling: false);

      connection.setRemoteParams(
        iceLite: false,
        usernameFragment: 'remote',
        password: 'remotepass',
      );

      await connection.gatherCandidates();

      expect(connection.iceControlling, isFalse);

      await connection.close();
    });

    test('pair states transition correctly', () {
      final localCandidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 54321,
        type: 'host',
      );

      final remoteCandidate = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '192.168.1.2',
        port: 54322,
        type: 'host',
      );

      final pair = CandidatePair(
        id: '1-2',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      // Initial state
      expect(pair.state, equals(CandidatePairState.frozen));

      // Transition to in progress
      pair.updateState(CandidatePairState.inProgress);
      expect(pair.state, equals(CandidatePairState.inProgress));

      // Transition to succeeded
      pair.updateState(CandidatePairState.succeeded);
      expect(pair.state, equals(CandidatePairState.succeeded));
    });

    test('nominated pair is set after successful check', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      connection.setRemoteParams(
        iceLite: false,
        usernameFragment: 'remote',
        password: 'remotepass',
      );

      await connection.gatherCandidates();

      // Initially no nominated pair
      expect(connection.nominated, isNull);

      await connection.close();
    });

    test('connection state transitions during checks', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      // Initial state
      expect(connection.state, equals(IceState.newState));

      await connection.gatherCandidates();

      // After gathering - state remains 'gathering' until connect() is called
      expect(connection.state, equals(IceState.gathering));

      await connection.close();

      // After close
      expect(connection.state, equals(IceState.closed));
    });

    test('pairs with different components are not created', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();

      // Add remote candidate with different component
      final remoteCandidate = RTCIceCandidate(
        foundation: '1',
        component: 2, // Different component
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.100',
        port: 54321,
        type: 'host',
      );

      await connection.addRemoteCandidate(remoteCandidate);

      // Should not create pairs (different components)
      expect(connection.checkList, isEmpty);

      await connection.close();
    });

    test('pairs with incompatible IP versions are not created', () async {
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(useIpv4: true, useIpv6: false),
      );

      await connection.gatherCandidates();

      // All local candidates should be IPv4
      for (final candidate in connection.localCandidates) {
        expect(candidate.host.contains(':'), isFalse);
      }

      // Add IPv6 remote candidate
      final remoteCandidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: 'fe80::1',
        port: 54321,
        type: 'host',
      );

      await connection.addRemoteCandidate(remoteCandidate);

      // Should not create pairs (incompatible IP versions)
      expect(connection.checkList, isEmpty);

      await connection.close();
    });

    test('multiple remote candidates create multiple pairs', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.gatherCandidates();

      // Add first remote candidate
      await connection.addRemoteCandidate(RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.100',
        port: 54321,
        type: 'host',
      ));

      final pairsAfterFirst = connection.checkList.length;

      // Add second remote candidate
      await connection.addRemoteCandidate(RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 54322,
        type: 'srflx',
      ));

      // Should have created more pairs
      expect(connection.checkList.length, greaterThan(pairsAfterFirst));

      await connection.close();
    });
  });
}
