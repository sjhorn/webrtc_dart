/// WebRTC Offer Example with WebSocket Signaling
///
/// This example creates a WebRTC peer connection that:
/// 1. Connects to a signaling server
/// 2. Creates an offer with a datachannel
/// 3. Sends the offer via signaling
/// 4. Receives the answer via signaling
/// 5. Exchanges messages on the datachannel
///
/// Usage:
///   1. Start signaling server: dart run examples/signaling/signaling_server.dart
///   2. Run this offer:         dart run examples/signaling/offer.dart
///   3. Run answer:             dart run examples/signaling/answer.dart
///
/// Or use with browser: open examples/signaling/answer.html
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

void main(List<String> args) async {
  final signalingUrl = args.isNotEmpty ? args[0] : 'ws://localhost:8888';

  print('WebRTC Offer Example');
  print('====================\n');

  // Connect to signaling server
  print('Connecting to signaling server: $signalingUrl');
  final socket = await WebSocket.connect(signalingUrl);
  print('Connected to signaling server\n');

  // Create peer connection
  final pc = RtcPeerConnection();
  print('Created PeerConnection');

  // Track connection state
  final connected = Completer<void>();

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection state: $state');
    if (state == PeerConnectionState.connected && !connected.isCompleted) {
      connected.complete();
    }
  });

  pc.onIceConnectionStateChange.listen((state) {
    print('[PC] ICE state: $state');
  });

  // Collect ICE candidates to send with offer
  final candidates = <Candidate>[];
  pc.onIceCandidate.listen((candidate) {
    print('[PC] Generated ICE candidate: ${candidate.type} at ${candidate.host}:${candidate.port}');
    candidates.add(candidate);
  });

  // Create datachannel
  print('Creating datachannel "chat"');
  final dc = pc.createDataChannel('chat');
  var messageCount = 0;

  dc.onStateChange.listen((state) {
    print('[DC] State: $state');
    if (state == DataChannelState.open) {
      print('[DC] Channel open! Sending messages...');
      // Send a message every second
      Timer.periodic(Duration(seconds: 1), (timer) {
        if (dc.state != DataChannelState.open) {
          timer.cancel();
          return;
        }
        dc.sendString('ping ${++messageCount}');
        print('[DC] Sent: ping $messageCount');
      });
    }
  });

  dc.onMessage.listen((message) {
    final text = message is String ? message : 'binary(${message.length})';
    print('[DC] Received: $text');
  });

  // Create offer
  print('\nCreating offer...');
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  print('Local description set');

  // Wait a bit for ICE gathering
  await Future.delayed(Duration(milliseconds: 500));

  // Send offer via signaling
  final offerMessage = jsonEncode({
    'type': 'offer',
    'sdp': offer.sdp,
    'candidates':
        candidates.map((c) => {'candidate': c.toSdp(), 'sdpMid': '0'}).toList(),
  });
  socket.add(offerMessage);
  print('Sent offer to signaling server (${candidates.length} candidates)');

  // Wait for answer from signaling
  print('\nWaiting for answer...');

  socket.listen((data) async {
    final message = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
    final type = message['type'];

    if (type == 'answer') {
      print('Received answer');
      final answer = SessionDescription(type: 'answer', sdp: message['sdp']);
      await pc.setRemoteDescription(answer);
      print('Remote description set');

      // Add remote ICE candidates
      if (message['candidates'] != null) {
        for (final candidateData in message['candidates']) {
          final candidate = Candidate.fromSdp(candidateData['candidate']);
          await pc.addIceCandidate(candidate);
          print('Added remote ICE candidate');
        }
      }
    }
  });

  // Wait for connection
  print('\nWaiting for connection...');
  try {
    await connected.future.timeout(Duration(seconds: 30));
    print('\nConnection established!');
    print('Messages will be exchanged every second.');
    print('Press Ctrl+C to exit.\n');

    // Keep running
    await Future.delayed(Duration(hours: 1));
  } catch (e) {
    print('\nConnection timeout or error: $e');
  }

  // Cleanup
  await pc.close();
  await socket.close();
}
