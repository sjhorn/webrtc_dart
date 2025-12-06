/// ICE TURN Example
///
/// This example demonstrates TURN relay functionality.
/// TURN (Traversal Using Relays around NAT) is used when direct
/// peer-to-peer connectivity is not possible due to restrictive NATs.
///
/// Note: This example requires a TURN server. You can use public
/// TURN servers or set up your own (coturn is a popular choice).
///
/// Usage: dart run examples/ice_turn.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('ICE TURN Example');
  print('=' * 50);
  print('');

  // TURN server configuration
  // Replace with your actual TURN server credentials
  const turnUrl = 'turn:turn.example.com:3478';
  const turnUsername = 'user';
  const turnCredential = 'password';

  print('TURN Configuration:');
  print('  URL: $turnUrl');
  print('  Username: $turnUsername');
  print('  Policy: relay-only');
  print('');

  // Create peer connections with TURN configuration
  // Using relay-only policy to force TURN usage
  final config = RtcConfiguration(
    iceServers: [
      IceServer(
        urls: [turnUrl],
        username: turnUsername,
        credential: turnCredential,
      ),
    ],
    iceTransportPolicy: IceTransportPolicy.relay,
  );

  final pc1 = RtcPeerConnection(config);
  final pc2 = RtcPeerConnection(config);

  // Track candidates
  final candidatesFromPc1 = <Candidate>[];
  final candidatesFromPc2 = <Candidate>[];

  // Track connection ready
  final connected = Completer<void>();
  var pc1Connected = false;
  var pc2Connected = false;

  // Monitor connection states
  pc1.onConnectionStateChange.listen((state) {
    print('[PC1] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      pc1Connected = true;
      if (pc2Connected && !connected.isCompleted) {
        connected.complete();
      }
    }
  });

  pc2.onConnectionStateChange.listen((state) {
    print('[PC2] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      pc2Connected = true;
      if (pc1Connected && !connected.isCompleted) {
        connected.complete();
      }
    }
  });

  // Monitor ICE states
  pc1.onIceConnectionStateChange.listen((state) {
    print('[PC1] ICE state: $state');
  });

  pc2.onIceConnectionStateChange.listen((state) {
    print('[PC2] ICE state: $state');
  });

  // Set up ICE candidate exchange with logging
  pc1.onIceCandidate.listen((candidate) {
    candidatesFromPc1.add(candidate);
    print(
        '[PC1] Candidate: ${candidate.type} (${candidate.host}:${candidate.port})');
    pc2.addIceCandidate(candidate);
  });

  pc2.onIceCandidate.listen((candidate) {
    candidatesFromPc2.add(candidate);
    print(
        '[PC2] Candidate: ${candidate.type} (${candidate.host}:${candidate.port})');
    pc1.addIceCandidate(candidate);
  });

  // Create a data channel for testing
  late DataChannel dc1;
  late DataChannel dc2;
  final dcReady = Completer<void>();

  pc2.onDataChannel.listen((channel) {
    dc2 = channel;
    if (channel.state == DataChannelState.open) {
      if (!dcReady.isCompleted) dcReady.complete();
    } else {
      channel.onStateChange.listen((state) {
        if (state == DataChannelState.open && !dcReady.isCompleted) {
          dcReady.complete();
        }
      });
    }
  });

  dc1 = pc1.createDataChannel('turn-test') as DataChannel;
  dc1.onStateChange.listen((state) {
    print('[DC] State: $state');
  });

  // Perform offer/answer exchange
  print('');
  print('Performing offer/answer exchange...');
  final offer = await pc1.createOffer();
  await pc1.setLocalDescription(offer);
  await pc2.setRemoteDescription(offer);

  final answer = await pc2.createAnswer();
  await pc2.setLocalDescription(answer);
  await pc1.setRemoteDescription(answer);

  // Wait for connection (may fail if TURN server not available)
  print('');
  print('Waiting for TURN relay connection...');
  print('(This will timeout if TURN server is not configured)');
  try {
    await connected.future.timeout(Duration(seconds: 15));
    print('Connection established via TURN relay!');

    // Wait for data channel
    await dcReady.future.timeout(Duration(seconds: 5));

    // Test data channel through TURN
    print('');
    print('Testing data channel through TURN relay...');
    final responseCompleter = Completer<void>();
    dc2.onMessage.listen((data) {
      final msg = String.fromCharCodes(data);
      print('[DC] Received: $msg');
      dc2.sendString('pong via TURN');
    });

    dc1.onMessage.listen((data) {
      final msg = String.fromCharCodes(data);
      print('[DC] Response: $msg');
      if (!responseCompleter.isCompleted) responseCompleter.complete();
    });

    dc1.sendString('ping via TURN');
    await responseCompleter.future.timeout(Duration(seconds: 5));
    print('Data channel working through TURN relay!');
  } catch (e) {
    print('Connection failed: $e');
    print('');
    print('This is expected if no TURN server is configured.');
  }

  // Show candidate summary
  print('');
  print('--- Candidate Summary ---');
  print('PC1 candidates: ${candidatesFromPc1.length}');
  for (final c in candidatesFromPc1) {
    print('  - ${c.type}: ${c.host}:${c.port}');
  }
  print('PC2 candidates: ${candidatesFromPc2.length}');
  for (final c in candidatesFromPc2) {
    print('  - ${c.type}: ${c.host}:${c.port}');
  }

  // Count relay candidates
  final relayCount = candidatesFromPc1.where((c) => c.type == 'relay').length +
      candidatesFromPc2.where((c) => c.type == 'relay').length;

  print('');
  print('Relay candidates gathered: $relayCount');

  // Explain TURN
  print('');
  print('--- TURN Mechanism ---');
  print('TURN (RFC 5766) provides relay-based NAT traversal:');
  print('  1. Client allocates a relay address on TURN server');
  print('  2. All media flows through the relay server');
  print('  3. Works even with symmetric NATs');
  print('  4. Higher latency than direct connection');
  print('  5. Uses server bandwidth (usually paid service)');
  print('');
  print('ICE transport policy "relay" forces TURN-only:');
  print('  - No host candidates gathered');
  print('  - No STUN (srflx) candidates gathered');
  print('  - Only relay candidates used');

  // Cleanup
  print('');
  print('Closing connections...');
  await pc1.close();
  await pc2.close();
  print('Done.');
}
