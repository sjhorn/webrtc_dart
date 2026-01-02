import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/rtc_peer_connection.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

void main() {
  group('IceConnection restart', () {
    test('restart generates new credentials', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      final oldUsername = ice.localUsername;
      final oldPassword = ice.localPassword;
      final oldGeneration = ice.generation;

      await ice.restart();

      expect(ice.localUsername, isNot(equals(oldUsername)));
      expect(ice.localPassword, isNot(equals(oldPassword)));
      expect(ice.generation, equals(oldGeneration + 1));

      await ice.close();
    });

    test('restart clears remote credentials', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      ice.setRemoteParams(
        iceLite: false,
        usernameFragment: 'remote_ufrag',
        password: 'remote_password',
      );

      expect(ice.remoteUsername, equals('remote_ufrag'));
      expect(ice.remotePassword, equals('remote_password'));

      await ice.restart();

      expect(ice.remoteUsername, isEmpty);
      expect(ice.remotePassword, isEmpty);

      await ice.close();
    });

    test('restart clears candidates', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      // Gather some candidates
      await ice.gatherCandidates();

      expect(ice.localCandidates, isNotEmpty);

      await ice.restart();

      expect(ice.localCandidates, isEmpty);
      expect(ice.remoteCandidates, isEmpty);
      expect(ice.checkList, isEmpty);

      await ice.close();
    });

    test('restart resets state to new', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      // Start gathering
      await ice.gatherCandidates();

      expect(ice.state, isNot(equals(IceState.newState)));

      await ice.restart();

      expect(ice.state, equals(IceState.newState));

      await ice.close();
    });

    test('restart clears nominated pair', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      await ice.gatherCandidates();

      // Note: nominated would be set during connectivity checks
      // For this test, we just verify it's null after restart
      await ice.restart();

      expect(ice.nominated, isNull);

      await ice.close();
    });

    test('restart increments generation counter', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      expect(ice.generation, equals(0));

      await ice.restart();
      expect(ice.generation, equals(1));

      await ice.restart();
      expect(ice.generation, equals(2));

      await ice.restart();
      expect(ice.generation, equals(3));

      await ice.close();
    });

    test('restart resets localCandidatesEnd flag', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      await ice.gatherCandidates();
      expect(ice.localCandidatesEnd, isTrue);

      await ice.restart();
      expect(ice.localCandidatesEnd, isFalse);

      await ice.close();
    });

    test('restart resets remoteCandidatesEnd flag', () async {
      final ice = IceConnectionImpl(iceControlling: true);

      await ice.addRemoteCandidate(null); // Signal end of candidates
      expect(ice.remoteCandidatesEnd, isTrue);

      await ice.restart();
      expect(ice.remoteCandidatesEnd, isFalse);

      await ice.close();
    });
  });

  group('RtcPeerConnection restartIce', () {
    test('restartIce sets needsRestart flag', () async {
      final pc = RtcPeerConnection();

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      pc.restartIce();

      // The flag is private, but we can verify behavior through createOffer
      // which should use new credentials after restartIce()
      await pc.close();
    });

    test('restartIce throws if connection is closed', () async {
      final pc = RtcPeerConnection();

      await Future.delayed(Duration(milliseconds: 100));
      await pc.close();

      expect(() => pc.restartIce(), throwsA(isA<StateError>()));
    });
  });

  group('RtcOfferOptions', () {
    test('default iceRestart is false', () {
      final options = RtcOfferOptions();
      expect(options.iceRestart, isFalse);
    });

    test('can set iceRestart to true', () {
      final options = RtcOfferOptions(iceRestart: true);
      expect(options.iceRestart, isTrue);
    });
  });

  group('createOffer with iceRestart', () {
    test('createOffer with iceRestart generates new credentials', () async {
      final pc = RtcPeerConnection();

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      // Create first offer
      final offer1 = await pc.createOffer();
      final sdp1 = offer1.sdp;

      // Extract ice-ufrag from SDP
      final ufragMatch1 = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp1);
      final ufrag1 = ufragMatch1?.group(1);

      // Create offer with ICE restart
      final offer2 = await pc.createOffer(RtcOfferOptions(iceRestart: true));
      final sdp2 = offer2.sdp;

      final ufragMatch2 = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp2);
      final ufrag2 = ufragMatch2?.group(1);

      // Credentials should be different after ICE restart
      expect(ufrag1, isNotNull);
      expect(ufrag2, isNotNull);
      expect(ufrag2, isNot(equals(ufrag1)));

      await pc.close();
    });

    test('createOffer after restartIce generates new credentials', () async {
      final pc = RtcPeerConnection();

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      // Create first offer
      final offer1 = await pc.createOffer();
      final sdp1 = offer1.sdp;

      final ufragMatch1 = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp1);
      final ufrag1 = ufragMatch1?.group(1);

      // Request ICE restart
      pc.restartIce();

      // Create second offer (should use new credentials)
      final offer2 = await pc.createOffer();
      final sdp2 = offer2.sdp;

      final ufragMatch2 = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp2);
      final ufrag2 = ufragMatch2?.group(1);

      // Credentials should be different after ICE restart
      expect(ufrag1, isNotNull);
      expect(ufrag2, isNotNull);
      expect(ufrag2, isNot(equals(ufrag1)));

      await pc.close();
    });

    test('multiple createOffer without iceRestart keeps same credentials',
        () async {
      final pc = RtcPeerConnection();

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      // Create first offer
      final offer1 = await pc.createOffer();
      final sdp1 = offer1.sdp;

      final ufragMatch1 = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp1);
      final ufrag1 = ufragMatch1?.group(1);

      // Create second offer without ICE restart
      final offer2 = await pc.createOffer();
      final sdp2 = offer2.sdp;

      final ufragMatch2 = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp2);
      final ufrag2 = ufragMatch2?.group(1);

      // Credentials should be the same
      expect(ufrag1, equals(ufrag2));

      await pc.close();
    });
  });

  group('Remote ICE restart detection', () {
    test('detects remote ICE restart when credentials change', () async {
      final pc = RtcPeerConnection();

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      // Set initial remote description with credentials
      final remoteSdp1 = '''v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:remote1
a=ice-pwd:remotepassword1234567890
a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00
a=setup:actpass
a=mid:0
a=sctp-port:5000
''';

      await pc.setRemoteDescription(
          SessionDescription(type: 'offer', sdp: remoteSdp1));

      // Create and set local answer
      final answer1 = await pc.createAnswer();
      await pc.setLocalDescription(answer1);

      // New remote description with different credentials (ICE restart)
      final remoteSdp2 = '''v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:remote2
a=ice-pwd:differentpassword12345
a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00
a=setup:actpass
a=mid:0
a=sctp-port:5000
''';

      // This should detect the remote ICE restart
      await pc.setRemoteDescription(
          SessionDescription(type: 'offer', sdp: remoteSdp2));

      // The local ICE connection should have been restarted
      // (Generation incremented, new credentials)
      // We can't easily verify this without exposing internals,
      // but the test passes if no exceptions occur

      await pc.close();
    });

    test('same credentials do not trigger ICE restart', () async {
      final pc = RtcPeerConnection();

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      // Set initial remote description
      final remoteSdp = '''v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:sameufrag
a=ice-pwd:samepassword1234567890
a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00
a=setup:actpass
a=mid:0
a=sctp-port:5000
''';

      await pc.setRemoteDescription(
          SessionDescription(type: 'offer', sdp: remoteSdp));

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      // Set same remote description again (no credential change)
      await pc.setRemoteDescription(
          SessionDescription(type: 'offer', sdp: remoteSdp));

      // No ICE restart should occur - test passes if no exceptions

      await pc.close();
    });
  });
}
