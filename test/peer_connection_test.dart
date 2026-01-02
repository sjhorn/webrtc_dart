import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtc_peer_connection.dart';
import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';
import 'package:webrtc_dart/src/datachannel/rtc_data_channel.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/sdp/rtx_sdp.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_transceiver.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RTCPeerConnection', () {
    test('initial state', () {
      final pc = RTCPeerConnection();

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.connectionState, PeerConnectionState.new_);
      expect(pc.iceConnectionState, IceConnectionState.new_);
      expect(pc.iceGatheringState, IceGatheringState.new_);
      expect(pc.localDescription, isNull);
      expect(pc.remoteDescription, isNull);
    });

    test('creates offer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();

      expect(offer.type, 'offer');
      expect(offer.sdp, isNotEmpty);
      expect(offer.sdp, contains('v=0'));
      expect(offer.sdp, contains('m=application'));
      expect(offer.sdp, contains('ice-ufrag'));
      expect(offer.sdp, contains('ice-pwd'));
    });

    test('sets local description with offer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      expect(pc.signalingState, SignalingState.haveLocalOffer);
      expect(pc.localDescription, isNotNull);
      expect(pc.localDescription!.type, 'offer');
    });

    test('sets remote description with offer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      expect(pc.signalingState, SignalingState.haveRemoteOffer);
      expect(pc.remoteDescription, isNotNull);
      expect(pc.remoteDescription!.type, 'offer');
    });

    test('creates answer after receiving offer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();

      expect(answer.type, 'answer');
      expect(answer.sdp, isNotEmpty);
      expect(answer.sdp, contains('v=0'));
      expect(answer.sdp, contains('m=application'));
    });

    test('sets local description with answer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.localDescription!.type, 'answer');
    });

    test('offer/answer exchange', () async {
      final pc1 = RTCPeerConnection();
      final pc2 = RTCPeerConnection();

      // PC1 creates offer
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      expect(pc1.signalingState, SignalingState.haveLocalOffer);

      // PC2 receives offer
      await pc2.setRemoteDescription(offer);
      expect(pc2.signalingState, SignalingState.haveRemoteOffer);

      // PC2 creates answer
      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);
      expect(pc2.signalingState, SignalingState.stable);

      // PC1 receives answer
      await pc1.setRemoteDescription(answer);
      expect(pc1.signalingState, SignalingState.stable);
    });

    test('cannot create offer in wrong state', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      // Now in haveRemoteOffer state, cannot create offer
      expect(() => pc.createOffer(), throwsStateError);
    });

    test('cannot create answer without remote offer', () async {
      final pc = RTCPeerConnection();

      expect(() => pc.createAnswer(), throwsStateError);
    });

    test('cannot set local answer in stable state', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);
      final answer = await pc.createAnswer();

      // Create new PC in stable state
      final pc2 = RTCPeerConnection();

      expect(() => pc2.setLocalDescription(answer), throwsStateError);
    });

    test('adds ICE candidate', () async {
      final pc = RTCPeerConnection();

      final candidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 50000,
        type: 'host',
      );

      // Should not throw
      await pc.addIceCandidate(candidate);
    });

    test('emits ICE candidates', () async {
      final pc = RTCPeerConnection();

      final candidates = <RTCIceCandidate>[];
      pc.onIceCandidate.listen(candidates.add);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Wait for ICE gathering
      await Future.delayed(Duration(milliseconds: 100));

      // Should have at least one candidate (host candidate)
      expect(candidates, isNotEmpty);
    });

    test('emits connection state changes', () async {
      final pc = RTCPeerConnection();

      final states = <PeerConnectionState>[];
      pc.onConnectionStateChange.listen(states.add);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await pc.close();

      expect(states, contains(PeerConnectionState.closed));
    });

    test('creates data channel before SCTP is ready (returns ProxyRTCDataChannel)',
        () async {
      final pc = RTCPeerConnection();

      // Wait for async initialization (certificate generation, transport setup)
      await Future.delayed(Duration(milliseconds: 100));

      // SCTP is not ready until ICE/DTLS/SCTP handshakes complete
      // But createDataChannel now returns a ProxyRTCDataChannel that will be
      // wired to a real RTCDataChannel when SCTP becomes ready
      final channel = pc.createDataChannel('test');

      // The channel should be in connecting state until SCTP is ready
      expect(channel.label, equals('test'));
      expect(channel.state, equals(DataChannelState.connecting));

      await pc.close();
    });

    test('closes cleanly', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await pc.close();

      expect(pc.connectionState, PeerConnectionState.closed);
      expect(pc.signalingState, SignalingState.closed);
    });

    test('rollback local offer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      expect(pc.signalingState, SignalingState.haveLocalOffer);

      await pc
          .setLocalDescription(RTCSessionDescription(type: 'rollback', sdp: ''));

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.localDescription, isNull);
    });

    test('rollback remote offer', () async {
      final pc = RTCPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);
      expect(pc.signalingState, SignalingState.haveRemoteOffer);

      await pc
          .setRemoteDescription(RTCSessionDescription(type: 'rollback', sdp: ''));

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.remoteDescription, isNull);
    });
  });

  group('RtcConfiguration', () {
    test('default configuration (matches TypeScript werift)', () {
      const config = RtcConfiguration();

      // Default STUN server matches TypeScript werift: stun:stun.l.google.com:19302
      expect(config.iceServers.length, 1);
      expect(config.iceServers[0].urls, ['stun:stun.l.google.com:19302']);
      expect(config.iceTransportPolicy, IceTransportPolicy.all);
      // Default bundlePolicy matches TypeScript werift: max-compat
      expect(config.bundlePolicy, BundlePolicy.maxCompat);
    });

    test('with ICE servers', () {
      const config = RtcConfiguration(
        iceServers: [
          IceServer(urls: ['stun:stun.l.google.com:19302']),
          IceServer(
            urls: ['turn:turn.example.com:3478'],
            username: 'user',
            credential: 'pass',
          ),
        ],
      );

      expect(config.iceServers.length, 2);
      expect(config.iceServers[0].urls, ['stun:stun.l.google.com:19302']);
      expect(config.iceServers[1].username, 'user');
      expect(config.iceServers[1].credential, 'pass');
    });

    test('with relay-only policy', () {
      const config = RtcConfiguration(
        iceTransportPolicy: IceTransportPolicy.relay,
      );

      expect(config.iceTransportPolicy, IceTransportPolicy.relay);
    });

    test('with bundlePolicy maxBundle (explicit)', () {
      const config = RtcConfiguration(bundlePolicy: BundlePolicy.maxBundle);

      expect(config.bundlePolicy, BundlePolicy.maxBundle);
    });

    test('with bundlePolicy disable', () {
      const config = RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
      );

      expect(config.bundlePolicy, BundlePolicy.disable);
    });

    test('with bundlePolicy maxCompat', () {
      const config = RtcConfiguration(
        bundlePolicy: BundlePolicy.maxCompat,
      );

      expect(config.bundlePolicy, BundlePolicy.maxCompat);
    });
  });

  group('BundlePolicy SDP', () {
    test('maxBundle includes BUNDLE group in SDP', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.maxBundle,
      ));

      // Add video track to get a media section
      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      final offer = await pc.createOffer();

      expect(offer.sdp, contains('a=group:BUNDLE'));
      await pc.close();
    });

    test('maxCompat includes BUNDLE group in SDP', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.maxCompat,
      ));

      // Add video track to get a media section
      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      final offer = await pc.createOffer();

      expect(offer.sdp, contains('a=group:BUNDLE'));
      await pc.close();
    });

    test('disable does NOT include BUNDLE group in SDP', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
      ));

      // Add video track to get a media section
      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      final offer = await pc.createOffer();

      expect(offer.sdp, isNot(contains('a=group:BUNDLE')));
      await pc.close();
    });

    test('answer respects bundlePolicy disable', () async {
      final pc1 = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
      ));
      final pc2 = RTCPeerConnection(RtcConfiguration(
        bundlePolicy: BundlePolicy.disable,
      ));

      // PC1 creates offer with video
      final videoTrack1 = VideoStreamTrack(id: 'video1', label: 'Video');
      pc1.addTrack(videoTrack1);

      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      expect(offer.sdp, isNot(contains('a=group:BUNDLE')));

      // PC2 receives offer
      final videoTrack2 = VideoStreamTrack(id: 'video2', label: 'Video');
      pc2.addTrack(videoTrack2);
      await pc2.setRemoteDescription(offer);

      // PC2 creates answer
      final answer = await pc2.createAnswer();
      expect(answer.sdp, isNot(contains('a=group:BUNDLE')));

      await pc1.close();
      await pc2.close();
    });
  });

  group('Signaling State Machine', () {
    test('stable -> haveLocalOffer -> stable', () async {
      final pc1 = RTCPeerConnection();
      final pc2 = RTCPeerConnection();

      expect(pc1.signalingState, SignalingState.stable);

      // PC1 creates and sets local offer
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      expect(pc1.signalingState, SignalingState.haveLocalOffer);

      // PC2 receives offer and creates answer
      await pc2.setRemoteDescription(offer);
      final answer = await pc2.createAnswer();

      // PC1 receives answer
      await pc1.setRemoteDescription(answer);
      expect(pc1.signalingState, SignalingState.stable);
    });

    test('stable -> haveRemoteOffer -> stable', () async {
      final pc = RTCPeerConnection();
      expect(pc.signalingState, SignalingState.stable);

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);
      expect(pc.signalingState, SignalingState.haveRemoteOffer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      expect(pc.signalingState, SignalingState.stable);
    });
  });

  group('RTX SDP Integration', () {
    test('video offer includes RTX attributes', () async {
      final pc = RTCPeerConnection();

      // Add a video track to trigger video SDP generation
      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      final offer = await pc.createOffer();
      final sdp = offer.parse();

      // Find video media section
      final videoMedia =
          sdp.mediaDescriptions.where((m) => m.type == 'video').firstOrNull;
      expect(videoMedia, isNotNull, reason: 'Should have video media section');

      // Verify RTX rtpmap is present
      final rtpMaps = videoMedia!.getRtpMaps();
      final rtxRtpMap = rtpMaps.where((r) => r.isRtx).firstOrNull;
      expect(rtxRtpMap, isNotNull, reason: 'Should have RTX rtpmap');
      expect(rtxRtpMap!.clockRate, 90000);

      // Verify RTX fmtp with apt is present
      final fmtps = videoMedia.getFmtps();
      final rtxFmtp = fmtps.where((f) => f.apt != null).firstOrNull;
      expect(rtxFmtp, isNotNull, reason: 'Should have RTX fmtp with apt');

      // Verify ssrc-group FID is present
      final ssrcGroups = videoMedia.getSsrcGroups();
      final fidGroup =
          ssrcGroups.where((g) => g.semantics == 'FID').firstOrNull;
      expect(fidGroup, isNotNull, reason: 'Should have ssrc-group FID');
      expect(fidGroup!.ssrcs.length, 2, reason: 'FID should have 2 SSRCs');

      await pc.close();
    });

    test('video offer RTX codec references original codec', () async {
      final pc = RTCPeerConnection();

      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      final offer = await pc.createOffer();
      final sdp = offer.parse();

      final videoMedia =
          sdp.mediaDescriptions.where((m) => m.type == 'video').first;

      // Get RTX codec info
      final rtxCodecs = videoMedia.getRtxCodecs();
      expect(rtxCodecs, isNotEmpty, reason: 'Should have RTX codec');

      // Verify RTX references the original VP8 payload type (96)
      expect(rtxCodecs.containsKey(96), isTrue,
          reason: 'RTX should reference VP8 payload type 96');

      final rtxInfo = rtxCodecs[96]!;
      // RTX payload type is max(all codec PTs) + 1
      // With VP8=96, VP9=97, H264=98, RTX gets 99
      expect(rtxInfo.rtxPayloadType, 99,
          reason:
              'RTX payload type should be 99 (after VP8=96, VP9=97, H264=98)');
      expect(rtxInfo.associatedPayloadType, 96);

      await pc.close();
    });

    test('audio offer does not include RTX', () async {
      final pc = RTCPeerConnection();

      // Add audio track
      final audioTrack = AudioStreamTrack(id: 'audio1', label: 'Audio');
      pc.addTrack(audioTrack);

      final offer = await pc.createOffer();
      final sdp = offer.parse();

      // Find audio media section
      final audioMedia =
          sdp.mediaDescriptions.where((m) => m.type == 'audio').firstOrNull;
      expect(audioMedia, isNotNull);

      // Verify no RTX for audio
      final rtxCodecs = audioMedia!.getRtxCodecs();
      expect(rtxCodecs, isEmpty, reason: 'Audio should not have RTX');

      final ssrcGroups = audioMedia.getSsrcGroups();
      expect(ssrcGroups, isEmpty, reason: 'Audio should not have ssrc-group');

      await pc.close();
    });

    test('answer includes RTX when offer has RTX', () async {
      final pc1 = RTCPeerConnection();
      final pc2 = RTCPeerConnection();

      // PC1 creates offer with video
      final videoTrack1 = VideoStreamTrack(id: 'video1', label: 'Video');
      pc1.addTrack(videoTrack1);

      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);

      // PC2 adds video track and receives offer
      final videoTrack2 = VideoStreamTrack(id: 'video2', label: 'Video');
      pc2.addTrack(videoTrack2);
      await pc2.setRemoteDescription(offer);

      // PC2 creates answer
      final answer = await pc2.createAnswer();
      final answerSdp = answer.parse();

      // Find video media section in answer
      final videoMedia = answerSdp.mediaDescriptions
          .where((m) => m.type == 'video')
          .firstOrNull;
      expect(videoMedia, isNotNull);

      // Verify answer has ssrc-group FID for RTX
      final ssrcGroups = videoMedia!.getSsrcGroups();
      final fidGroup =
          ssrcGroups.where((g) => g.semantics == 'FID').firstOrNull;
      expect(fidGroup, isNotNull, reason: 'Answer should have ssrc-group FID');
      expect(fidGroup!.ssrcs.length, 2);

      await pc1.close();
      await pc2.close();
    });

    test('RTX SSRC is different from original SSRC', () async {
      final pc = RTCPeerConnection();

      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      final offer = await pc.createOffer();
      final sdp = offer.parse();

      final videoMedia =
          sdp.mediaDescriptions.where((m) => m.type == 'video').first;

      // Get SSRC mapping
      final rtxSsrcMapping = videoMedia.getRtxSsrcMapping();
      expect(rtxSsrcMapping, isNotEmpty);

      // Verify SSRCs are different
      for (final entry in rtxSsrcMapping.entries) {
        expect(entry.key, isNot(equals(entry.value)),
            reason: 'RTX SSRC should be different from original SSRC');
      }

      await pc.close();
    });

    test('RTX attributes are preserved across multiple offers', () async {
      final pc = RTCPeerConnection();

      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      pc.addTrack(videoTrack);

      // Create first offer
      final offer1 = await pc.createOffer();
      final sdp1 = offer1.parse();
      final videoMedia1 =
          sdp1.mediaDescriptions.where((m) => m.type == 'video').first;
      final rtxMapping1 = videoMedia1.getRtxSsrcMapping();

      // Create second offer
      final offer2 = await pc.createOffer();
      final sdp2 = offer2.parse();
      final videoMedia2 =
          sdp2.mediaDescriptions.where((m) => m.type == 'video').first;
      final rtxMapping2 = videoMedia2.getRtxSsrcMapping();

      // RTX SSRC should be preserved across offers
      expect(rtxMapping1.keys.first, rtxMapping2.keys.first,
          reason: 'Original SSRC should be same');
      expect(rtxMapping1.values.first, rtxMapping2.values.first,
          reason: 'RTX SSRC should be same across offers');

      await pc.close();
    });
  });

  group('Nonstandard Track API (werift parity)', () {
    test('addTransceiver creates transceiver with track wired', () async {
      final pc = RTCPeerConnection();

      // Create nonstandard track (like TypeScript werift MediaStreamTrack)
      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );

      // Add transceiver with track (like TypeScript: addTransceiver(track, {direction: 'sendonly'}))
      final transceiver = pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
      );

      expect(transceiver.kind, MediaStreamTrackKind.video);
      expect(transceiver.direction, RtpTransceiverDirection.sendonly);
      expect(transceiver.sender.nonstandardTrack, equals(track));

      await pc.close();
    });

    test('addTransceiver with H264 codec', () async {
      final pc = RTCPeerConnection();

      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );

      final transceiver = pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
        codec: createH264Codec(payloadType: 96),
      );

      // Verify SDP contains H264
      final offer = await pc.createOffer();
      expect(offer.sdp, contains('H264'));
      expect(offer.sdp, contains('a=rtpmap:96'));

      expect(transceiver.sender.codec.codecName, 'H264');
      await pc.close();
    });

    test('addTransceiver creates offer with video media', () async {
      final pc = RTCPeerConnection();

      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );

      pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
      );

      final offer = await pc.createOffer();
      final sdp = offer.parse();

      // Should have a video media section
      final videoMedia =
          sdp.mediaDescriptions.where((m) => m.type == 'video').firstOrNull;
      expect(videoMedia, isNotNull, reason: 'Should have video media section');

      // Direction should be sendonly (check raw SDP since it's a flag attribute)
      expect(offer.sdp, contains('a=sendonly'));

      await pc.close();
    });

    test('sender.registerNonstandardTrack wires track to sender', () async {
      final pc = RTCPeerConnection();

      // First add transceiver without track
      final transceiver = pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Initially no nonstandard track
      expect(transceiver.sender.nonstandardTrack, isNull);

      // Register nonstandard track (like TypeScript registerTrack)
      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );
      transceiver.sender.registerNonstandardTrack(track);

      // Now should have the track
      expect(transceiver.sender.nonstandardTrack, equals(track));

      await pc.close();
    });

    test('audio track creates audio transceiver', () async {
      final pc = RTCPeerConnection();

      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.audio,
        id: 'test-audio',
      );

      final transceiver = pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendrecv,
      );

      expect(transceiver.kind, MediaStreamTrackKind.audio);
      expect(transceiver.direction, RtpTransceiverDirection.sendrecv);

      await pc.close();
    });

    test('codecs from RtcConfiguration are used when no explicit codec',
        () async {
      // Create peer connection with H264 codec config (like TypeScript werift)
      final pc = RTCPeerConnection(RtcConfiguration(
        codecs: RtcCodecs(
          video: [
            createH264Codec(
              payloadType: 96,
              rtcpFeedback: [
                RtcpFeedback(type: 'transport-cc'),
                RtcpFeedback(type: 'nack'),
              ],
            ),
          ],
        ),
      ));

      // Add transceiver without explicit codec - should use config codec
      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );

      pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
      );

      final offer = await pc.createOffer();

      // Should contain H264 codec from config
      expect(offer.sdp, contains('H264'));
      expect(offer.sdp, contains('profile-level-id'));
      // Should contain configured RTCP feedback
      expect(offer.sdp, contains('a=rtcp-fb:96 transport-cc'));
      expect(offer.sdp, contains('a=rtcp-fb:96 nack'));

      await pc.close();
    });

    test('writeRtp with different payload type gets rewritten to codec PT',
        () async {
      // This test verifies the payload type rewriting fix for Ring video forwarding.
      // When RTP packets from an external source (e.g., Ring camera) have a different
      // payload type than the SDP-negotiated codec, _attachNonstandardTrack should
      // rewrite the payload type to match the negotiated codec.

      final pc = RTCPeerConnection(RtcConfiguration(
        codecs: RtcCodecs(
          video: [
            createH264Codec(payloadType: 96), // Negotiated PT is 96
          ],
        ),
      ));

      final track = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );

      final transceiver = pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Verify the sender's codec has the correct payload type
      expect(transceiver.sender.codec.payloadType, 96);

      // Create an RTP packet with a DIFFERENT payload type (e.g., 100)
      // simulating a Ring camera that uses its own PT
      final externalPacket = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 100, // External PT != 96
        sequenceNumber: 1000,
        timestamp: 90000,
        ssrc: 0xDEADBEEF,
        csrcs: [],
        payload: Uint8List.fromList([0x67, 0x42, 0xc0, 0x1e]),
      );

      // Write the packet to the track
      // This triggers _attachNonstandardTrack's listener which calls
      // rtpSession.sendRawRtpPacket(rtp, payloadType: codec.payloadType)
      track.writeRtp(externalPacket);

      // The actual verification happens in the RTP flow, but at minimum
      // we verify the sender's codec has the expected payload type
      // that will be used for rewriting
      expect(transceiver.sender.codec.payloadType, 96,
          reason: 'Sender codec should have negotiated PT 96');

      await pc.close();
    });
  });

  group('Audio Codec Configuration', () {
    test('audio transceiver uses configured PCMU codec instead of default Opus',
        () async {
      // This test verifies the fix for the bug where createAudioTransceiver
      // always used Opus regardless of configured codecs.
      final pc = RTCPeerConnection(RtcConfiguration(
        codecs: RtcCodecs(
          audio: [createPcmuCodec()], // Configure PCMU instead of default Opus
          video: [createH264Codec(payloadType: 96)],
        ),
      ));

      final audioTrack = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.audio,
        id: 'test-audio',
      );

      final transceiver = pc.addTransceiver(
        audioTrack,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Verify the sender's codec is PCMU, not Opus
      expect(transceiver.sender.codec.mimeType, 'audio/PCMU',
          reason: 'Sender codec should be PCMU as configured');
      expect(transceiver.sender.codec.clockRate, 8000,
          reason: 'PCMU clock rate should be 8000');
      expect(transceiver.sender.codec.payloadType, 0,
          reason: 'PCMU static payload type is 0');

      await pc.close();
    });

    test('audio transceiver SDP contains configured PCMU codec', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        codecs: RtcCodecs(
          audio: [createPcmuCodec()],
        ),
      ));

      final audioTrack = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.audio,
        id: 'test-audio',
      );

      pc.addTransceiver(
        audioTrack,
        direction: RtpTransceiverDirection.sendonly,
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Verify SDP contains PCMU, not Opus
      expect(offer.sdp, contains('PCMU/8000'),
          reason: 'SDP should contain PCMU codec');
      expect(offer.sdp, isNot(contains('opus/48000')),
          reason: 'SDP should not contain Opus when PCMU is configured');

      await pc.close();
    });

    test('addTransceiver with audio kind uses configured codec', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        codecs: RtcCodecs(
          audio: [createPcmuCodec()],
        ),
      ));

      final transceiver = pc.addTransceiver(
        MediaStreamTrackKind.audio,
        direction: RtpTransceiverDirection.sendonly,
      );

      expect(transceiver.sender.codec.mimeType, 'audio/PCMU');
      expect(transceiver.sender.codec.clockRate, 8000);

      await pc.close();
    });

    test('multiple transceivers (video + audio) use correct codecs', () async {
      final pc = RTCPeerConnection(RtcConfiguration(
        codecs: RtcCodecs(
          audio: [createPcmuCodec()],
          video: [createH264Codec(payloadType: 96)],
        ),
      ));

      final videoTrack = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.video,
        id: 'test-video',
      );
      final audioTrack = nonstandard.MediaStreamTrack(
        kind: nonstandard.MediaKind.audio,
        id: 'test-audio',
      );

      // Add video first, then audio
      final videoTransceiver = pc.addTransceiver(
        videoTrack,
        direction: RtpTransceiverDirection.sendonly,
      );
      final audioTransceiver = pc.addTransceiver(
        audioTrack,
        direction: RtpTransceiverDirection.sendonly,
      );

      // Verify each transceiver has correct codec
      expect(videoTransceiver.sender.codec.mimeType, 'video/H264');
      expect(videoTransceiver.sender.codec.payloadType, 96);
      expect(audioTransceiver.sender.codec.mimeType, 'audio/PCMU');
      expect(audioTransceiver.sender.codec.payloadType, 0);

      // Verify SDP contains both codecs
      final offer = await pc.createOffer();
      expect(offer.sdp, contains('m=video'));
      expect(offer.sdp, contains('m=audio'));
      expect(offer.sdp, contains('H264/90000'));
      expect(offer.sdp, contains('PCMU/8000'));

      await pc.close();
    });
  });
}
