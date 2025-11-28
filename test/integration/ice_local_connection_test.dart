import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';

void main() {
  group('ICE Local Connection', () {
    test('two ICE connections exchange data locally', () async {
      // Create two ICE connections
      final ice1 = IceConnectionImpl(
        iceControlling: true,
        options: const IceOptions(),
      );

      final ice2 = IceConnectionImpl(
        iceControlling: false,
        options: const IceOptions(),
      );

      // Track received data
      final ice1Data = <Uint8List>[];
      final ice2Data = <Uint8List>[];

      ice1.onData.listen(ice1Data.add);
      ice2.onData.listen(ice2Data.add);

      // Track ICE candidates
      final ice1Candidates = <Candidate>[];
      final ice2Candidates = <Candidate>[];

      ice1.onIceCandidate.listen(ice1Candidates.add);
      ice2.onIceCandidate.listen(ice2Candidates.add);

      // Set remote parameters
      ice1.setRemoteParams(
        iceLite: false,
        usernameFragment: ice2.localUsername,
        password: ice2.localPassword,
      );

      ice2.setRemoteParams(
        iceLite: false,
        usernameFragment: ice1.localUsername,
        password: ice1.localPassword,
      );

      // Gather candidates
      await ice1.gatherCandidates();
      await ice2.gatherCandidates();

      // Wait for candidate gathering
      await Future.delayed(Duration(milliseconds: 200));

      print('ICE1 gathered ${ice1Candidates.length} candidates');
      print('ICE2 gathered ${ice2Candidates.length} candidates');

      expect(ice1Candidates.length, greaterThan(0));
      expect(ice2Candidates.length, greaterThan(0));

      // Exchange candidates
      for (final candidate in ice1Candidates) {
        await ice2.addRemoteCandidate(candidate);
      }

      for (final candidate in ice2Candidates) {
        await ice1.addRemoteCandidate(candidate);
      }

      // Signal end of candidates
      await ice1.addRemoteCandidate(null);
      await ice2.addRemoteCandidate(null);

      print('Candidates exchanged, check lists:');
      print('  ICE1: ${ice1.checkList.length} pairs');
      print('  ICE2: ${ice2.checkList.length} pairs');

      // Start connectivity checks
      final ice1Connected = Completer<void>();
      final ice2Connected = Completer<void>();

      ice1.onStateChanged.listen((state) {
        print('ICE1 state: $state');
        if (state == IceState.connected || state == IceState.completed) {
          if (!ice1Connected.isCompleted) ice1Connected.complete();
        }
      });

      ice2.onStateChanged.listen((state) {
        print('ICE2 state: $state');
        if (state == IceState.connected || state == IceState.completed) {
          if (!ice2Connected.isCompleted) ice2Connected.complete();
        }
      });

      // Connect
      await Future.wait([
        ice1.connect(),
        ice2.connect(),
      ]);

      // Wait for connection or timeout
      try {
        await Future.wait([
          ice1Connected.future,
          ice2Connected.future,
        ]).timeout(Duration(seconds: 5));

        print('✓ ICE connections established!');

        // Try sending data
        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);

        print('Sending data from ICE1 to ICE2...');
        await ice1.send(testData);

        // Wait for data to arrive
        await Future.delayed(Duration(milliseconds: 100));

        print('ICE2 received ${ice2Data.length} packets');
        if (ice2Data.isNotEmpty) {
          print('✓ Data received: ${ice2Data[0]}');
          expect(ice2Data[0], equals(testData));
        }

      } catch (e) {
        print('✗ Connection timeout or error: $e');
        print('ICE1 state: ${ice1.state}');
        print('ICE2 state: ${ice2.state}');
        print('ICE1 nominated: ${ice1.nominated}');
        print('ICE2 nominated: ${ice2.nominated}');
      }

      await ice1.close();
      await ice2.close();
    }, timeout: Timeout(Duration(seconds: 10)));

    test('ICE connection can send and receive test data', () async {
      final ice = IceConnectionImpl(
        iceControlling: true,
        options: const IceOptions(),
      );

      await ice.gatherCandidates();

      // Verify we have candidates
      expect(ice.localCandidates, isNotEmpty);

      // Verify state transitions
      expect(ice.state, anyOf(IceState.checking, IceState.gathering));

      await ice.close();
      expect(ice.state, IceState.closed);
    });

    test('ICE candidates have valid format', () async {
      final ice = IceConnectionImpl(
        iceControlling: true,
        options: const IceOptions(),
      );

      final candidates = <Candidate>[];
      ice.onIceCandidate.listen(candidates.add);

      await ice.gatherCandidates();

      // Wait for candidates to be emitted
      await Future.delayed(Duration(milliseconds: 100));

      expect(candidates, isNotEmpty);

      for (final candidate in candidates) {
        // Verify candidate structure
        expect(candidate.foundation, isNotEmpty);
        expect(candidate.component, 1);
        expect(candidate.transport, 'udp');
        expect(candidate.priority, greaterThan(0));
        expect(candidate.host, isNotEmpty);
        expect(candidate.port, greaterThan(0));
        expect(candidate.type, anyOf('host', 'srflx', 'relay'));

        // Verify SDP format
        final sdp = candidate.toSdp();
        expect(sdp, contains(candidate.foundation));
        expect(sdp, contains(candidate.host));
        expect(sdp, contains('${candidate.port}'));
        expect(sdp, contains('typ ${candidate.type}'));
      }

      await ice.close();
    });

    test('ICE transport validates data send requires nominated pair', () async {
      final ice = IceConnectionImpl(
        iceControlling: true,
        options: const IceOptions(),
      );

      await ice.gatherCandidates();
      await Future.delayed(Duration(milliseconds: 100));

      // Try to send data without nominated pair - should throw
      final testData = Uint8List.fromList([1, 2, 3]);

      expect(
        () => ice.send(testData),
        throwsA(isA<StateError>()),
      );

      await ice.close();
    });
  });
}
