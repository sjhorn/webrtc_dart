import 'package:test/test.dart';
import 'package:webrtc_dart/src/peer_connection.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/sdp/rtx_sdp.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';

void main() {
  group('RtcPeerConnection', () {
    test('initial state', () {
      final pc = RtcPeerConnection();

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.connectionState, PeerConnectionState.new_);
      expect(pc.iceConnectionState, IceConnectionState.new_);
      expect(pc.iceGatheringState, IceGatheringState.new_);
      expect(pc.localDescription, isNull);
      expect(pc.remoteDescription, isNull);
    });

    test('creates offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();

      expect(offer.type, 'offer');
      expect(offer.sdp, isNotEmpty);
      expect(offer.sdp, contains('v=0'));
      expect(offer.sdp, contains('m=application'));
      expect(offer.sdp, contains('ice-ufrag'));
      expect(offer.sdp, contains('ice-pwd'));
    });

    test('sets local description with offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      expect(pc.signalingState, SignalingState.haveLocalOffer);
      expect(pc.localDescription, isNotNull);
      expect(pc.localDescription!.type, 'offer');
    });

    test('sets remote description with offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      expect(pc.signalingState, SignalingState.haveRemoteOffer);
      expect(pc.remoteDescription, isNotNull);
      expect(pc.remoteDescription!.type, 'offer');
    });

    test('creates answer after receiving offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();

      expect(answer.type, 'answer');
      expect(answer.sdp, isNotEmpty);
      expect(answer.sdp, contains('v=0'));
      expect(answer.sdp, contains('m=application'));
    });

    test('sets local description with answer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.localDescription!.type, 'answer');
    });

    test('offer/answer exchange', () async {
      final pc1 = RtcPeerConnection();
      final pc2 = RtcPeerConnection();

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
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);

      // Now in haveRemoteOffer state, cannot create offer
      expect(() => pc.createOffer(), throwsStateError);
    });

    test('cannot create answer without remote offer', () async {
      final pc = RtcPeerConnection();

      expect(() => pc.createAnswer(), throwsStateError);
    });

    test('cannot set local answer in stable state', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);
      final answer = await pc.createAnswer();

      // Create new PC in stable state
      final pc2 = RtcPeerConnection();

      expect(() => pc2.setLocalDescription(answer), throwsStateError);
    });

    test('adds ICE candidate', () async {
      final pc = RtcPeerConnection();

      final candidate = Candidate(
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
      final pc = RtcPeerConnection();

      final candidates = <Candidate>[];
      pc.onIceCandidate.listen(candidates.add);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Wait for ICE gathering
      await Future.delayed(Duration(milliseconds: 100));

      // Should have at least one candidate (host candidate)
      expect(candidates, isNotEmpty);
    });

    test('emits connection state changes', () async {
      final pc = RtcPeerConnection();

      final states = <PeerConnectionState>[];
      pc.onConnectionStateChange.listen(states.add);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await pc.close();

      expect(states, contains(PeerConnectionState.closed));
    });

    test('creates data channel before SCTP is ready (returns ProxyDataChannel)',
        () async {
      final pc = RtcPeerConnection();

      // Wait for async initialization (certificate generation, transport setup)
      await Future.delayed(Duration(milliseconds: 100));

      // SCTP is not ready until ICE/DTLS/SCTP handshakes complete
      // But createDataChannel now returns a ProxyDataChannel that will be
      // wired to a real DataChannel when SCTP becomes ready
      final channel = pc.createDataChannel('test');

      // The channel should be in connecting state until SCTP is ready
      expect(channel.label, equals('test'));
      expect(channel.state, equals(DataChannelState.connecting));

      await pc.close();
    });

    test('closes cleanly', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await pc.close();

      expect(pc.connectionState, PeerConnectionState.closed);
      expect(pc.signalingState, SignalingState.closed);
    });

    test('rollback local offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      expect(pc.signalingState, SignalingState.haveLocalOffer);

      await pc
          .setLocalDescription(SessionDescription(type: 'rollback', sdp: ''));

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.localDescription, isNull);
    });

    test('rollback remote offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);
      expect(pc.signalingState, SignalingState.haveRemoteOffer);

      await pc
          .setRemoteDescription(SessionDescription(type: 'rollback', sdp: ''));

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.remoteDescription, isNull);
    });
  });

  group('RtcConfiguration', () {
    test('default configuration', () {
      const config = RtcConfiguration();

      expect(config.iceServers, isEmpty);
      expect(config.iceTransportPolicy, IceTransportPolicy.all);
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
  });

  group('Signaling State Machine', () {
    test('stable -> haveLocalOffer -> stable', () async {
      final pc1 = RtcPeerConnection();
      final pc2 = RtcPeerConnection();

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
      final pc = RtcPeerConnection();
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
      final pc = RtcPeerConnection();

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
      final pc = RtcPeerConnection();

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
      expect(rtxInfo.rtxPayloadType, 97,
          reason: 'RTX payload type should be 97');
      expect(rtxInfo.associatedPayloadType, 96);

      await pc.close();
    });

    test('audio offer does not include RTX', () async {
      final pc = RtcPeerConnection();

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
      final pc1 = RtcPeerConnection();
      final pc2 = RtcPeerConnection();

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
      final pc = RtcPeerConnection();

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
      final pc = RtcPeerConnection();

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
}
