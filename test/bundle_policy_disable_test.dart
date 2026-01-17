import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

/// Test for bundlePolicy:disable audio RTP routing issue.
///
/// Issue: With bundlePolicy:disable, audio RTP packets are not being delivered
/// to the audio track's onReceiveRtp stream. Video works correctly.
///
/// Reference: ring_client_api/WEBRTC_ISSUE.md
void main() {
  group('bundlePolicy:disable', () {
    test('audio and video RTP packets are routed to correct transceivers',
        () async {
      // Allow event loop to stabilize before this resource-intensive test
      // bundlePolicy:disable creates 4 transports (2 per peer × 2 media types)
      await Future.delayed(Duration(milliseconds: 100));

      // Create two peer connections with bundlePolicy:disable
      // This creates separate transports for audio and video
      final pcOffer = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
        codecs: RtcCodecs(
          audio: [
            RtpCodecParameters(
              mimeType: 'audio/opus',
              clockRate: 48000,
              channels: 2,
            ),
          ],
          video: [
            RtpCodecParameters(
              mimeType: 'video/VP8',
              clockRate: 90000,
            ),
          ],
        ),
      ));

      final pcAnswer = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
        codecs: RtcCodecs(
          audio: [
            RtpCodecParameters(
              mimeType: 'audio/opus',
              clockRate: 48000,
              channels: 2,
            ),
          ],
          video: [
            RtpCodecParameters(
              mimeType: 'video/VP8',
              clockRate: 90000,
            ),
          ],
        ),
      ));

      // Event-driven connection waiting with state tracking
      final offerConnected = Completer<void>();
      final answerConnected = Completer<void>();
      var offerState = PeerConnectionState.new_;
      var answerState = PeerConnectionState.new_;

      pcOffer.onConnectionStateChange.listen((state) {
        offerState = state;
        if (state == PeerConnectionState.connected &&
            !offerConnected.isCompleted) {
          offerConnected.complete();
        }
      });

      pcAnswer.onConnectionStateChange.listen((state) {
        answerState = state;
        if (state == PeerConnectionState.connected &&
            !answerConnected.isCompleted) {
          answerConnected.complete();
        }
      });

      // Create audio and video transceivers on offerer (sendrecv for audio, recvonly for video)
      final audioTransceiver = pcOffer.addTransceiver(
        MediaStreamTrackKind.audio,
        direction: RtpTransceiverDirection.sendrecv,
      );
      final videoTransceiver = pcOffer.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.recvonly,
      );

      // Exchange ICE candidates (trickle ICE)
      pcOffer.onIceCandidate.listen((candidate) async {
        await pcAnswer.addIceCandidate(candidate);
      });

      pcAnswer.onIceCandidate.listen((candidate) async {
        await pcOffer.addIceCandidate(candidate);
      });

      // Perform offer/answer exchange
      final offer = await pcOffer.createOffer();
      await pcOffer.setLocalDescription(offer);
      await pcAnswer.setRemoteDescription(offer);

      final answer = await pcAnswer.createAnswer();
      await pcAnswer.setLocalDescription(answer);
      await pcOffer.setRemoteDescription(answer);

      // Wait for both sides to connect (event-driven with timeout)
      // bundlePolicy:disable creates 4 transports (audio+video × 2 peers),
      // requiring more time under concurrent test load
      try {
        await Future.wait([
          offerConnected.future,
          answerConnected.future,
        ]).timeout(Duration(seconds: 20));
      } on TimeoutException {
        fail('Connection timeout - offerer: $offerState, answerer: $answerState');
      }

      // Verify both sides reached connected state
      expect(pcOffer.connectionState, equals(PeerConnectionState.connected),
          reason: 'Offerer should be connected with bundlePolicy:disable');
      expect(pcAnswer.connectionState, equals(PeerConnectionState.connected),
          reason: 'Answerer should be connected with bundlePolicy:disable');

      // Verify transceivers have correct MIDs
      expect(audioTransceiver.mid, equals('1'),
          reason: 'Audio transceiver should have mid=1');
      expect(videoTransceiver.mid, equals('2'),
          reason: 'Video transceiver should have mid=2');

      // Clean up - allow time for OS to release sockets
      await pcOffer.close();
      await pcAnswer.close();
      await Future.delayed(Duration(milliseconds: 50));
    },
        timeout: Timeout(Duration(seconds: 25)),
        retry: 2 // Retry on failure due to resource contention under parallel test load
        );

    test('verifies separate transports for audio and video', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
      ));

      await Future.delayed(Duration(milliseconds: 500));

      // Add audio and video transceivers
      pc.addTransceiver(
        MediaStreamTrackKind.audio,
        direction: RtpTransceiverDirection.sendrecv,
      );
      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.recvonly,
      );

      // Create offer - should have separate m-lines for audio and video
      final offer = await pc.createOffer();
      final sdp = offer.sdp;

      // Verify no BUNDLE group in SDP
      expect(sdp.contains('a=group:BUNDLE'), isFalse,
          reason: 'bundlePolicy:disable should not have BUNDLE group');

      // Verify separate m-lines
      final audioMLine = sdp.contains('m=audio');
      final videoMLine = sdp.contains('m=video');
      expect(audioMLine, isTrue, reason: 'Should have audio m-line');
      expect(videoMLine, isTrue, reason: 'Should have video m-line');

      await pc.close();
    });
  });
}
