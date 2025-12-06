import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/transport/transport.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';

void main() {
  group('DataChannel End-to-End', () {
    test('exchange "hello world" messages between two peers', () async {
      print('\n=== Starting DataChannel E2E Test ===\n');

      // Generate certificates for DTLS
      print('Generating certificates...');
      final cert1 = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Peer 1'),
      );
      final cert2 = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Peer 2'),
      );

      // Create two ICE connections
      print('Creating ICE connections...');
      final ice1 = IceConnectionImpl(
        iceControlling: true,
        options: const IceOptions(),
      );

      final ice2 = IceConnectionImpl(
        iceControlling: false,
        options: const IceOptions(),
      );

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
      print('Gathering ICE candidates...');
      await ice1.gatherCandidates();
      await ice2.gatherCandidates();

      // Wait for candidate gathering
      await Future.delayed(Duration(milliseconds: 200));

      print('Peer 1 gathered ${ice1Candidates.length} candidates');
      print('Peer 2 gathered ${ice2Candidates.length} candidates');

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

      // Track state changes BEFORE creating transports
      final ice1Connected = Completer<void>();
      final ice2Connected = Completer<void>();

      ice1.onStateChanged.listen((state) {
        print('Peer 1 ICE state: $state');
        if (state == IceState.connected || state == IceState.completed) {
          if (!ice1Connected.isCompleted) ice1Connected.complete();
        }
      });

      ice2.onStateChanged.listen((state) {
        print('Peer 2 ICE state: $state');
        if (state == IceState.connected || state == IceState.completed) {
          if (!ice2Connected.isCompleted) ice2Connected.complete();
        }
      });

      // Create integrated transports BEFORE starting ICE
      // This ensures state listeners are set up properly
      print('Creating transports...');
      final transport1 = IntegratedTransport(
        iceConnection: ice1,
        serverCertificate: cert1,
      );

      final transport2 = IntegratedTransport(
        iceConnection: ice2,
        serverCertificate: cert2,
      );

      // Start connectivity checks
      print('Starting ICE connectivity checks...');
      await Future.wait([
        ice1.connect(),
        ice2.connect(),
      ]);

      // Wait for ICE connection
      print('Waiting for ICE connection...');
      await Future.wait([
        ice1Connected.future,
        ice2Connected.future,
      ]).timeout(Duration(seconds: 5));

      print('✓ ICE connections established!');

      // Wait for DTLS and SCTP to establish
      print('Waiting for DTLS and SCTP handshakes...');

      // Track transport state changes
      final transport1Connected = Completer<void>();
      final transport2Connected = Completer<void>();

      transport1.onStateChange.listen((state) {
        print('Transport 1 state: $state');
        if (state == TransportState.connected &&
            !transport1Connected.isCompleted) {
          transport1Connected.complete();
        }
      });

      transport2.onStateChange.listen((state) {
        print('Transport 2 state: $state');
        if (state == TransportState.connected &&
            !transport2Connected.isCompleted) {
          transport2Connected.complete();
        }
      });

      // Wait for both transports to reach connected state
      await Future.wait([
        transport1Connected.future,
        transport2Connected.future,
      ]).timeout(
        Duration(seconds: 5),
        onTimeout: () {
          print('✗ Timeout waiting for transport connection');
          print('Transport 1 final state: ${transport1.state}');
          print('Transport 2 final state: ${transport2.state}');
          throw TimeoutException('Transports did not connect');
        },
      );

      print('✓ Transports connected!');

      // Wait a bit more for SCTP association to establish
      print('Waiting for SCTP association...');
      await Future.delayed(Duration(milliseconds: 500));

      // Create DataChannels
      print('\n--- Creating DataChannels ---');

      // Peer 1 creates a channel
      final channel1 = transport1.createDataChannel(
        label: 'test-channel',
        ordered: true,
      );

      print('Peer 1 created DataChannel: "${channel1.label}"');

      // Track channel state
      final channel1Open = Completer<void>();
      channel1.onStateChange.listen((state) {
        print('Channel 1 state: $state');
        if (state == DataChannelState.open && !channel1Open.isCompleted) {
          channel1Open.complete();
        }
      });

      // Wait for Peer 2 to receive the incoming channel
      print('Waiting for Peer 2 to receive channel...');
      final channel2Completer = Completer<DataChannel>();

      transport2.onDataChannel.listen((channel) {
        print('Peer 2 received DataChannel: "${channel.label}"');
        if (!channel2Completer.isCompleted) {
          channel2Completer.complete(channel);
        }
      });

      // Wait for channel to be received and opened
      final channel2 = await channel2Completer.future.timeout(
        Duration(seconds: 3),
        onTimeout: () {
          print('✗ Timeout waiting for channel 2');
          throw TimeoutException('Did not receive incoming DataChannel');
        },
      );

      final channel2Open = Completer<void>();
      channel2.onStateChange.listen((state) {
        print('Channel 2 state: $state');
        if (state == DataChannelState.open && !channel2Open.isCompleted) {
          channel2Open.complete();
        }
      });

      // Check if already open (state may have changed before listener attached)
      if (channel2.state == DataChannelState.open) {
        print('Channel 2 state: ${channel2.state} (already open)');
        channel2Open.complete();
      }

      // Wait for both channels to open
      print('Waiting for channels to open...');
      await Future.wait([
        channel1Open.future.timeout(Duration(seconds: 3)),
        channel2Open.future.timeout(Duration(seconds: 3)),
      ]);

      print('✓ Both DataChannels are open!');

      // Set up message receivers
      final peer1Messages = <String>[];
      final peer2Messages = <String>[];

      channel1.onMessage.listen((message) {
        print('Peer 1 received: "$message"');
        peer1Messages.add(message.toString());
      });

      channel2.onMessage.listen((message) {
        print('Peer 2 received: "$message"');
        peer2Messages.add(message.toString());
      });

      // Exchange messages
      print('\n--- Exchanging Messages ---');

      print('Peer 1 sending: "Hello from Peer 1!"');
      await channel1.sendString('Hello from Peer 1!');

      await Future.delayed(Duration(milliseconds: 100));

      print('Peer 2 sending: "Hello from Peer 2!"');
      await channel2.sendString('Hello from Peer 2!');

      // Wait for messages to be delivered
      await Future.delayed(Duration(milliseconds: 200));

      // Verify messages were received
      print('\n--- Verification ---');
      print(
          'Peer 1 received ${peer1Messages.length} message(s): $peer1Messages');
      print(
          'Peer 2 received ${peer2Messages.length} message(s): $peer2Messages');

      expect(peer2Messages, contains('Hello from Peer 1!'));
      expect(peer1Messages, contains('Hello from Peer 2!'));

      print('\n✓ Message exchange successful!');

      // Clean up
      print('\n--- Cleaning up ---');
      await transport1.close();
      await transport2.close();

      print('✓ Test complete!\n');
    }, timeout: Timeout(Duration(seconds: 15)));
  });
}
