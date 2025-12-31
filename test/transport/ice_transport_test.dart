import 'dart:async';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';
import 'package:webrtc_dart/src/transport/ice_transport.dart';

void main() {
  group('RtcIceConnectionState', () {
    test('enum has expected values', () {
      expect(RtcIceConnectionState.values.length, 7);
      expect(RtcIceConnectionState.new_, isNotNull);
      expect(RtcIceConnectionState.checking, isNotNull);
      expect(RtcIceConnectionState.connected, isNotNull);
      expect(RtcIceConnectionState.completed, isNotNull);
      expect(RtcIceConnectionState.disconnected, isNotNull);
      expect(RtcIceConnectionState.failed, isNotNull);
      expect(RtcIceConnectionState.closed, isNotNull);
    });
  });

  group('RtcIceTransport', () {
    late IceConnection connection;
    late RtcIceGatherer gatherer;
    late RtcIceTransport transport;

    setUp(() {
      connection = IceConnectionImpl(iceControlling: true);
      gatherer = RtcIceGatherer(connection);
      transport = RtcIceTransport(gatherer);
    });

    tearDown(() async {
      await transport.stop();
    });

    test('initial state is new', () {
      expect(transport.state, RtcIceConnectionState.new_);
    });

    test('exposes underlying connection', () {
      expect(transport.connection, connection);
    });

    test('role reflects iceControlling flag', () {
      expect(transport.role, 'controlling');

      // Create a controlled transport
      final ice2 = IceConnectionImpl(iceControlling: false);
      final gatherer2 = RtcIceGatherer(ice2);
      final transport2 = RtcIceTransport(gatherer2);

      expect(transport2.role, 'controlled');

      transport2.stop();
    });

    test('gatheringState proxies from gatherer', () {
      expect(transport.gatheringState, gatherer.gatheringState);
    });

    test('localCandidates proxies from gatherer', () {
      expect(transport.localCandidates, gatherer.localCandidates);
    });

    test('localParameters proxies from gatherer', () {
      final transportParams = transport.localParameters;
      final gathererParams = gatherer.localParameters;

      expect(transportParams.usernameFragment, gathererParams.usernameFragment);
      expect(transportParams.password, gathererParams.password);
    });

    test('remoteCandidates initially empty', () {
      expect(transport.remoteCandidates, isEmpty);
    });

    test('candidatePairs initially empty', () {
      expect(transport.candidatePairs, isEmpty);
    });

    test('gather() delegates to gatherer', () async {
      await transport.gather();

      expect(transport.gatheringState, IceGathererState.complete);
      expect(transport.localCandidates, isNotEmpty);
    });

    test('start() throws if closed', () async {
      await transport.stop();

      expect(
        () => transport.start(),
        throwsStateError,
      );
    });

    test('start() throws without remote parameters', () async {
      // Set up with local candidates but no remote params
      await transport.gather();

      expect(
        () => transport.start(),
        throwsStateError,
      );
    });

    test('restart() resets state to new', () async {
      // First get to a non-new state by setting remote params
      transport.setRemoteParams(RtcIceParameters(
        usernameFragment: 'remoteUfrag',
        password: 'remotePassword',
      ));

      // Now restart
      transport.restart();

      expect(transport.state, RtcIceConnectionState.new_);
      expect(transport.gatheringState, IceGathererState.new_);
    });

    test('restart() emits negotiation needed event', () async {
      var negotiationNeeded = false;
      transport.onNegotiationNeeded.listen((_) {
        negotiationNeeded = true;
      });

      transport.restart();

      await Future.delayed(Duration(milliseconds: 10));
      expect(negotiationNeeded, true);
    });

    test('setRemoteParams sets credentials on connection', () {
      transport.setRemoteParams(RtcIceParameters(
        usernameFragment: 'remoteUfrag',
        password: 'remotePassword',
        iceLite: false,
      ));

      expect(connection.remoteUsername, 'remoteUfrag');
      expect(connection.remotePassword, 'remotePassword');
    });

    test('setRemoteParams with changed credentials triggers restart', () async {
      // Set initial remote params
      transport.setRemoteParams(RtcIceParameters(
        usernameFragment: 'ufrag1',
        password: 'password1',
      ));

      final states = <RtcIceConnectionState>[];
      transport.onStateChange.listen(states.add);

      // Set different params - should trigger restart
      transport.setRemoteParams(RtcIceParameters(
        usernameFragment: 'ufrag2',
        password: 'password2',
      ));

      await Future.delayed(Duration(milliseconds: 10));

      // Should have transitioned back to new state
      expect(transport.state, RtcIceConnectionState.new_);
    });

    test('stop() transitions to closed state', () async {
      await transport.stop();

      expect(transport.state, RtcIceConnectionState.closed);
    });

    test('stop() is idempotent', () async {
      await transport.stop();
      await transport.stop(); // Should not throw

      expect(transport.state, RtcIceConnectionState.closed);
    });

    test('onStateChange emits state transitions', () async {
      final states = <RtcIceConnectionState>[];
      transport.onStateChange.listen(states.add);

      await transport.stop();

      expect(states, contains(RtcIceConnectionState.closed));
    });

    test('onIceCandidate forwards from gatherer', () async {
      // Subscribe before gathering to ensure we catch all events
      final candidateCompleter = Completer<void>();
      final candidates = <dynamic>[];
      transport.onIceCandidate.listen((c) {
        candidates.add(c);
        if (c == null) {
          // End of candidates signal
          candidateCompleter.complete();
        }
      });

      await transport.gather();
      await candidateCompleter.future.timeout(Duration(seconds: 5));

      // Should have received at least one element (the null for end-of-candidates)
      expect(candidates, isNotEmpty);
      // Last element should be null (end-of-candidates signal)
      expect(candidates.last, isNull);
    });
  });

  group('RtcIceTransport integration', () {
    test('two transports can establish connection', () async {
      final ice1 = IceConnectionImpl(iceControlling: true);
      final ice2 = IceConnectionImpl(iceControlling: false);

      final gatherer1 = RtcIceGatherer(ice1);
      final gatherer2 = RtcIceGatherer(ice2);

      final transport1 = RtcIceTransport(gatherer1);
      final transport2 = RtcIceTransport(gatherer2);

      try {
        // Gather candidates
        await Future.wait([transport1.gather(), transport2.gather()]);

        // Exchange ICE parameters
        transport1.setRemoteParams(transport2.localParameters);
        transport2.setRemoteParams(transport1.localParameters);

        // Exchange candidates
        for (final candidate in transport1.localCandidates) {
          await transport2.addRemoteCandidate(candidate);
        }
        for (final candidate in transport2.localCandidates) {
          await transport1.addRemoteCandidate(candidate);
        }

        // Signal end of candidates
        await transport1.addRemoteCandidate(null);
        await transport2.addRemoteCandidate(null);

        // Track state changes
        final states1 = <RtcIceConnectionState>[];
        final states2 = <RtcIceConnectionState>[];
        transport1.onStateChange.listen(states1.add);
        transport2.onStateChange.listen(states2.add);

        // Start connectivity checks
        await Future.wait([
          transport1.start(),
          transport2.start(),
        ]);

        // Both should reach connected or completed state
        final connectedStates = [
          RtcIceConnectionState.connected,
          RtcIceConnectionState.completed,
        ];
        expect(
          connectedStates.contains(transport1.state) ||
              states1.any((s) => connectedStates.contains(s)),
          true,
        );
        expect(
          connectedStates.contains(transport2.state) ||
              states2.any((s) => connectedStates.contains(s)),
          true,
        );
      } finally {
        await transport1.stop();
        await transport2.stop();
      }
    });

    test('transport handles ICE restart', () async {
      final ice1 = IceConnectionImpl(iceControlling: true);
      final ice2 = IceConnectionImpl(iceControlling: false);

      final gatherer1 = RtcIceGatherer(ice1);
      final gatherer2 = RtcIceGatherer(ice2);

      final transport1 = RtcIceTransport(gatherer1);
      final transport2 = RtcIceTransport(gatherer2);

      try {
        // Set up initial connection
        await Future.wait([transport1.gather(), transport2.gather()]);
        transport1.setRemoteParams(transport2.localParameters);
        transport2.setRemoteParams(transport1.localParameters);

        // Restart transport1
        transport1.restart();

        // Should be back to new state
        expect(transport1.state, RtcIceConnectionState.new_);
        expect(transport1.gatheringState, IceGathererState.new_);

        // Can gather again
        await transport1.gather();
        expect(transport1.gatheringState, IceGathererState.complete);
      } finally {
        await transport1.stop();
        await transport2.stop();
      }
    });
  });
}
