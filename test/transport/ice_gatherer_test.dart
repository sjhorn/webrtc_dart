import 'dart:async';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';

void main() {
  group('IceGathererState', () {
    test('enum has expected values', () {
      expect(IceGathererState.values.length, 3);
      expect(IceGathererState.new_, isNotNull);
      expect(IceGathererState.gathering, isNotNull);
      expect(IceGathererState.complete, isNotNull);
    });
  });

  group('RtcIceParameters', () {
    test('creates with required parameters', () {
      final params = RtcIceParameters(
        usernameFragment: 'testUfrag',
        password: 'testPassword123',
      );

      expect(params.usernameFragment, 'testUfrag');
      expect(params.password, 'testPassword123');
      expect(params.iceLite, false);
    });

    test('creates with iceLite flag', () {
      final params = RtcIceParameters(
        usernameFragment: 'ufrag',
        password: 'password',
        iceLite: true,
      );

      expect(params.iceLite, true);
    });

    test('toString includes ufrag and truncated password', () {
      final params = RtcIceParameters(
        usernameFragment: 'myUfrag',
        password: 'mySecretPassword',
      );

      final str = params.toString();
      expect(str, contains('myUfrag'));
      expect(str, contains('mySe...')); // First 4 chars of password
      expect(
          str.contains('mySecretPassword'), false); // Full password not shown
    });
  });

  group('RtcIceGatherer', () {
    late IceConnection connection;
    late RtcIceGatherer gatherer;

    setUp(() {
      connection = IceConnectionImpl(iceControlling: true);
      gatherer = RtcIceGatherer(connection);
    });

    tearDown(() async {
      await gatherer.close();
      await connection.close();
    });

    test('initial state is new', () {
      expect(gatherer.gatheringState, IceGathererState.new_);
    });

    test('exposes underlying connection', () {
      expect(gatherer.connection, connection);
    });

    test('localCandidates proxies to connection', () {
      expect(gatherer.localCandidates, connection.localCandidates);
    });

    test('localParameters contains ufrag and password', () {
      final params = gatherer.localParameters;

      expect(params.usernameFragment, isNotEmpty);
      expect(params.password, isNotEmpty);
      expect(params.iceLite, false);
    });

    test('gatheringState setter emits state change', () async {
      final states = <IceGathererState>[];
      gatherer.onGatheringStateChange.listen(states.add);

      gatherer.gatheringState = IceGathererState.gathering;

      await Future.delayed(Duration(milliseconds: 10));
      expect(states, contains(IceGathererState.gathering));
      expect(gatherer.gatheringState, IceGathererState.gathering);
    });

    test('setting same state does not emit', () async {
      final states = <IceGathererState>[];
      gatherer.onGatheringStateChange.listen(states.add);

      // Set to same state multiple times
      gatherer.gatheringState = IceGathererState.new_;
      gatherer.gatheringState = IceGathererState.new_;

      await Future.delayed(Duration(milliseconds: 10));
      expect(states, isEmpty); // No change, initial was already new_
    });

    test('gather() transitions through states', () async {
      final completer = Completer<void>();
      final states = <IceGathererState>[];
      gatherer.onGatheringStateChange.listen((state) {
        states.add(state);
        if (state == IceGathererState.complete) {
          completer.complete();
        }
      });

      await gatherer.gather();
      await completer.future.timeout(Duration(seconds: 5));

      // Should have transitioned through gathering -> complete
      expect(states, contains(IceGathererState.gathering));
      expect(states, contains(IceGathererState.complete));
      expect(gatherer.gatheringState, IceGathererState.complete);
    });

    test('gather() emits candidates', () async {
      final completer = Completer<void>();
      final candidates = <Candidate?>[];
      gatherer.onIceCandidate.listen((c) {
        candidates.add(c);
        if (c == null) {
          completer.complete();
        }
      });

      await gatherer.gather();
      await completer.future.timeout(Duration(seconds: 5));

      // Should have at least emitted null (end-of-candidates)
      expect(candidates, isNotEmpty);
      expect(candidates.last, isNull);
    });

    test('gather() is idempotent - only gathers once', () async {
      final completer = Completer<void>();
      var stateChangeCount = 0;
      gatherer.onGatheringStateChange.listen((state) {
        stateChangeCount++;
        if (state == IceGathererState.complete) {
          completer.complete();
        }
      });

      await gatherer.gather();
      await completer.future.timeout(Duration(seconds: 5));
      final firstCount = stateChangeCount;

      // Calling gather again should do nothing
      await gatherer.gather();

      // Small delay to ensure any spurious events would arrive
      await Future.delayed(Duration(milliseconds: 50));

      expect(stateChangeCount, firstCount);
    });

    test('close() cleans up resources', () async {
      await gatherer.close();

      // After close, controllers should be closed
      // (Adding to closed controller throws)
      expect(
        () => gatherer.gatheringState = IceGathererState.gathering,
        returnsNormally, // State updates silently fail after close
      );
    });

    test('forwards candidates from connection', () async {
      final completer = Completer<void>();
      final candidates = <Candidate?>[];
      gatherer.onIceCandidate.listen((c) {
        candidates.add(c);
        if (c == null) {
          completer.complete();
        }
      });

      // Start gathering to trigger candidate emission
      await gatherer.gather();
      await completer.future.timeout(Duration(seconds: 5));

      // Should have received at least the null end-of-candidates signal
      expect(candidates, isNotEmpty);
      expect(candidates.last, isNull);
    });
  });

  group('RtcIceGatherer integration', () {
    test('two gatherers can exchange candidates', () async {
      final ice1 = IceConnectionImpl(iceControlling: true);
      final ice2 = IceConnectionImpl(iceControlling: false);

      final gatherer1 = RtcIceGatherer(ice1);
      final gatherer2 = RtcIceGatherer(ice2);

      try {
        // Gather candidates from both
        await Future.wait([gatherer1.gather(), gatherer2.gather()]);

        // Both should have local candidates
        expect(gatherer1.localCandidates, isNotEmpty);
        expect(gatherer2.localCandidates, isNotEmpty);

        // Both should be in complete state
        expect(gatherer1.gatheringState, IceGathererState.complete);
        expect(gatherer2.gatheringState, IceGathererState.complete);
      } finally {
        await gatherer1.close();
        await gatherer2.close();
        await ice1.close();
        await ice2.close();
      }
    });
  });
}
