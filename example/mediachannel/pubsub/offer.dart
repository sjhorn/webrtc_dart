/// Pub/Sub Media Channel Example
///
/// Demonstrates a publish/subscribe pattern for video routing.
/// Publishers send video, subscribers receive. Server routes
/// video from publishers to subscribers.
///
/// Usage: dart run example/mediachannel/pubsub/offer.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

/// Simple pub/sub media router
class MediaRouter {
  final Map<String, MediaStreamTrack> _publishers = {};
  final Map<String, List<RtpTransceiver>> _subscribers = {};

  /// Register a publisher track
  void publish(String mediaId, MediaStreamTrack track) {
    print('[Router] Publisher registered: $mediaId');
    _publishers[mediaId] = track;

    // Forward to existing subscribers
    final subs = _subscribers[mediaId];
    if (subs != null) {
      for (final transceiver in subs) {
        transceiver.sender.replaceTrack(track);
        print('[Router] Forwarding to subscriber');
      }
    }
  }

  /// Subscribe to a media stream
  void subscribe(String mediaId, RtpTransceiver transceiver) {
    print('[Router] Subscriber registered for: $mediaId');
    _subscribers.putIfAbsent(mediaId, () => []).add(transceiver);

    // If publisher exists, start forwarding
    final track = _publishers[mediaId];
    if (track != null) {
      transceiver.sender.replaceTrack(track);
      print('[Router] Started forwarding to new subscriber');
    }
  }

  /// Unsubscribe from a media stream
  void unsubscribe(String mediaId, RtpTransceiver transceiver) {
    _subscribers[mediaId]?.remove(transceiver);
  }

  /// Unpublish a media stream
  void unpublish(String mediaId) {
    _publishers.remove(mediaId);
    print('[Router] Publisher removed: $mediaId');
  }
}

void main() async {
  print('Pub/Sub Media Channel Example');
  print('=' * 50);

  final router = MediaRouter();

  // Simulate a publisher peer
  final publisherPc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  // Simulate a subscriber peer
  final subscriberPc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  // Publisher: recvonly to receive video from browser
  final pubTransceiver = publisherPc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  // When publisher sends track, register with router
  publisherPc.onTrack.listen((t) {
    print('[Publisher] Received video track');
    final track = t.receiver.track;
    router.publish('room1-video', track);

    // Request keyframes periodically for subscribers
    Timer.periodic(Duration(seconds: 2), (_) {
      // Send PLI to publisher
    });
  });

  // Subscriber: sendonly to send video to browser
  final subTransceiver = subscriberPc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.sendonly,
  );

  // Subscribe to the published stream
  router.subscribe('room1-video', subTransceiver);

  // Create offers
  final pubOffer = await publisherPc.createOffer();
  await publisherPc.setLocalDescription(pubOffer);

  final subOffer = await subscriberPc.createOffer();
  await subscriberPc.setLocalDescription(subOffer);

  print('\n--- Publisher SDP ---');
  print('Direction: recvonly (receives video from browser)');
  print('Mid: ${pubTransceiver.mid}');

  print('\n--- Subscriber SDP ---');
  print('Direction: sendonly (sends video to browser)');
  print('Mid: ${subTransceiver.mid}');

  print('\n--- Pub/Sub Pattern ---');
  print('1. Publisher connects, creates recvonly transceiver');
  print('2. Browser sends video to publisher');
  print('3. Server registers track with router');
  print('4. Subscriber connects, creates sendonly transceiver');
  print('5. Router forwards publisher track to subscriber');
  print('6. Subscriber browser receives video');

  print('\n--- Use Cases ---');
  print('- Video conferencing (N publishers, N subscribers)');
  print('- Live streaming (1 publisher, N subscribers)');
  print('- Selective forwarding unit (SFU) architecture');

  await publisherPc.close();
  await subscriberPc.close();
  print('\nDone.');
}
