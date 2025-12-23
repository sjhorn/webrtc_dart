/// Interop Client Example
///
/// Dart client that connects to a WebRTC server (browser or another Dart).
/// Answers offers and handles bidirectional communication.
///
/// Usage: dart run example/interop/client.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Interop Client Example');
  print('=' * 50);

  final serverUrl = 'ws://localhost:8888';
  print('Connecting to $serverUrl...');

  try {
    final socket = await WebSocket.connect(serverUrl);
    print('[WS] Connected to server');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    pc.onIceConnectionStateChange.listen((state) {
      print('[ICE] Connection: $state');
    });

    // Gather ICE candidates
    pc.onIceCandidate.listen((candidate) {
      socket.add(jsonEncode({
        'type': 'candidate',
        'candidate': candidate.toSdp(),
        'sdpMid': '0',
      }));
    });

    // Handle incoming tracks
    pc.onTrack.listen((transceiver) {
      print('[Track] Received ${transceiver.kind}');
    });

    // Handle DataChannels
    pc.onDataChannel.listen((dc) {
      print('[DC] Received channel: ${dc.label}');

      dc.onStateChange.listen((state) {
        if (state == DataChannelState.open) {
          print('[DC] ${dc.label} opened');
          dc.sendString('Hello from Dart client!');
        }
      });

      dc.onMessage.listen((msg) {
        print('[DC] Message: $msg');
      });
    });

    // Handle signaling messages
    socket.listen((data) async {
      final msg = jsonDecode(data as String);

      if (msg['type'] == 'offer') {
        print('[SDP] Received offer');
        final offer = SessionDescription(type: 'offer', sdp: msg['sdp']);
        await pc.setRemoteDescription(offer);

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socket.add(jsonEncode({
          'type': 'answer',
          'sdp': answer.sdp,
        }));
        print('[SDP] Sent answer');
      } else if (msg['type'] == 'candidate' && msg['candidate'] != null) {
        final candidate = Candidate.fromSdp(msg['candidate']);
        await pc.addIceCandidate(candidate);
      }
    }, onDone: () {
      print('[WS] Server disconnected');
      pc.close();
    });

    // Keep running
    await Future.delayed(Duration(hours: 1));
  } catch (e) {
    print('[Error] $e');
    print('\nMake sure a WebSocket server is running on $serverUrl');
  }
}
