/// Dart Offerer (webrtc_dart)
/// Creates offer, writes offer.json, waits for answer.json
/// Sends datachannel messages to TypeScript peer
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

const signalsDir = '/Users/shorn/dev/dart/webrtc_dart/interop/signals';
const offerFile = '$signalsDir/offer.json';
const answerFile = '$signalsDir/answer.json';
const dartCandidatesFile = '$signalsDir/candidates_dart.jsonl';
const jsCandidatesFile = '$signalsDir/candidates_js.jsonl';

void main() async {
  print('[Dart Offerer] Starting...');

  // Clean up old signal files
  final signalsDirObj = Directory(signalsDir);
  if (await signalsDirObj.exists()) {
    await signalsDirObj.delete(recursive: true);
  }
  await signalsDirObj.create(recursive: true);

  // Create peer connection
  final pc = RtcPeerConnection();
  print('[Dart Offerer] PeerConnection created');

  // Wait for initialization
  await Future.delayed(Duration(milliseconds: 500));

  // Track received messages
  var messagesReceived = 0;
  final receivedMessages = <String>[];

  // Handle connection state changes
  pc.onConnectionStateChange.listen((state) {
    print('[Dart Offerer] Connection state: $state');
  });

  // Handle ICE connection state changes
  pc.onIceConnectionStateChange.listen((state) {
    print('[Dart Offerer] ICE connection state: $state');
  });

  // Handle ICE candidates - write to file for exchange with JS peer
  pc.onIceCandidate.listen((candidate) async {
    print('[Dart Offerer] ICE candidate: ${candidate.type} at ${candidate.host}:${candidate.port}');

    // Write candidate to file (append mode, one JSON per line)
    // Format matches JavaScript RTCIceCandidate structure
    final candidateJson = jsonEncode({
      'candidate': 'candidate:${candidate.toSdp()}',
      'sdpMid': '0', // For data channel
      'sdpMLineIndex': 0,
      'usernameFragment': candidate.ufrag,
    });
    await File(dartCandidatesFile).writeAsString(
      '$candidateJson\n',
      mode: FileMode.append,
    );
  });

  // Create datachannel before offer (offerer must create it)
  print('[Dart Offerer] Creating DataChannel...');
  final channel = pc.createDataChannel('chat');
  print('[Dart Offerer] DataChannel created: ${channel.label}');

  // Setup channel handlers
  channel.onStateChange.listen((state) {
    print('[Dart Offerer] DataChannel state: $state');
    if (state == DataChannelState.open) {
      print('[Dart Offerer] DataChannel opened!');
      print('[Dart Offerer] Sending initial message');
      channel.sendString('Hello from Dart!');

      // Send periodic messages
      var count = 0;
      Timer.periodic(Duration(seconds: 2), (timer) {
        if (channel.state != DataChannelState.open) {
          timer.cancel();
          return;
        }

        count++;
        final message = 'Message #$count from Dart';
        print('[Dart Offerer] Sending: $message');
        channel.sendString(message);

        if (count >= 5) {
          timer.cancel();
          print('[Dart Offerer] Sent 5 messages, stopping');
        }
      });
    }
  });

  // Handle incoming messages
  channel.onMessage.listen((message) {
    messagesReceived++;
    final text = message is String ? message : 'binary';
    print('[Dart Offerer] Received message #$messagesReceived: $text');
    receivedMessages.add(text);
  });

  // If channel is already open, send message immediately
  if (channel.state == DataChannelState.open) {
    print('[Dart Offerer] Channel already open, sending initial message');
    channel.sendString('Hello from Dart!');
  }

  // Also handle any incoming datachannels from JS side
  pc.onDataChannel.listen((incomingChannel) {
    print('[Dart Offerer] Incoming DataChannel: ${incomingChannel.label}');
  });

  // Create and write offer
  print('[Dart Offerer] Creating offer...');
  final offer = await pc.createOffer();
  print('[Dart Offerer] Offer created');
  print('[Dart Offerer] Offer SDP:\n${offer.sdp}');

  await pc.setLocalDescription(offer);
  print('[Dart Offerer] Local description set');

  // Write offer to file
  final offerJson = jsonEncode({
    'type': offer.type,
    'sdp': offer.sdp,
  });
  await File(offerFile).writeAsString(offerJson);
  print('[Dart Offerer] Offer written to: $offerFile');
  print('[Dart Offerer] Waiting for answer...');

  // Wait for answer file
  final answerData = await waitForFile(answerFile);
  final answerJson = jsonDecode(answerData) as Map<String, dynamic>;
  final answer = SessionDescription(
    type: answerJson['type'] as String,
    sdp: answerJson['sdp'] as String,
  );

  print('[Dart Offerer] Received answer');
  print('[Dart Offerer] Answer SDP:\n${answer.sdp}');

  await pc.setRemoteDescription(answer);
  print('[Dart Offerer] Remote description set');
  print('[Dart Offerer] Connection should establish now...');

  // Start polling for JS candidates
  print('[Dart Offerer] Starting to poll for JS ICE candidates...');
  pollForCandidates(pc, jsCandidatesFile);

  // Wait for messages
  print('[Dart Offerer] Waiting for messages...');
  await Future.delayed(Duration(seconds: 30));

  print('\n[Dart Offerer] Test Results:');
  print('  Messages received: $messagesReceived');
  print('  Connection state: ${pc.connectionState}');
  print('  ICE state: ${pc.iceConnectionState}');

  if (messagesReceived > 0) {
    print('\n[SUCCESS] Dart ↔ TypeScript interop working!');
    print('Received messages:');
    for (final msg in receivedMessages) {
      print('  - $msg');
    }
  } else {
    print('\n[FAILURE] No messages received');
  }

  await pc.close();
  print('[Dart Offerer] Complete');
}

