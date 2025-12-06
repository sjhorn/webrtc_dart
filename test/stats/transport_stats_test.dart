import 'package:test/test.dart';
import 'package:webrtc_dart/src/stats/transport_stats.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';

void main() {
  // Helper to get timestamp as double
  double now() => DateTime.now().millisecondsSinceEpoch.toDouble();

  group('RTCDtlsTransportState', () {
    test('newState has correct value', () {
      expect(RTCDtlsTransportState.newState.value, equals('new'));
      expect(RTCDtlsTransportState.newState.toString(), equals('new'));
    });

    test('connecting has correct value', () {
      expect(RTCDtlsTransportState.connecting.value, equals('connecting'));
      expect(RTCDtlsTransportState.connecting.toString(), equals('connecting'));
    });

    test('connected has correct value', () {
      expect(RTCDtlsTransportState.connected.value, equals('connected'));
      expect(RTCDtlsTransportState.connected.toString(), equals('connected'));
    });

    test('closed has correct value', () {
      expect(RTCDtlsTransportState.closed.value, equals('closed'));
      expect(RTCDtlsTransportState.closed.toString(), equals('closed'));
    });

    test('failed has correct value', () {
      expect(RTCDtlsTransportState.failed.value, equals('failed'));
      expect(RTCDtlsTransportState.failed.toString(), equals('failed'));
    });
  });

  group('RTCIceTransportState', () {
    test('newState has correct value', () {
      expect(RTCIceTransportState.newState.value, equals('new'));
      expect(RTCIceTransportState.newState.toString(), equals('new'));
    });

    test('checking has correct value', () {
      expect(RTCIceTransportState.checking.value, equals('checking'));
      expect(RTCIceTransportState.checking.toString(), equals('checking'));
    });

    test('connected has correct value', () {
      expect(RTCIceTransportState.connected.value, equals('connected'));
      expect(RTCIceTransportState.connected.toString(), equals('connected'));
    });

    test('completed has correct value', () {
      expect(RTCIceTransportState.completed.value, equals('completed'));
      expect(RTCIceTransportState.completed.toString(), equals('completed'));
    });

    test('disconnected has correct value', () {
      expect(RTCIceTransportState.disconnected.value, equals('disconnected'));
      expect(
          RTCIceTransportState.disconnected.toString(), equals('disconnected'));
    });

    test('failed has correct value', () {
      expect(RTCIceTransportState.failed.value, equals('failed'));
      expect(RTCIceTransportState.failed.toString(), equals('failed'));
    });

    test('closed has correct value', () {
      expect(RTCIceTransportState.closed.value, equals('closed'));
      expect(RTCIceTransportState.closed.toString(), equals('closed'));
    });
  });

  group('RTCIceRole', () {
    test('unknown has correct value', () {
      expect(RTCIceRole.unknown.value, equals('unknown'));
      expect(RTCIceRole.unknown.toString(), equals('unknown'));
    });

    test('controlling has correct value', () {
      expect(RTCIceRole.controlling.value, equals('controlling'));
      expect(RTCIceRole.controlling.toString(), equals('controlling'));
    });

    test('controlled has correct value', () {
      expect(RTCIceRole.controlled.value, equals('controlled'));
      expect(RTCIceRole.controlled.toString(), equals('controlled'));
    });
  });

  group('RTCTransportStats', () {
    test('construction with required values', () {
      final timestamp = now();
      final stats = RTCTransportStats(
        timestamp: timestamp,
        id: 'transport-1',
      );

      expect(stats.timestamp, equals(timestamp));
      expect(stats.id, equals('transport-1'));
      expect(stats.type, equals(RTCStatsType.transport));
      expect(stats.bytesSent, isNull);
      expect(stats.bytesReceived, isNull);
    });

    test('construction with all values', () {
      final timestamp = now();
      final stats = RTCTransportStats(
        timestamp: timestamp,
        id: 'transport-1',
        bytesSent: 1000,
        bytesReceived: 2000,
        packetsSent: 10,
        packetsReceived: 20,
        rtcpTransportStatsId: 'rtcp-1',
        iceLocalCandidateId: 'local-1',
        iceRemoteCandidateId: 'remote-1',
        iceState: RTCIceTransportState.connected,
        selectedCandidatePairId: 'pair-1',
        selectedCandidatePairChanges: 2,
        localCertificateId: 'cert-local',
        remoteCertificateId: 'cert-remote',
        tlsVersion: '1.2',
        dtlsCipher: 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',
        dtlsState: RTCDtlsTransportState.connected,
        srtpCipher: 'AEAD_AES_128_GCM',
        tlsGroup: 'X25519',
        iceRole: RTCIceRole.controlling,
        iceLocalUsernameFragment: 'ufrag',
      );

      expect(stats.bytesSent, equals(1000));
      expect(stats.bytesReceived, equals(2000));
      expect(stats.packetsSent, equals(10));
      expect(stats.packetsReceived, equals(20));
      expect(stats.rtcpTransportStatsId, equals('rtcp-1'));
      expect(stats.iceLocalCandidateId, equals('local-1'));
      expect(stats.iceRemoteCandidateId, equals('remote-1'));
      expect(stats.iceState, equals(RTCIceTransportState.connected));
      expect(stats.selectedCandidatePairId, equals('pair-1'));
      expect(stats.selectedCandidatePairChanges, equals(2));
      expect(stats.localCertificateId, equals('cert-local'));
      expect(stats.remoteCertificateId, equals('cert-remote'));
      expect(stats.tlsVersion, equals('1.2'));
      expect(
          stats.dtlsCipher, equals('TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256'));
      expect(stats.dtlsState, equals(RTCDtlsTransportState.connected));
      expect(stats.srtpCipher, equals('AEAD_AES_128_GCM'));
      expect(stats.tlsGroup, equals('X25519'));
      expect(stats.iceRole, equals(RTCIceRole.controlling));
      expect(stats.iceLocalUsernameFragment, equals('ufrag'));
    });

    test('toJson includes all set values', () {
      final timestamp = now();
      final stats = RTCTransportStats(
        timestamp: timestamp,
        id: 'transport-1',
        bytesSent: 1000,
        bytesReceived: 2000,
        packetsSent: 10,
        packetsReceived: 20,
        rtcpTransportStatsId: 'rtcp-1',
        iceLocalCandidateId: 'local-1',
        iceRemoteCandidateId: 'remote-1',
        iceState: RTCIceTransportState.connected,
        selectedCandidatePairId: 'pair-1',
        selectedCandidatePairChanges: 2,
        localCertificateId: 'cert-local',
        remoteCertificateId: 'cert-remote',
        tlsVersion: '1.2',
        dtlsCipher: 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',
        dtlsState: RTCDtlsTransportState.connected,
        srtpCipher: 'AEAD_AES_128_GCM',
        tlsGroup: 'X25519',
        iceRole: RTCIceRole.controlling,
        iceLocalUsernameFragment: 'ufrag',
      );

      final json = stats.toJson();

      expect(json['type'], equals('transport'));
      expect(json['id'], equals('transport-1'));
      expect(json['bytesSent'], equals(1000));
      expect(json['bytesReceived'], equals(2000));
      expect(json['packetsSent'], equals(10));
      expect(json['packetsReceived'], equals(20));
      expect(json['rtcpTransportStatsId'], equals('rtcp-1'));
      expect(json['iceLocalCandidateId'], equals('local-1'));
      expect(json['iceRemoteCandidateId'], equals('remote-1'));
      expect(json['iceState'], equals('connected'));
      expect(json['selectedCandidatePairId'], equals('pair-1'));
      expect(json['selectedCandidatePairChanges'], equals(2));
      expect(json['localCertificateId'], equals('cert-local'));
      expect(json['remoteCertificateId'], equals('cert-remote'));
      expect(json['tlsVersion'], equals('1.2'));
      expect(json['dtlsCipher'],
          equals('TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256'));
      expect(json['dtlsState'], equals('connected'));
      expect(json['srtpCipher'], equals('AEAD_AES_128_GCM'));
      expect(json['tlsGroup'], equals('X25519'));
      expect(json['iceRole'], equals('controlling'));
      expect(json['iceLocalUsernameFragment'], equals('ufrag'));
    });

    test('toJson omits null values', () {
      final timestamp = now();
      final stats = RTCTransportStats(
        timestamp: timestamp,
        id: 'transport-1',
      );

      final json = stats.toJson();

      expect(json.containsKey('bytesSent'), isFalse);
      expect(json.containsKey('bytesReceived'), isFalse);
      expect(json.containsKey('iceState'), isFalse);
      expect(json.containsKey('dtlsState'), isFalse);
    });
  });

  group('RTCCertificateStats', () {
    test('construction with required values', () {
      final timestamp = now();
      final stats = RTCCertificateStats(
        timestamp: timestamp,
        id: 'cert-1',
        fingerprint: 'AA:BB:CC:DD:EE:FF',
        fingerprintAlgorithm: 'sha-256',
      );

      expect(stats.timestamp, equals(timestamp));
      expect(stats.id, equals('cert-1'));
      expect(stats.type, equals(RTCStatsType.certificate));
      expect(stats.fingerprint, equals('AA:BB:CC:DD:EE:FF'));
      expect(stats.fingerprintAlgorithm, equals('sha-256'));
      expect(stats.base64Certificate, isNull);
      expect(stats.issuerCertificateId, isNull);
    });

    test('construction with all values', () {
      final timestamp = now();
      final stats = RTCCertificateStats(
        timestamp: timestamp,
        id: 'cert-1',
        fingerprint: 'AA:BB:CC:DD:EE:FF',
        fingerprintAlgorithm: 'sha-256',
        base64Certificate: 'MIIB...',
        issuerCertificateId: 'cert-issuer',
      );

      expect(stats.fingerprint, equals('AA:BB:CC:DD:EE:FF'));
      expect(stats.fingerprintAlgorithm, equals('sha-256'));
      expect(stats.base64Certificate, equals('MIIB...'));
      expect(stats.issuerCertificateId, equals('cert-issuer'));
    });

    test('toJson includes all values', () {
      final timestamp = now();
      final stats = RTCCertificateStats(
        timestamp: timestamp,
        id: 'cert-1',
        fingerprint: 'AA:BB:CC:DD:EE:FF',
        fingerprintAlgorithm: 'sha-256',
        base64Certificate: 'MIIB...',
        issuerCertificateId: 'cert-issuer',
      );

      final json = stats.toJson();

      expect(json['type'], equals('certificate'));
      expect(json['id'], equals('cert-1'));
      expect(json['fingerprint'], equals('AA:BB:CC:DD:EE:FF'));
      expect(json['fingerprintAlgorithm'], equals('sha-256'));
      expect(json['base64Certificate'], equals('MIIB...'));
      expect(json['issuerCertificateId'], equals('cert-issuer'));
    });

    test('toJson omits null optional values', () {
      final timestamp = now();
      final stats = RTCCertificateStats(
        timestamp: timestamp,
        id: 'cert-1',
        fingerprint: 'AA:BB:CC:DD:EE:FF',
        fingerprintAlgorithm: 'sha-256',
      );

      final json = stats.toJson();

      expect(json.containsKey('fingerprint'), isTrue);
      expect(json.containsKey('fingerprintAlgorithm'), isTrue);
      expect(json.containsKey('base64Certificate'), isFalse);
      expect(json.containsKey('issuerCertificateId'), isFalse);
    });
  });
}
