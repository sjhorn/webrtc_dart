import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtc_peer_connection.dart';

void main() {
  group('PeerConnection configuration', () {
    group('getConfiguration', () {
      test('returns default configuration when no config provided', () {
        final pc = RtcPeerConnection();
        final config = pc.getConfiguration();

        expect(config, isNotNull);
        expect(config, isA<RtcConfiguration>());
      });

      test('returns initial configuration', () {
        final initialConfig = RtcConfiguration(
          iceServers: [
            IceServer(urls: ['stun:stun.example.com:3478']),
          ],
          bundlePolicy: BundlePolicy.maxBundle,
        );

        final pc = RtcPeerConnection(initialConfig);
        final config = pc.getConfiguration();

        expect(config.iceServers.length, equals(1));
        expect(
            config.iceServers[0].urls[0], equals('stun:stun.example.com:3478'));
        expect(config.bundlePolicy, equals(BundlePolicy.maxBundle));
      });
    });

    group('setConfiguration', () {
      test('updates ICE servers', () {
        final pc = RtcPeerConnection();

        final newConfig = RtcConfiguration(
          iceServers: [
            IceServer(urls: ['stun:stun.newserver.com:3478']),
            IceServer(
              urls: ['turn:turn.newserver.com:3478'],
              username: 'user',
              credential: 'pass',
            ),
          ],
        );

        pc.setConfiguration(newConfig);
        final config = pc.getConfiguration();

        expect(config.iceServers.length, equals(2));
        expect(config.iceServers[0].urls[0],
            equals('stun:stun.newserver.com:3478'));
        expect(config.iceServers[1].urls[0],
            equals('turn:turn.newserver.com:3478'));
      });

      test('updates bundle policy', () {
        final pc = RtcPeerConnection(
          RtcConfiguration(bundlePolicy: BundlePolicy.maxCompat),
        );

        expect(
            pc.getConfiguration().bundlePolicy, equals(BundlePolicy.maxCompat));

        pc.setConfiguration(
          RtcConfiguration(bundlePolicy: BundlePolicy.maxBundle),
        );

        expect(
            pc.getConfiguration().bundlePolicy, equals(BundlePolicy.maxBundle));
      });

      test('updates ICE transport policy', () {
        final pc = RtcPeerConnection();

        pc.setConfiguration(
          RtcConfiguration(iceTransportPolicy: IceTransportPolicy.relay),
        );

        final config = pc.getConfiguration();
        expect(config.iceTransportPolicy, equals(IceTransportPolicy.relay));
      });

      test('can replace configuration multiple times', () {
        final pc = RtcPeerConnection();

        // First update
        pc.setConfiguration(
          RtcConfiguration(
            iceServers: [
              IceServer(urls: ['stun:stun1.example.com']),
            ],
          ),
        );
        expect(pc.getConfiguration().iceServers.length, equals(1));
        expect(pc.getConfiguration().iceServers[0].urls[0], contains('stun1'));

        // Second update
        pc.setConfiguration(
          RtcConfiguration(
            iceServers: [
              IceServer(urls: ['stun:stun2.example.com']),
              IceServer(urls: ['stun:stun3.example.com']),
            ],
          ),
        );
        expect(pc.getConfiguration().iceServers.length, equals(2));
        expect(pc.getConfiguration().iceServers[0].urls[0], contains('stun2'));
        expect(pc.getConfiguration().iceServers[1].urls[0], contains('stun3'));
      });

      test('updates bundle policy to disable', () {
        final pc = RtcPeerConnection();

        pc.setConfiguration(
          RtcConfiguration(bundlePolicy: BundlePolicy.disable),
        );

        expect(
            pc.getConfiguration().bundlePolicy, equals(BundlePolicy.disable));
      });
    });

    group('TURN server configuration', () {
      test('parses TURN credentials from IceServer', () {
        final config = RtcConfiguration(
          iceServers: [
            IceServer(
              urls: ['turn:turn.example.com:3478'],
              username: 'turnuser',
              credential: 'turnpass',
            ),
          ],
        );

        final pc = RtcPeerConnection(config);
        final retrievedConfig = pc.getConfiguration();

        expect(retrievedConfig.iceServers[0].username, equals('turnuser'));
        expect(retrievedConfig.iceServers[0].credential, equals('turnpass'));
      });

      test('handles multiple TURN servers', () {
        final config = RtcConfiguration(
          iceServers: [
            IceServer(
              urls: ['turn:turn1.example.com:3478'],
              username: 'user1',
              credential: 'pass1',
            ),
            IceServer(
              urls: ['turn:turn2.example.com:3478'],
              username: 'user2',
              credential: 'pass2',
            ),
          ],
        );

        final pc = RtcPeerConnection(config);
        final retrievedConfig = pc.getConfiguration();

        expect(retrievedConfig.iceServers.length, equals(2));
      });
    });
  });
}
