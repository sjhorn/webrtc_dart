import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart'
    show CertificateKeyPair, generateSelfSignedCertificate;
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/transport/dtls_transport.dart';
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';
import 'package:webrtc_dart/src/transport/ice_transport.dart';

void main() {
  group('RtcDtlsState', () {
    test('enum has expected values', () {
      expect(RtcDtlsState.values.length, 5);
      expect(RtcDtlsState.new_, isNotNull);
      expect(RtcDtlsState.connecting, isNotNull);
      expect(RtcDtlsState.connected, isNotNull);
      expect(RtcDtlsState.closed, isNotNull);
      expect(RtcDtlsState.failed, isNotNull);
    });
  });

  group('RtcDtlsRole', () {
    test('enum has expected values', () {
      expect(RtcDtlsRole.values.length, 3);
      expect(RtcDtlsRole.auto, isNotNull);
      expect(RtcDtlsRole.server, isNotNull);
      expect(RtcDtlsRole.client, isNotNull);
    });
  });

  group('RtcDtlsFingerprint', () {
    test('creates with required parameters', () {
      final fingerprint = RtcDtlsFingerprint(
        algorithm: 'sha-256',
        value: 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
      );

      expect(fingerprint.algorithm, 'sha-256');
      expect(fingerprint.value, contains('AA:BB'));
    });

    test('toString truncates fingerprint', () {
      final fingerprint = RtcDtlsFingerprint(
        algorithm: 'sha-256',
        value: 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
      );

      final str = fingerprint.toString();
      expect(str, contains('sha-256'));
      expect(str, contains('...'));
    });
  });

  group('RtcDtlsParameters', () {
    test('creates with defaults', () {
      final params = RtcDtlsParameters();

      expect(params.fingerprints, isEmpty);
      expect(params.role, RtcDtlsRole.auto);
    });

    test('creates with fingerprints', () {
      final fingerprint = RtcDtlsFingerprint(
        algorithm: 'sha-256',
        value: 'test-fingerprint',
      );

      final params = RtcDtlsParameters(
        fingerprints: [fingerprint],
        role: RtcDtlsRole.server,
      );

      expect(params.fingerprints.length, 1);
      expect(params.role, RtcDtlsRole.server);
    });
  });

  group('RtcDtlsTransport', () {
    late IceConnection iceConnection;
    late RtcIceGatherer iceGatherer;
    late RtcIceTransport iceTransport;
    late CertificateKeyPair certificate;

    setUpAll(() async {
      // Generate certificate once for all tests
      certificate = await generateSelfSignedCertificate();
    });

    setUp(() {
      iceConnection = IceConnectionImpl(iceControlling: true);
      iceGatherer = RtcIceGatherer(iceConnection);
      iceTransport = RtcIceTransport(iceGatherer);
    });

    tearDown(() async {
      await iceTransport.stop();
    });

    test('initial state is new', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      expect(dtlsTransport.state, RtcDtlsState.new_);
    });

    test('exposes underlying iceTransport', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      expect(dtlsTransport.iceTransport, iceTransport);
    });

    test('role defaults to auto', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      expect(dtlsTransport.role, RtcDtlsRole.auto);
    });

    test('role can be set explicitly', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
        role: RtcDtlsRole.server,
      );

      expect(dtlsTransport.role, RtcDtlsRole.server);
    });

    test('localParameters contains fingerprint', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      final params = dtlsTransport.localParameters;
      expect(params.fingerprints, isNotEmpty);
      expect(params.fingerprints.first.algorithm, 'sha-256');
      expect(params.fingerprints.first.value, isNotEmpty);
    });

    test('localParameters empty without certificate', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: null,
      );

      final params = dtlsTransport.localParameters;
      expect(params.fingerprints, isEmpty);
    });

    test('setRemoteParams stores parameters', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      final remoteParams = RtcDtlsParameters(
        fingerprints: [
          RtcDtlsFingerprint(algorithm: 'sha-256', value: 'remote-fp'),
        ],
        role: RtcDtlsRole.client,
      );

      dtlsTransport.setRemoteParams(remoteParams);
      // Parameters stored internally (not directly accessible but used in start())
    });

    test('start() throws if state is not new', () async {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      // Close the transport first
      await dtlsTransport.stop();

      expect(
        () => dtlsTransport.start(),
        throwsStateError,
      );
    });

    test('start() throws without remote fingerprints', () async {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      // Don't set remote params
      expect(
        () => dtlsTransport.start(),
        throwsStateError,
      );
    });

    test('stop() transitions to closed state', () async {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      await dtlsTransport.stop();

      expect(dtlsTransport.state, RtcDtlsState.closed);
    });

    test('stop() is idempotent', () async {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      await dtlsTransport.stop();
      await dtlsTransport.stop(); // Should not throw

      expect(dtlsTransport.state, RtcDtlsState.closed);
    });

    test('onStateChange emits state transitions', () async {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      final states = <RtcDtlsState>[];
      dtlsTransport.onStateChange.listen(states.add);

      await dtlsTransport.stop();

      expect(states, contains(RtcDtlsState.closed));
    });

    test('statistics are initially zero', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      expect(dtlsTransport.bytesSent, 0);
      expect(dtlsTransport.bytesReceived, 0);
      expect(dtlsTransport.packetsSent, 0);
      expect(dtlsTransport.packetsReceived, 0);
    });

    test('srtpStarted is initially false', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      expect(dtlsTransport.srtpStarted, false);
    });

    test('debugLabel can be set', () {
      final dtlsTransport = RtcDtlsTransport(
        iceTransport: iceTransport,
        localCertificate: certificate,
      );

      dtlsTransport.debugLabel = 'test-transport';
      expect(dtlsTransport.debugLabel, 'test-transport');
    });
  });

  // Note: Full DTLS integration tests are covered in test/integration/full_stack_test.dart
  // These tests would require full ICE connectivity which is redundant to test here.
  group('RtcDtlsTransport integration', () {
    test('full DTLS handshake is tested in full_stack_test.dart', () {
      // This is a placeholder - the actual integration test is in full_stack_test.dart
      // Testing RtcDtlsTransport in isolation would require mocking the ICE layer
      expect(true, true);
    });
  });
}
