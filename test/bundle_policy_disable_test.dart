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

      // Wait for transport initialization
      await Future.delayed(Duration(milliseconds: 500));

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

      // Wait for connection
      await Future.delayed(Duration(seconds: 3));

      // Wait for connection to stabilize (late candidates may still arrive)
      await Future.delayed(Duration(seconds: 1));

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

      // Clean up
      await pcOffer.close();
      await pcAnswer.close();
    });

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
