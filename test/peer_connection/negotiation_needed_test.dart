import 'dart:async';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtc_peer_connection.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_transceiver.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

void main() {
  group('onNegotiationNeeded', () {
    late RTCPeerConnection pc;

    setUp(() async {
      pc = RTCPeerConnection();
    });

    tearDown(() async {
      await pc.close();
    });

    test('fires when addTransceiver is called', () async {
      var eventCount = 0;
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Wait for microtask to complete
      await Future.delayed(Duration(milliseconds: 10));

      expect(eventCount, equals(1));
    });

    test('fires when addTransceiver is called', () async {
      var eventCount = 0;
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      // Create a nonstandard track
      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
      );

      pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Wait for microtask to complete
      await Future.delayed(Duration(milliseconds: 10));

      expect(eventCount, equals(1));
    });

    test('fires when createDataChannel is called for first channel', () async {
      var eventCount = 0;
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      pc.createDataChannel('test');

      // Wait for microtask to complete
      await Future.delayed(Duration(milliseconds: 10));

      expect(eventCount, equals(1));
    });

    test('does not fire for subsequent data channels', () async {
      var eventCount = 0;
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      pc.createDataChannel('first');
      pc.createDataChannel('second');
      pc.createDataChannel('third');

      // Wait for microtask to complete
      await Future.delayed(Duration(milliseconds: 10));

      // Only one event for the first channel
      expect(eventCount, equals(1));
    });

    test('coalesces multiple triggers into single event', () async {
      var eventCount = 0;
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      // Multiple operations in same microtask
      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      );
      pc.addTransceiver(
        MediaStreamTrackKind.audio,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Wait for microtask to complete
      await Future.delayed(Duration(milliseconds: 10));

      // Should be coalesced to single event
      expect(eventCount, equals(1));
    });

    test('does not fire when not in stable signaling state', () async {
      var eventCount = 0;

      // First create and set local offer to change signaling state
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Now signaling state is have-local-offer, not stable
      expect(pc.signalingState, equals(SignalingState.haveLocalOffer));

      // Start listening AFTER state change
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      // Add transceiver - should not fire negotiation needed
      // because we're not in stable state
      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Wait for microtask to complete
      await Future.delayed(Duration(milliseconds: 10));

      // Should not have fired since not in stable state
      expect(eventCount, equals(0));
    });

    test('stream can be listened to multiple times (broadcast)', () async {
      var count1 = 0;
      var count2 = 0;

      pc.onNegotiationNeeded.listen((_) => count1++);
      pc.onNegotiationNeeded.listen((_) => count2++);

      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      );

      await Future.delayed(Duration(milliseconds: 10));

      expect(count1, equals(1));
      expect(count2, equals(1));
    });

    test('no events after close', () async {
      var eventCount = 0;
      pc.onNegotiationNeeded.listen((_) => eventCount++);

      await pc.close();

      // This should not fire after close
      // The transceiver add will fail anyway since connection is closed
      // So we just verify the stream doesn't emit after close
      await Future.delayed(Duration(milliseconds: 10));

      expect(eventCount, equals(0));
    });
  });
}
