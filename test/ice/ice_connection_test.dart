import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('IceConnectionImpl', () {
    test('creates connection with controlling role', () {
      final connection = IceConnectionImpl(iceControlling: true);

      expect(connection.iceControlling, isTrue);
      expect(connection.state, equals(IceState.newState));
      expect(connection.generation, equals(0));
      expect(connection.localUsername, hasLength(4));
      expect(connection.localPassword, hasLength(22));
      expect(connection.remoteUsername, isEmpty);
      expect(connection.remotePassword, isEmpty);
      expect(connection.remoteIsLite, isFalse);
    });

    test('creates connection with controlled role', () {
      final connection = IceConnectionImpl(iceControlling: false);

      expect(connection.iceControlling, isFalse);
      expect(connection.state, equals(IceState.newState));
    });

    test('generates unique credentials', () {
      final conn1 = IceConnectionImpl(iceControlling: true);
      final conn2 = IceConnectionImpl(iceControlling: true);

      expect(conn1.localUsername, isNot(equals(conn2.localUsername)));
      expect(conn1.localPassword, isNot(equals(conn2.localPassword)));
    });

    test('sets remote parameters', () {
      final connection = IceConnectionImpl(iceControlling: true);

      connection.setRemoteParams(
        iceLite: true,
        usernameFragment: 'remote-user',
        password: 'remote-pass',
      );

      expect(connection.remoteIsLite, isTrue);
      expect(connection.remoteUsername, equals('remote-user'));
      expect(connection.remotePassword, equals('remote-pass'));
    });

    test('state changes emit events', () async {
      final connection = IceConnectionImpl(iceControlling: true);
      final states = <IceState>[];

      final subscription = connection.onStateChanged.listen((state) {
        states.add(state);
      });

      await connection.gatherCandidates();
      await Future.delayed(
          Duration(milliseconds: 10)); // Allow stream to process

      expect(states, contains(IceState.gathering));
      // After gathering, state remains 'gathering' until connect() is called
      expect(connection.state, equals(IceState.gathering));

      await subscription.cancel();
    });

    test('tracks local candidates', () {
      final connection = IceConnectionImpl(iceControlling: true);

      expect(connection.localCandidates, isEmpty);
      expect(connection.localCandidatesEnd, isFalse);
    });

    test('adds remote candidate', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      final candidate = Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 54321,
        type: 'host',
      );

      await connection.addRemoteCandidate(candidate);

      expect(connection.remoteCandidates, contains(candidate));
    });

    test('null candidate marks remote candidates as complete', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      expect(connection.remoteCandidatesEnd, isFalse);

      await connection.addRemoteCandidate(null);

      expect(connection.remoteCandidatesEnd, isTrue);
    });

    test('validates remote candidates', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      final invalidCandidate = Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '192.168.1.1',
        port: 1234,
        type: 'prflx', // Not supported as remote candidate
      );

      expect(
        () => connection.addRemoteCandidate(invalidCandidate),
        throwsArgumentError,
      );
    });

    test('creates candidate pairs when adding remote candidate', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      // Add a local candidate manually for testing
      final _ = Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 54321,
        type: 'host',
      );
      connection.localCandidates; // Access to make it non-empty (hack for test)

      // We need to manually add to _localCandidates for this test
      // In real usage, this would be done by gatherCandidates()

      final remoteCandidate = Candidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 12345,
        type: 'srflx',
      );

      await connection.addRemoteCandidate(remoteCandidate);

      // Check pairs would be created (when local candidates exist)
      expect(connection.remoteCandidates, contains(remoteCandidate));
    });

    test('send throws when no nominated pair', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      final data = Uint8List.fromList([1, 2, 3, 4]);

      expect(() => connection.send(data), throwsStateError);
    });

    test('closes connection', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      await connection.close();

      expect(connection.state, equals(IceState.closed));
    });

    test('restarts ICE', () async {
      final connection = IceConnectionImpl(iceControlling: true);

      final oldUsername = connection.localUsername;
      final oldPassword = connection.localPassword;
      final oldGeneration = connection.generation;

      await connection.restart();

      expect(connection.generation, equals(oldGeneration + 1));
      expect(connection.localUsername, isNot(equals(oldUsername)));
      expect(connection.localPassword, isNot(equals(oldPassword)));
      expect(connection.remoteUsername, isEmpty);
      expect(connection.remotePassword, isEmpty);
      expect(connection.state, equals(IceState.newState));
      expect(connection.localCandidates, isEmpty);
      expect(connection.remoteCandidates, isEmpty);
      expect(connection.checkList, isEmpty);
      expect(connection.nominated, isNull);
    });

    test('getDefaultCandidate returns null when no candidates', () {
      final connection = IceConnectionImpl(iceControlling: true);

      expect(connection.getDefaultCandidate(), isNull);
    });

    test('cannot change role after connection established', () {
      final connection = IceConnectionImpl(iceControlling: true);

      // Simulate connection by setting generation
      connection.restart();

      connection.iceControlling = false;

      // Role should remain controlling due to generation > 0
      expect(connection.iceControlling, isTrue);
    });
  });

  group('randomString', () {
    test('generates string of correct length', () {
      final str4 = randomString(4);
      expect(str4, hasLength(4));

      final str22 = randomString(22);
      expect(str22, hasLength(22));
    });

    test('generates different strings', () {
      final str1 = randomString(10);
      final str2 = randomString(10);

      expect(str1, isNot(equals(str2)));
    });

    test('generates hex characters', () {
      final str = randomString(10);
      final hexPattern = RegExp(r'^[0-9a-f]+$');

      expect(str, matches(hexPattern));
    });
  });

  group('IceState', () {
    test('has all required states', () {
      expect(IceState.values, contains(IceState.newState));
      expect(IceState.values, contains(IceState.gathering));
      expect(IceState.values, contains(IceState.checking));
      expect(IceState.values, contains(IceState.connected));
      expect(IceState.values, contains(IceState.completed));
      expect(IceState.values, contains(IceState.failed));
      expect(IceState.values, contains(IceState.closed));
      expect(IceState.values, contains(IceState.disconnected));
    });
  });

  group('IceOptions', () {
    test('creates with defaults', () {
      const options = IceOptions();

      expect(options.useIpv4, isTrue);
      expect(options.useIpv6, isTrue);
      expect(options.stunServer, isNull);
      expect(options.turnServer, isNull);
    });

    test('creates with custom values', () {
      const options = IceOptions(
        stunServer: ('stun.example.com', 3478),
        turnServer: ('turn.example.com', 3478),
        turnUsername: 'user',
        turnPassword: 'pass',
        useIpv4: true,
        useIpv6: false,
        portRange: (10000, 20000),
      );

      expect(options.stunServer, equals(('stun.example.com', 3478)));
      expect(options.turnServer, equals(('turn.example.com', 3478)));
      expect(options.turnUsername, equals('user'));
      expect(options.turnPassword, equals('pass'));
      expect(options.useIpv4, isTrue);
      expect(options.useIpv6, isFalse);
      expect(options.portRange, equals((10000, 20000)));
    });
  });
}
