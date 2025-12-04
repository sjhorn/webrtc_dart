/// WebRTC Answer Example with WebSocket Signaling
///
/// This example creates a WebRTC peer connection that:
/// 1. Connects to a signaling server
/// 2. Waits for an offer via signaling
/// 3. Creates an answer
/// 4. Sends the answer via signaling
/// 5. Exchanges messages on the datachannel
///
/// Usage:
///   1. Start signaling server: dart run examples/signaling/signaling_server.dart
///   2. Run offer:              dart run examples/signaling/offer.dart
///   3. Run this answer:        dart run examples/signaling/answer.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

void main(List<String> args) async {
  final signalingUrl = args.isNotEmpty ? args[0] : 'ws://localhost:8888';

  print('WebRTC Answer Example');
  print('=====================\n');

  // Connect to signaling server
  print('Connecting to signaling server: $signalingUrl');
  final socket = await WebSocket.connect(signalingUrl);
  print('Connected to signaling server');
  print('Waiting for offer...\n');

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

  // Collect ICE candidates
  final candidates = <Candidate>[];
  pc.onIceCandidate.listen((candidate) {
    print('[PC] Generated ICE candidate: ${candidate.type} at ${candidate.host}:${candidate.port}');
    candidates.add(candidate);
  });

  // Handle incoming datachannel
  var messageCount = 0;
  pc.onDataChannel.listen((channel) {
    print('[DC] Received datachannel: ${channel.label}');

    channel.onStateChange.listen((state) {
      print('[DC] State: $state');
    });

    channel.onMessage.listen((message) {
      final text = message is String ? message : 'binary(${message.length})';
      print('[DC] Received: $text');

      // Reply to pings with pongs
      if (text.startsWith('ping')) {
        final reply = 'pong ${++messageCount}';
        channel.sendString(reply);
        print('[DC] Sent: $reply');
      }
    });
  });

  // Handle signaling messages
  socket.listen((data) async {
    final message = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
    final type = message['type'];

    if (type == 'offer') {
      print('Received offer');
      final offer = SessionDescription(type: 'offer', sdp: message['sdp']);
      await pc.setRemoteDescription(offer);
      print('Remote description set');

      // Add remote ICE candidates
      if (message['candidates'] != null) {
        for (final candidateData in message['candidates']) {
          final candidate = Candidate.fromSdp(candidateData['candidate']);
          await pc.addIceCandidate(candidate);
          print('Added remote ICE candidate');
        }
      }

      // Create answer
      print('\nCreating answer...');
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      print('Local description set');

      // Wait a bit for ICE gathering
      await Future.delayed(Duration(milliseconds: 500));

      // Send answer via signaling
      final answerMessage = jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
        'candidates':
            candidates.map((c) => {'candidate': c.toSdp(), 'sdpMid': '0'}).toList(),
      });
      socket.add(answerMessage);
      print('Sent answer to signaling server (${candidates.length} candidates)\n');
    }
  });

  // Wait for connection
  print('Waiting for connection...');
  try {
    await connected.future.timeout(Duration(seconds: 30));
    print('\nConnection established!');
    print('Responding to pings with pongs.');
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
