/// Local DataChannel Example
///
/// This example creates two peer connections locally and establishes
/// a datachannel between them to exchange messages.
///
/// Usage: dart run examples/datachannel_local.dart
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Starting local datachannel example...\n');

  // Create two peer connections
  final pcOffer = RtcPeerConnection();
  final pcAnswer = RtcPeerConnection();

  // Wait for transport initialization (certificate generation, etc.)
  print('Waiting for transport initialization...');
  await Future.delayed(Duration(milliseconds: 500));
  print('Transport initialized\n');

  // Track received messages
  final offerMessages = <String>[];
  final answerMessages = <String>[];

  // Set up completers for state tracking
  final iceCompleted = Completer<void>();
  var offerIceComplete = false;
  var answerIceComplete = false;

  final transportConnected = Completer<void>();
  var offerTransportReady = false;
  var answerTransportReady = false;

  // Set up connection state monitoring
  pcOffer.onConnectionStateChange.listen((state) {
    print('[Offer] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      print('[Offer] Transport connected');
      offerTransportReady = true;
      if (answerTransportReady && !transportConnected.isCompleted) {
        transportConnected.complete();
      }
    }
  });

  pcAnswer.onConnectionStateChange.listen((state) {
    print('[Answer] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      print('[Answer] Transport connected');
      answerTransportReady = true;
      if (offerTransportReady && !transportConnected.isCompleted) {
        transportConnected.complete();
      }
    }
  });

  // Set up ICE state change monitoring
  pcOffer.onIceConnectionStateChange.listen((state) {
    print('[Offer] ICE state: $state');
    if (state == IceConnectionState.completed ||
        state == IceConnectionState.connected) {
      offerIceComplete = true;
      if (answerIceComplete && !iceCompleted.isCompleted) {
        iceCompleted.complete();
      }
    }
  });

  pcAnswer.onIceConnectionStateChange.listen((state) {
    print('[Answer] ICE state: $state');
    if (state == IceConnectionState.completed ||
        state == IceConnectionState.connected) {
      answerIceComplete = true;
      if (offerIceComplete && !iceCompleted.isCompleted) {
        iceCompleted.complete();
      }
    }
  });

  // Set up ICE candidate exchange
  pcOffer.onIceCandidate.listen((candidate) async {
    print(
        '[Offer] Generated ICE candidate: ${candidate.type} at ${candidate.host}:${candidate.port}');
    print('[Offer] Adding candidate to Answer');
    await pcAnswer.addIceCandidate(candidate);
    print('[Offer] Candidate added');
  });

  pcAnswer.onIceCandidate.listen((candidate) async {
    print(
        '[Answer] Generated ICE candidate: ${candidate.type} at ${candidate.host}:${candidate.port}');
    print('[Answer] Adding candidate to Offer');
    await pcOffer.addIceCandidate(candidate);
    print('[Answer] Candidate added');
  });

  // Handle incoming datachannel on answering side
  pcAnswer.onDataChannel.listen((channel) {
    print(
        '[Answer DC] Received datachannel: ${channel.label}, state=${channel.state}');

    channel.onMessage.listen((message) {
      final text = message is String
          ? message
          : 'binary(${(message as Uint8List).length})';
      print('[Answer DC] Received: $text');
      answerMessages.add(text);
    });

    channel.onStateChange.listen((state) {
      print('[Answer DC] State changed: $state');
      if (state == DataChannelState.open) {
        print('[Answer DC] Sending "hi"');
        channel.sendString('hi');
      }
    });

    // If channel is already open, send message immediately
    if (channel.state == DataChannelState.open) {
      print('[Answer DC] Channel already open, sending "hi"');
      channel.sendString('hi');
    }
  });

  print('\nPerforming offer/answer exchange...');

  // Create and exchange offer
  print('[Offer] Creating offer...');
  final offer = await pcOffer.createOffer();
  print('[Offer] Offer SDP created (${offer.sdp.length} bytes)');
  print('[Offer] SDP:\n${offer.sdp}');

  await pcOffer.setLocalDescription(offer);
  print('[Offer] Set local description');

  await pcAnswer.setRemoteDescription(offer);
  print('[Answer] Set remote description');

  // Create and exchange answer
  print('[Answer] Creating answer...');
  final answer = await pcAnswer.createAnswer();
  print('[Answer] Answer SDP created (${answer.sdp.length} bytes)');

  await pcAnswer.setLocalDescription(answer);
  print('[Answer] Set local description');

  await pcOffer.setRemoteDescription(answer);
  print('[Offer] Set remote description');

  // Wait for ICE to complete
  print('\nWaiting for ICE connection...');
  try {
    await iceCompleted.future.timeout(Duration(seconds: 10));
    print('\n✓ ICE connection established!');
  } catch (e) {
    print('\n✗ ICE connection timeout');
  }

  // Wait for full transport connection (ICE + DTLS + SCTP)
  print('\nWaiting for DTLS and SCTP handshakes...');
  try {
    await transportConnected.future.timeout(Duration(seconds: 10));
    print('✓ Full transport stack connected!\n');
  } catch (e) {
    print('✗ Transport connection timeout\n');
  }

  // Now create datachannel (after transport is connected)
  print('Creating datachannel "chat"...');
  final dc = pcOffer.createDataChannel('chat');
  print('DataChannel created: ${dc.label}\n');

  dc.onStateChange.listen((state) {
    print('[Offer DC] State changed: $state');
    if (state == DataChannelState.open) {
      print('[Offer DC] Sending "hello"');
      dc.sendString('hello');
    }
  });

  dc.onMessage.listen((message) {
    final text = message is String
        ? message
        : 'binary(${(message as Uint8List).length})';
    print('[Offer DC] Received: $text');
    offerMessages.add(text);
  });

  // Wait for DataChannel to open and exchange messages
  print('Waiting for DataChannel messages...');
  await Future.delayed(Duration(seconds: 2));

  // Summary
  print('\n--- Summary ---');
  print('Offer signaling state: ${pcOffer.signalingState.name}');
  print('Answer signaling state: ${pcAnswer.signalingState.name}');
  print('Offer connection state: ${pcOffer.connectionState.name}');
  print('Answer connection state: ${pcAnswer.connectionState.name}');
  print('Offer ICE state: ${pcOffer.iceConnectionState.name}');
  print('Answer ICE state: ${pcAnswer.iceConnectionState.name}');
  print('');
  print('Messages received by offer: ${offerMessages.length}');
  if (offerMessages.isNotEmpty) {
    for (final msg in offerMessages) {
      print('  - "$msg"');
    }
  }
  print('Messages received by answer: ${answerMessages.length}');
  if (answerMessages.isNotEmpty) {
    for (final msg in answerMessages) {
      print('  - "$msg"');
    }
  }

  if (offerMessages.isNotEmpty && answerMessages.isNotEmpty) {
    print('\n✅ SUCCESS: DataChannel message exchange complete!');
  } else {
    print('\n⚠️  WARNING: No messages were exchanged');
  }

  // Cleanup
  print('\nClosing connections...');
  await pcOffer.close();
  await pcAnswer.close();

  print('Connections closed.');
}
