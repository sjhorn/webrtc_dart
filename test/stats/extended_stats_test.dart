import 'package:test/test.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';
import 'package:webrtc_dart/src/stats/ice_stats.dart';
import 'package:webrtc_dart/src/stats/transport_stats.dart';
import 'package:webrtc_dart/src/stats/data_channel_stats.dart';

void main() {
  group('RTCIceCandidateStats', () {
    test('local candidate construction', () {
      final stats = RTCIceCandidateStats(
        timestamp: 1234567890.0,
        id: 'local-candidate-1',
        isRemote: false,
        address: '192.168.1.100',
        port: 54321,
        protocol: 'udp',
        candidateType: 'host',
        priority: 2130706431,
        foundation: 'abc123',
      );

      expect(stats.type, equals(RTCStatsType.localCandidate));
      expect(stats.isRemote, isFalse);
      expect(stats.address, equals('192.168.1.100'));
      expect(stats.port, equals(54321));
      expect(stats.protocol, equals('udp'));
      expect(stats.candidateType, equals('host'));
    });

    test('remote candidate construction', () {
      final stats = RTCIceCandidateStats(
        timestamp: 1234567890.0,
        id: 'remote-candidate-1',
        isRemote: true,
        address: '10.0.0.1',
        port: 12345,
        protocol: 'udp',
        candidateType: 'srflx',
        relatedAddress: '192.168.1.50',
        relatedPort: 54321,
      );

      expect(stats.type, equals(RTCStatsType.remoteCandidate));
      expect(stats.isRemote, isTrue);
      expect(stats.candidateType, equals('srflx'));
      expect(stats.relatedAddress, equals('192.168.1.50'));
      expect(stats.relatedPort, equals(54321));
    });

    test('toJson includes all fields', () {
      final stats = RTCIceCandidateStats(
        timestamp: 1234567890.0,
        id: 'candidate-1',
        isRemote: false,
        transportId: 'transport-1',
        address: '192.168.1.100',
        port: 54321,
        protocol: 'udp',
        candidateType: 'host',
        priority: 2130706431,
        foundation: 'abc123',
        usernameFragment: 'ufrag',
      );

      final json = stats.toJson();

      expect(json['id'], equals('candidate-1'));
      expect(json['type'], equals('local-candidate'));
      expect(json['isRemote'], isFalse);
      expect(json['address'], equals('192.168.1.100'));
      expect(json['port'], equals(54321));
      expect(json['protocol'], equals('udp'));
      expect(json['candidateType'], equals('host'));
      expect(json['priority'], equals(2130706431));
      expect(json['foundation'], equals('abc123'));
    });

    test('relay candidate with URL', () {
      final stats = RTCIceCandidateStats(
        timestamp: 1234567890.0,
        id: 'relay-candidate-1',
        isRemote: false,
        address: '100.200.50.25',
        port: 3478,
        protocol: 'udp',
        candidateType: 'relay',
        url: 'turn:turn.example.com:3478',
        relatedAddress: '192.168.1.100',
        relatedPort: 54321,
      );

      expect(stats.candidateType, equals('relay'));
      expect(stats.url, equals('turn:turn.example.com:3478'));
    });
  });

  group('RTCIceCandidatePairStats', () {
    test('construction with required fields', () {
      final stats = RTCIceCandidatePairStats(
        timestamp: 1234567890.0,
        id: 'pair-1',
        localCandidateId: 'local-1',
        remoteCandidateId: 'remote-1',
        state: RTCStatsIceCandidatePairState.succeeded,
      );

      expect(stats.type, equals(RTCStatsType.candidatePair));
      expect(stats.localCandidateId, equals('local-1'));
      expect(stats.remoteCandidateId, equals('remote-1'));
      expect(stats.state, equals(RTCStatsIceCandidatePairState.succeeded));
    });

    test('construction with traffic stats', () {
      final stats = RTCIceCandidatePairStats(
        timestamp: 1234567890.0,
        id: 'pair-1',
        localCandidateId: 'local-1',
        remoteCandidateId: 'remote-1',
        state: RTCStatsIceCandidatePairState.succeeded,
        nominated: true,
        packetsSent: 100,
        packetsReceived: 95,
        bytesSent: 50000,
        bytesReceived: 48000,
        currentRoundTripTime: 0.025,
        totalRoundTripTime: 2.5,
      );

      expect(stats.nominated, isTrue);
      expect(stats.packetsSent, equals(100));
      expect(stats.packetsReceived, equals(95));
      expect(stats.bytesSent, equals(50000));
      expect(stats.bytesReceived, equals(48000));
      expect(stats.currentRoundTripTime, equals(0.025));
    });

    test('toJson includes all fields', () {
      final stats = RTCIceCandidatePairStats(
        timestamp: 1234567890.0,
        id: 'pair-1',
        transportId: 'transport-1',
        localCandidateId: 'local-1',
        remoteCandidateId: 'remote-1',
        state: RTCStatsIceCandidatePairState.inProgress,
        nominated: false,
        requestsSent: 5,
        responsesReceived: 3,
        priority: 9000000000,
      );

      final json = stats.toJson();

      expect(json['id'], equals('pair-1'));
      expect(json['type'], equals('candidate-pair'));
      expect(json['localCandidateId'], equals('local-1'));
      expect(json['remoteCandidateId'], equals('remote-1'));
      expect(json['state'], equals('in-progress'));
      expect(json['nominated'], isFalse);
      expect(json['requestsSent'], equals(5));
      expect(json['responsesReceived'], equals(3));
    });

    test('all pair states', () {
      expect(RTCStatsIceCandidatePairState.frozen.value, equals('frozen'));
      expect(RTCStatsIceCandidatePairState.waiting.value, equals('waiting'));
      expect(RTCStatsIceCandidatePairState.inProgress.value,
          equals('in-progress'));
      expect(RTCStatsIceCandidatePairState.failed.value, equals('failed'));
      expect(
          RTCStatsIceCandidatePairState.succeeded.value, equals('succeeded'));
    });
  });

  group('RTCTransportStats', () {
    test('construction with basic fields', () {
      final stats = RTCTransportStats(
        timestamp: 1234567890.0,
        id: 'transport-1',
        bytesSent: 100000,
        bytesReceived: 95000,
        packetsSent: 500,
        packetsReceived: 480,
      );

      expect(stats.type, equals(RTCStatsType.transport));
      expect(stats.bytesSent, equals(100000));
      expect(stats.bytesReceived, equals(95000));
      expect(stats.packetsSent, equals(500));
      expect(stats.packetsReceived, equals(480));
    });

    test('construction with ICE fields', () {
      final stats = RTCTransportStats(
        timestamp: 1234567890.0,
        id: 'transport-1',
        iceState: RTCIceTransportState.completed,
        iceRole: RTCIceRole.controlling,
        selectedCandidatePairId: 'pair-1',
        iceLocalUsernameFragment: 'ufrag123',
      );

      expect(stats.iceState, equals(RTCIceTransportState.completed));
      expect(stats.iceRole, equals(RTCIceRole.controlling));
      expect(stats.selectedCandidatePairId, equals('pair-1'));
    });

    test('construction with DTLS fields', () {
      final stats = RTCTransportStats(
        timestamp: 1234567890.0,
        id: 'transport-1',
        dtlsState: RTCDtlsTransportState.connected,
        dtlsCipher: 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',
        tlsVersion: '1.2',
        srtpCipher: 'AEAD_AES_128_GCM',
        localCertificateId: 'cert-local',
        remoteCertificateId: 'cert-remote',
      );

      expect(stats.dtlsState, equals(RTCDtlsTransportState.connected));
      expect(stats.tlsVersion, equals('1.2'));
      expect(stats.srtpCipher, equals('AEAD_AES_128_GCM'));
    });

    test('toJson includes all fields', () {
      final stats = RTCTransportStats(
        timestamp: 1234567890.0,
        id: 'transport-1',
        bytesSent: 100000,
        bytesReceived: 95000,
        iceState: RTCIceTransportState.connected,
        dtlsState: RTCDtlsTransportState.connected,
        iceRole: RTCIceRole.controlled,
      );

      final json = stats.toJson();

      expect(json['id'], equals('transport-1'));
      expect(json['type'], equals('transport'));
      expect(json['bytesSent'], equals(100000));
      expect(json['iceState'], equals('connected'));
      expect(json['dtlsState'], equals('connected'));
      expect(json['iceRole'], equals('controlled'));
    });

    test('all DTLS states', () {
      expect(RTCDtlsTransportState.newState.value, equals('new'));
      expect(RTCDtlsTransportState.connecting.value, equals('connecting'));
      expect(RTCDtlsTransportState.connected.value, equals('connected'));
      expect(RTCDtlsTransportState.closed.value, equals('closed'));
      expect(RTCDtlsTransportState.failed.value, equals('failed'));
    });

    test('all ICE transport states', () {
      expect(RTCIceTransportState.newState.value, equals('new'));
      expect(RTCIceTransportState.checking.value, equals('checking'));
      expect(RTCIceTransportState.connected.value, equals('connected'));
      expect(RTCIceTransportState.completed.value, equals('completed'));
      expect(RTCIceTransportState.disconnected.value, equals('disconnected'));
      expect(RTCIceTransportState.failed.value, equals('failed'));
      expect(RTCIceTransportState.closed.value, equals('closed'));
    });

    test('all ICE roles', () {
      expect(RTCIceRole.unknown.value, equals('unknown'));
      expect(RTCIceRole.controlling.value, equals('controlling'));
      expect(RTCIceRole.controlled.value, equals('controlled'));
    });
  });

  group('RTCCertificateStats', () {
    test('construction', () {
      final stats = RTCCertificateStats(
        timestamp: 1234567890.0,
        id: 'certificate-1',
        fingerprint:
            'sha-256 AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90',
        fingerprintAlgorithm: 'sha-256',
      );

      expect(stats.type, equals(RTCStatsType.certificate));
      expect(stats.fingerprint, contains('AB:CD:EF'));
      expect(stats.fingerprintAlgorithm, equals('sha-256'));
    });

    test('construction with certificate chain', () {
      final stats = RTCCertificateStats(
        timestamp: 1234567890.0,
        id: 'certificate-1',
        fingerprint: 'sha-256 AA:BB:CC:DD',
        fingerprintAlgorithm: 'sha-256',
        issuerCertificateId: 'certificate-2',
        base64Certificate: 'MIIBkTCB+wIJAL...',
      );

      expect(stats.issuerCertificateId, equals('certificate-2'));
      expect(stats.base64Certificate, isNotNull);
    });

    test('toJson includes all fields', () {
      final stats = RTCCertificateStats(
        timestamp: 1234567890.0,
        id: 'cert-1',
        fingerprint: 'sha-256 AA:BB:CC',
        fingerprintAlgorithm: 'sha-256',
        base64Certificate: 'base64data',
      );

      final json = stats.toJson();

      expect(json['id'], equals('cert-1'));
      expect(json['type'], equals('certificate'));
      expect(json['fingerprint'], equals('sha-256 AA:BB:CC'));
      expect(json['fingerprintAlgorithm'], equals('sha-256'));
      expect(json['base64Certificate'], equals('base64data'));
    });
  });

  group('RTCDataChannelStats', () {
    test('construction with required fields', () {
      final stats = RTCDataChannelStats(
        timestamp: 1234567890.0,
        id: 'datachannel-1',
        state: RTCDataChannelState.open,
      );

      expect(stats.type, equals(RTCStatsType.dataChannel));
      expect(stats.state, equals(RTCDataChannelState.open));
    });

    test('construction with all fields', () {
      final stats = RTCDataChannelStats(
        timestamp: 1234567890.0,
        id: 'datachannel-1',
        label: 'chat',
        protocol: 'json',
        dataChannelIdentifier: 1,
        state: RTCDataChannelState.open,
        messagesSent: 100,
        bytesSent: 5000,
        messagesReceived: 95,
        bytesReceived: 4800,
      );

      expect(stats.label, equals('chat'));
      expect(stats.protocol, equals('json'));
      expect(stats.dataChannelIdentifier, equals(1));
      expect(stats.messagesSent, equals(100));
      expect(stats.bytesSent, equals(5000));
      expect(stats.messagesReceived, equals(95));
      expect(stats.bytesReceived, equals(4800));
    });

    test('toJson includes all fields', () {
      final stats = RTCDataChannelStats(
        timestamp: 1234567890.0,
        id: 'dc-1',
        label: 'test-channel',
        state: RTCDataChannelState.connecting,
        messagesSent: 10,
        bytesSent: 500,
      );

      final json = stats.toJson();

      expect(json['id'], equals('dc-1'));
      expect(json['type'], equals('data-channel'));
      expect(json['label'], equals('test-channel'));
      expect(json['state'], equals('connecting'));
      expect(json['messagesSent'], equals(10));
      expect(json['bytesSent'], equals(500));
    });

    test('all data channel states', () {
      expect(RTCDataChannelState.connecting.value, equals('connecting'));
      expect(RTCDataChannelState.open.value, equals('open'));
      expect(RTCDataChannelState.closing.value, equals('closing'));
      expect(RTCDataChannelState.closed.value, equals('closed'));
    });
  });

  group('RTCStatsReport with extended stats', () {
    test('can contain mixed stats types', () {
      final report = RTCStatsReport([
        RTCPeerConnectionStats(
          timestamp: 1234567890.0,
          id: 'pc-stats',
          dataChannelsOpened: 2,
        ),
        RTCIceCandidateStats(
          timestamp: 1234567890.0,
          id: 'local-1',
          isRemote: false,
          address: '192.168.1.100',
          port: 54321,
          protocol: 'udp',
          candidateType: 'host',
        ),
        RTCIceCandidateStats(
          timestamp: 1234567890.0,
          id: 'remote-1',
          isRemote: true,
          address: '10.0.0.1',
          port: 12345,
          protocol: 'udp',
          candidateType: 'srflx',
        ),
        RTCIceCandidatePairStats(
          timestamp: 1234567890.0,
          id: 'pair-1',
          localCandidateId: 'local-1',
          remoteCandidateId: 'remote-1',
          state: RTCStatsIceCandidatePairState.succeeded,
          nominated: true,
        ),
        RTCTransportStats(
          timestamp: 1234567890.0,
          id: 'transport-1',
          iceState: RTCIceTransportState.completed,
          dtlsState: RTCDtlsTransportState.connected,
        ),
        RTCDataChannelStats(
          timestamp: 1234567890.0,
          id: 'dc-1',
          label: 'chat',
          state: RTCDataChannelState.open,
        ),
      ]);

      expect(report.length, equals(6));
      expect(report['pc-stats'], isA<RTCPeerConnectionStats>());
      expect(report['local-1'], isA<RTCIceCandidateStats>());
      expect(report['pair-1'], isA<RTCIceCandidatePairStats>());
      expect(report['transport-1'], isA<RTCTransportStats>());
      expect(report['dc-1'], isA<RTCDataChannelStats>());
    });

    test('can filter by stats type', () {
      final report = RTCStatsReport([
        RTCIceCandidateStats(
          timestamp: 1234567890.0,
          id: 'local-1',
          isRemote: false,
          candidateType: 'host',
        ),
        RTCIceCandidateStats(
          timestamp: 1234567890.0,
          id: 'local-2',
          isRemote: false,
          candidateType: 'srflx',
        ),
        RTCIceCandidateStats(
          timestamp: 1234567890.0,
          id: 'remote-1',
          isRemote: true,
          candidateType: 'host',
        ),
        RTCTransportStats(
          timestamp: 1234567890.0,
          id: 'transport-1',
        ),
      ]);

      final localCandidates = report.values
          .whereType<RTCIceCandidateStats>()
          .where((s) => !s.isRemote)
          .toList();

      expect(localCandidates.length, equals(2));

      final remoteCandidates = report.values
          .whereType<RTCIceCandidateStats>()
          .where((s) => s.isRemote)
          .toList();

      expect(remoteCandidates.length, equals(1));

      final transports = report.values.whereType<RTCTransportStats>().toList();
      expect(transports.length, equals(1));
    });
  });
}
