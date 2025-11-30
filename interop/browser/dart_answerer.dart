/// Dart Answerer for Chrome Browser Interop Testing
///
/// Usage:
/// 1. Open index.html in Chrome
/// 2. Click "Create Offer" in the browser
/// 3. Run this script: dart run interop/browser/dart_answerer.dart
/// 4. Paste the offer JSON when prompted
/// 5. Copy the answer JSON and paste it in the browser
/// 6. Messages should flow!

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('=== Dart WebRTC Answerer for Browser Interop ===\n');

  // Create peer connection
  final pc = RtcPeerConnection();
  print('[Dart] PeerConnection created');

  // Wait for initialization
  await Future.delayed(Duration(milliseconds: 500));

  // Track connection state
  pc.onConnectionStateChange.listen((state) {
    print('[Dart] Connection state: $state');
  });

  pc.onIceConnectionStateChange.listen((state) {
    print('[Dart] ICE connection state: $state');
  });

  // Track ICE candidates
  final localCandidates = <Candidate>[];
  pc.onIceCandidate.listen((candidate) {
    print('[Dart] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
    localCandidates.add(candidate);
  });

  // Handle incoming data channels
  pc.onDataChannel.listen((channel) {
    print('[Dart] Incoming DataChannel: ${channel.label}');

    channel.onStateChange.listen((state) {
      print('[Dart] DataChannel state: $state');

      if (state == DataChannelState.open) {
        print('[Dart] DataChannel OPEN! Sending greeting...');
        channel.sendString('Hello from Dart!');

        // Send periodic messages
        var count = 0;
        Timer.periodic(Duration(seconds: 3), (timer) {
          if (channel.state != DataChannelState.open) {
            timer.cancel();
            return;
          }
          count++;
          final msg = 'Dart message #$count';
          print('[Dart] Sending: $msg');
          channel.sendString(msg);

          if (count >= 5) {
            timer.cancel();
          }
        });
      }
    });

    channel.onMessage.listen((message) {
      print('[Dart] Received: $message');
    });
  });

  // Read offer from stdin
  print('\n--- Paste the offer JSON from Chrome (then press Enter twice): ---\n');

  final lines = <String>[];
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty && lines.isNotEmpty) {
      break; // Empty line signals end of input
    }
    lines.add(line);
  }

  final offerJson = lines.join('\n');

  try {
    final offerData = jsonDecode(offerJson) as Map<String, dynamic>;
    final offer = SessionDescription(
      type: offerData['type'] as String,
      sdp: offerData['sdp'] as String,
    );

    print('\n[Dart] Received offer:');
    print('[Dart] SDP type: ${offer.type}');
    print('[Dart] SDP preview: ${offer.sdp.substring(0, 200.clamp(0, offer.sdp.length))}...');

    // Set remote description
    await pc.setRemoteDescription(offer);
    print('[Dart] Remote description set');

    // Create answer
    print('[Dart] Creating answer...');
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    print('[Dart] Local description set');

    // Wait for ICE gathering
    await Future.delayed(Duration(seconds: 2));

    // Output the answer
    final answerJson = jsonEncode({
      'type': answer.type,
      'sdp': answer.sdp,
    });

    print('\n--- Copy this answer JSON to Chrome: ---\n');
    print(answerJson);
    print('\n--- End of answer JSON ---\n');

    // Also output ICE candidates for trickle ICE (if needed)
    if (localCandidates.isNotEmpty) {
      print('[Dart] Local ICE candidates (${localCandidates.length}):');
      for (final c in localCandidates) {
        print('  - ${c.type} ${c.host}:${c.port}');
      }
    }

    print('\n[Dart] Waiting for connection and messages...');
    print('[Dart] Press Ctrl+C to exit\n');

    // Keep running
    await Future.delayed(Duration(minutes: 5));

  } catch (e, st) {
    print('[Dart] Error: $e');
    print(st);
    exit(1);
  }

  await pc.close();
  print('[Dart] Closed');
}
