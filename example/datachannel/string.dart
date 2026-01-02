/// RTCDataChannel String Messages Example
///
/// This example demonstrates sending and receiving string messages
/// over a RTCDataChannel between two local peer connections.
///
/// Usage: dart run examples/datachannel_string.dart
library;

import 'dart:async';
import 'dart:convert';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('RTCDataChannel String Messages Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final pc1 = RTCPeerConnection();
  final pc2 = RTCPeerConnection();

  // Wait for transport initialization
  await Future.delayed(Duration(milliseconds: 500));

  // Track data channels (dynamic - can be RTCDataChannel or ProxyDataChannel)
  late dynamic dc1;
  late dynamic dc2;

  final dc1Ready = Completer<void>();
  final dc2Ready = Completer<void>();

  // Message tracking
  final pc1ReceivedMessages = <String>[];
  final pc2ReceivedMessages = <String>[];

  // Set up ICE candidate exchange
  pc1.onIceCandidate.listen((candidate) async {
    await pc2.addIceCandidate(candidate);
  });

  pc2.onIceCandidate.listen((candidate) async {
    await pc1.addIceCandidate(candidate);
  });

  // Handle incoming datachannel on pc2
  pc2.onDataChannel.listen((channel) {
    dc2 = channel;
    print(
        '[PC2] RTCDataChannel received: ${channel.label}, state: ${channel.state}, type: ${channel.runtimeType}');

    // Set up message handler
    print('[PC2] Setting up message listener...');
    dc2.onMessage.listen((data) {
      final message = data is String ? data : utf8.decode(data);
      pc2ReceivedMessages.add(message);
      print('[PC2] Received: "$message"');

      // Echo back with "pong" prefix
      final response = 'pong: $message';
      dc2.sendString(response);
      print('[PC2] Sent: "$response"');
    });

    if (channel.state == DataChannelState.open) {
      if (!dc2Ready.isCompleted) dc2Ready.complete();
    } else {
      channel.onStateChange.listen((state) {
        print('[PC2] RTCDataChannel state: $state');
        if (state == DataChannelState.open && !dc2Ready.isCompleted) {
          dc2Ready.complete();
        }
      });
    }
  });

  // Create datachannel on pc1 with protocol
  dc1 = pc1.createDataChannel('chat', protocol: 'text');
  print('[PC1] Created RTCDataChannel: ${dc1.label} (protocol: ${dc1.protocol})');

  dc1.onStateChange.listen((state) {
    print('[PC1] RTCDataChannel state: $state');
    if (state == DataChannelState.open && !dc1Ready.isCompleted) {
      dc1Ready.complete();
    }
  });

  // Set up message handler for pc1
  dc1.onMessage.listen((data) {
    final message = data is String ? data : utf8.decode(data);
    pc1ReceivedMessages.add(message);
    print('[PC1] Received: "$message"');
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

  // Wait for datachannels to be ready
  print('Waiting for RTCDataChannel connections...');
  await Future.wait([dc1Ready.future, dc2Ready.future])
      .timeout(Duration(seconds: 10));

  print('');
  print('DataChannels connected!');
  print('');

  // Send some string messages
  final messagesToSend = [
    'Hello, WebRTC!',
    'This is a test message',
    'Unicode works too: ',
    'Final message',
  ];

  print('--- Sending Messages ---');
  print(
      '[PC1] DC1 state before send: ${dc1.state}, isInitialized: ${(dc1 as dynamic).isInitialized}');
  for (final msg in messagesToSend) {
    print('[PC1] Sending: "$msg"');
    await dc1.sendString(msg);
    // Small delay to allow processing
    await Future.delayed(Duration(milliseconds: 100));
  }

  // Wait for all responses
  await Future.delayed(Duration(milliseconds: 500));

  // Summary
  print('');
  print('--- Summary ---');
  print('Messages sent by PC1: ${messagesToSend.length}');
  print('Messages received by PC1: ${pc1ReceivedMessages.length}');
  print('Messages received by PC2: ${pc2ReceivedMessages.length}');

  if (pc1ReceivedMessages.length == messagesToSend.length &&
      pc2ReceivedMessages.length == messagesToSend.length) {
    print('');
    print('SUCCESS: All string messages exchanged successfully!');
  } else {
    print('');
    print('WARNING: Message count mismatch');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await pc1.close();
  await pc2.close();
  print('Done.');
}
