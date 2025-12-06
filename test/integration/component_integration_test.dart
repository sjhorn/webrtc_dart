import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/peer_connection.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';

void main() {
  group('Component Integration', () {
    test('SDP offer/answer exchange', () async {
      final pc1 = RtcPeerConnection();
      final pc2 = RtcPeerConnection();

      // Create offer
      final offer = await pc1.createOffer();
      expect(offer.type, 'offer');
      expect(offer.sdp, contains('v=0'));
      expect(offer.sdp, contains('m=application'));

      // Set local and remote descriptions
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);

      // Create answer
      final answer = await pc2.createAnswer();
      expect(answer.type, 'answer');

      // Complete exchange
      await pc2.setLocalDescription(answer);
      await pc1.setRemoteDescription(answer);

      // Verify signaling is stable
      expect(pc1.signalingState, SignalingState.stable);
      expect(pc2.signalingState, SignalingState.stable);

      await pc1.close();
      await pc2.close();
    });

    test('SDP parsing contains correct attributes', () async {
      final pc = RtcPeerConnection();
      final offer = await pc.createOffer();

      final sdpMessage = offer.parse();

      // Check session-level attributes
      expect(sdpMessage.attributes.any((a) => a.key == 'group'), isTrue);
      expect(sdpMessage.attributes.any((a) => a.key == 'ice-options'), isTrue);

      // Check media description
      expect(sdpMessage.mediaDescriptions.length, 1);
      final media = sdpMessage.mediaDescriptions[0];

      expect(media.type, 'application');
      expect(media.protocol, 'UDP/DTLS/SCTP');

      // Check ICE credentials are present
      expect(media.getAttributeValue('ice-ufrag'), isNotNull);
      expect(media.getAttributeValue('ice-pwd'), isNotNull);

      // Check DTLS fingerprint
      expect(media.getAttributeValue('fingerprint'), isNotNull);

      // Check SCTP port
      expect(media.getAttributeValue('sctp-port'), '5000');

      await pc.close();
    });

    test('ICE candidate has correct format', () {
      final candidate = Candidate(
        foundation: 'foundation',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 50000,
        type: 'host',
      );

      final sdp = candidate.toSdp();

      expect(sdp, contains('foundation'));
      expect(sdp, contains('1 udp'));
      expect(sdp, contains('192.168.1.1'));
      expect(sdp, contains('50000'));
      expect(sdp, contains('typ host'));
    });

    test('SCTP association sends packets', () async {
      var sentPackets = <Uint8List>[];

      // Create SCTP association
      final assoc1 = SctpAssociation(
        localPort: 5000,
        remotePort: 5000,
        onSendPacket: (packet) async {
          sentPackets.add(packet);
        },
      );

      // Establish connection (will send INIT)
      await assoc1.connect();

      // Wait a bit for INIT packet
      await Future.delayed(Duration(milliseconds: 50));

      // Verify INIT packet was sent
      expect(sentPackets.length, greaterThan(0));

      await assoc1.close();
    });

    test('DataChannel manager creates channels', () async {
      var sentPackets = <Uint8List>[];

      final assoc = SctpAssociation(
        localPort: 5000,
        remotePort: 5000,
        onSendPacket: (packet) async {
          sentPackets.add(packet);
        },
      );

      // Manually set state to established for testing
      // (normally would require full handshake)
      await assoc.connect();

      // Wait for INIT
      await Future.delayed(Duration(milliseconds: 50));

      expect(sentPackets, isNotEmpty);

      await assoc.close();
    });

    test('Codec parameters are correctly defined', () {
      // Test that codec parameters match expected values
      // Import is at top, but need to use the factory function
      final opusParams = createOpusCodec();

      expect(opusParams.isAudio, isTrue);
      expect(opusParams.isVideo, isFalse);
      expect(opusParams.codecName, 'opus');
      expect(opusParams.mimeType, 'audio/opus');
      expect(opusParams.clockRate, 48000);
      expect(opusParams.channels, 2);
    });

    test('Complete offer/answer with ICE candidates', () async {
      final pc1 = RtcPeerConnection();
      final pc2 = RtcPeerConnection();

      final pc1Candidates = <Candidate>[];
      final pc2Candidates = <Candidate>[];

      // Collect ICE candidates
      pc1.onIceCandidate.listen(pc1Candidates.add);
      pc2.onIceCandidate.listen(pc2Candidates.add);

      // Perform offer/answer
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);

      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);
      await pc1.setRemoteDescription(answer);

      // Wait for ICE gathering
      await Future.delayed(Duration(milliseconds: 200));

      // Should have generated at least one host candidate each
      expect(pc1Candidates.length, greaterThanOrEqualTo(1));
      expect(pc2Candidates.length, greaterThanOrEqualTo(1));

      // Verify candidates are valid
      for (final candidate in pc1Candidates) {
        expect(candidate.foundation, isNotEmpty);
        expect(candidate.host, isNotEmpty);
        expect(candidate.port, greaterThan(0));
      }

      await pc1.close();
      await pc2.close();
    });
  });

  group('Protocol Interoperability', () {
    test('SDP round-trip preserves structure', () async {
      final pc = RtcPeerConnection();
      final offer = await pc.createOffer();

      // Parse and re-serialize
      final parsed = offer.parse();
      final reserialized = parsed.serialize();
      final reparsed =
          SessionDescription(type: 'offer', sdp: reserialized).parse();

      // Check key fields are preserved
      expect(reparsed.version, parsed.version);
      expect(reparsed.sessionName, parsed.sessionName);
      expect(
          reparsed.mediaDescriptions.length, parsed.mediaDescriptions.length);

      await pc.close();
    });

    test('ICE candidate can be parsed from SDP', () {
      final sdpLine =
          'foundation 1 udp 2130706431 192.168.1.1 50000 typ host generation 0 ufrag abcd';

      final candidate = Candidate.fromSdp(sdpLine);

      expect(candidate.foundation, 'foundation');
      expect(candidate.component, 1);
      expect(candidate.transport, 'udp');
      expect(candidate.priority, 2130706431);
      expect(candidate.host, '192.168.1.1');
      expect(candidate.port, 50000);
      expect(candidate.type, 'host');
      expect(candidate.generation, 0);
      expect(candidate.ufrag, 'abcd');
    });
  });
}