/// Wait for file to exist and return its contents
Future<String> waitForFile(String filePath) async {
  var attempts = 0;
  const maxAttempts = 600; // 60 seconds

  while (attempts < maxAttempts) {
    final file = File(filePath);
    if (await file.exists()) {
      // Wait a bit to ensure file is fully written
      await Future.delayed(Duration(milliseconds: 100));
      return await file.readAsString();
    }
    await Future.delayed(Duration(milliseconds: 100));
    attempts++;
  }

  throw TimeoutException('Timeout waiting for file: $filePath');
}

/// Poll for ICE candidates from a file and add them to the peer connection
void pollForCandidates(RtcPeerConnection pc, String candidatesFile) {
  var lastSize = 0;

  Timer.periodic(Duration(milliseconds: 100), (timer) async {
    final file = File(candidatesFile);

    if (!await file.exists()) {
      return;
    }

    final content = await file.readAsString();
    final currentSize = content.length;

    // Only process if file has grown
    if (currentSize > lastSize) {
      final lines = content.split('\n');

      // Process new lines
      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        try {
          final candidateData = jsonDecode(line) as Map<String, dynamic>;

          // Parse the SDP candidate string (remove 'candidate:' prefix)
          String candidateStr = candidateData['candidate'] as String;
          if (candidateStr.startsWith('candidate:')) {
            candidateStr = candidateStr.substring('candidate:'.length);
          }

          // Create Candidate object from SDP format
          final candidate = Candidate.fromSdp(candidateStr);

          await pc.addIceCandidate(candidate);
          print('[Dart Offerer] Added remote ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
        } catch (e) {
          // Ignore parse errors for incomplete lines
        }
      }

      lastSize = currentSize;
    }

    // Stop polling after connection is established
    if (pc.iceConnectionState == IceConnectionState.connected ||
        pc.iceConnectionState == IceConnectionState.completed) {
      timer.cancel();
      print('[Dart Offerer] Stopped polling for candidates (connection established)');
    }
  });
}
