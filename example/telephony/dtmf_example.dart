/// DTMF (Dual-Tone Multi-Frequency) Example
///
/// Demonstrates RTCDTMFSender with a complete peer-to-peer connection.
/// Creates two peer connections (caller and callee) that exchange audio
/// and DTMF tones.
///
/// Usage:
///   dart run example/telephony/dtmf_example.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('DTMF (Dual-Tone Multi-Frequency) Example');
  print('=' * 42 + '\n');

  // Create two peer connections to simulate caller and callee
  final caller = RTCPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  final callee = RTCPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  print('[Setup] Created caller and callee peer connections\n');

  // Exchange ICE candidates between peers
  caller.onIceCandidate.listen((candidate) {
    callee.addIceCandidate(candidate);
  });

  callee.onIceCandidate.listen((candidate) {
    caller.addIceCandidate(candidate);
  });

  // Track connection state
  final callerConnected = Completer<void>();
  caller.onConnectionStateChange.listen((state) {
    print('[Caller] Connection state: $state');
    if (state == PeerConnectionState.connected && !callerConnected.isCompleted) {
      callerConnected.complete();
    }
  });

  callee.onConnectionStateChange.listen((state) {
    print('[Callee] Connection state: $state');
  });

  // Callee receives track from caller
  callee.onTrack.listen((transceiver) {
    print('[Callee] Received track: ${transceiver.receiver.track.kind}');
  });

  // Create audio track for caller (this will have DTMF capability)
  final audioTrack = AudioStreamTrack(
    id: 'caller-audio',
    label: 'Caller Audio',
  );

  // Add audio track to caller - this creates an RTCRtpSender with DTMF
  final sender = caller.addTrack(audioTrack);
  print('[Caller] Added audio track');
  print('[Caller] DTMF available: ${sender.dtmf != null}');

  // Create offer
  print('\n[Signaling] Creating offer...');
  final offer = await caller.createOffer();
  await caller.setLocalDescription(offer);

  // Give to callee as remote description
  await callee.setRemoteDescription(offer);

  // Create answer
  print('[Signaling] Creating answer...');
  final answer = await callee.createAnswer();
  await callee.setLocalDescription(answer);

  // Give answer back to caller
  await caller.setRemoteDescription(answer);

  print('[Signaling] Offer/answer exchange complete');

  // Wait for connection to establish
  print('\n[Connection] Waiting for ICE connection...');
  await callerConnected.future.timeout(
    Duration(seconds: 10),
    onTimeout: () {
      print('[Connection] Timeout waiting for connection');
    },
  );

  print('\n${'=' * 42}');
  print('DTMF Demonstration');
  print('${'=' * 42}\n');

  // Get the DTMF sender
  final dtmf = sender.dtmf;
  if (dtmf == null) {
    print('ERROR: DTMF sender not available');
    await cleanup(caller, callee);
    return;
  }

  print('[DTMF] Sender available');
  print('[DTMF] canInsertDTMF: ${dtmf.canInsertDTMF}');

  // Set up tone change listener
  final sentTones = <String>[];
  dtmf.ontonechange = (event) {
    if (event.tone.isEmpty) {
      print('[DTMF] All tones completed');
    } else {
      print('[DTMF] Sending tone: "${event.tone}"');
      sentTones.add(event.tone);
    }
  };

  // Send DTMF tones - simulating dialing a phone number
  final tones = '123*#';
  print('\n[DTMF] Inserting tones: "$tones"');
  print('[DTMF] Duration: 100ms, Gap: 70ms');

  dtmf.insertDTMF(tones, duration: 100, interToneGap: 70);

  print('[DTMF] Tone buffer: "${dtmf.toneBuffer}"');

  // Wait for all tones to complete
  final waitTime = tones.length * 170 + 500;
  print('[DTMF] Waiting ${waitTime}ms for tones to complete...\n');
  await Future.delayed(Duration(milliseconds: waitTime));

  // Results
  print('=' * 42);
  print('Results');
  print('=' * 42);
  print('Requested tones: "$tones"');
  print('Sent tones: "${sentTones.join()}"');
  print('Success: ${sentTones.join() == tones.toUpperCase()}');

  // Demonstrate extended DTMF (A-D)
  print('\n[DTMF] Sending extended tones: "ABCD"');
  sentTones.clear();
  dtmf.insertDTMF('ABCD', duration: 50, interToneGap: 50);
  await Future.delayed(Duration(milliseconds: 500));
  print('[DTMF] Extended tones sent: "${sentTones.join()}"');

  // Clean up
  print('\n[Cleanup] Closing connections...');
  await cleanup(caller, callee);
  print('[Cleanup] Done');
}

Future<void> cleanup(RTCPeerConnection caller, RTCPeerConnection callee) async {
  await caller.close();
  await callee.close();
}
