import 'package:test/test.dart';
import 'package:webrtc_dart/src/peer_connection.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

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

    test('creates data channel throws before SCTP is ready', () async {
      final pc = RtcPeerConnection();

      // Wait for async initialization (certificate generation, transport setup)
      await Future.delayed(Duration(milliseconds: 100));

      // SCTP is not ready until ICE/DTLS/SCTP handshakes complete
      expect(
        () => pc.createDataChannel('test'),
        throwsA(isA<StateError>()),
      );

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

      await pc.setLocalDescription(
          SessionDescription(type: 'rollback', sdp: ''));

      expect(pc.signalingState, SignalingState.stable);
      expect(pc.localDescription, isNull);
    });

    test('rollback remote offer', () async {
      final pc = RtcPeerConnection();

      final offer = await pc.createOffer();
      await pc.setRemoteDescription(offer);
      expect(pc.signalingState, SignalingState.haveRemoteOffer);

      await pc.setRemoteDescription(
          SessionDescription(type: 'rollback', sdp: ''));

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
}
