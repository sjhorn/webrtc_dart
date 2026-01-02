import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';

void main() {
  group('CandidatePair', () {
    late RTCIceCandidate localCandidate;
    late RTCIceCandidate remoteCandidate;

    setUp(() {
      localCandidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 54321,
        type: 'host',
      );

      remoteCandidate = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 12345,
        type: 'srflx',
      );
    });

    test('creates candidate pair', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      expect(pair.id, equals('test-id'));
      expect(pair.localCandidate, equals(localCandidate));
      expect(pair.remoteCandidate, equals(remoteCandidate));
      expect(pair.iceControlling, isTrue);
      expect(pair.state, equals(CandidatePairState.frozen));
      expect(pair.nominated, isFalse);
      expect(pair.remoteNominated, isFalse);
    });

    test('updates state', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      expect(pair.state, equals(CandidatePairState.frozen));

      pair.updateState(CandidatePairState.waiting);
      expect(pair.state, equals(CandidatePairState.waiting));

      pair.updateState(CandidatePairState.inProgress);
      expect(pair.state, equals(CandidatePairState.inProgress));

      pair.updateState(CandidatePairState.succeeded);
      expect(pair.state, equals(CandidatePairState.succeeded));
    });

    test('returns correct component', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      expect(pair.component, equals(1));
    });

    test('returns correct foundation', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      expect(pair.foundation, equals('1'));
    });

    test('returns correct remote address', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      final (host, port) = pair.remoteAddr;
      expect(host, equals('10.0.0.1'));
      expect(port, equals(12345));
    });

    test('computes priority correctly', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      final priority = pair.priority;
      expect(priority, greaterThan(0));
    });

    test('tracks statistics', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      expect(pair.stats.packetsSent, equals(0));
      expect(pair.stats.packetsReceived, equals(0));
      expect(pair.stats.bytesSent, equals(0));
      expect(pair.stats.bytesReceived, equals(0));

      pair.stats.packetsSent = 10;
      pair.stats.bytesSent = 1000;

      expect(pair.stats.packetsSent, equals(10));
      expect(pair.stats.bytesSent, equals(1000));
    });

    test('converts to JSON', () {
      final pair = CandidatePair(
        id: 'test-id',
        localCandidate: localCandidate,
        remoteCandidate: remoteCandidate,
        iceControlling: true,
      );

      pair.nominated = true;
      pair.stats.packetsSent = 10;

      final json = pair.toJson();

      expect(json['id'], equals('test-id'));
      expect(json['nominated'], isTrue);
      expect(json['state'], equals('frozen'));
      expect(json['stats']['packetsSent'], equals(10));
    });
  });

  group('candidatePairPriority', () {
    test('computes priority for controlling agent', () {
      final local = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      final remote = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 5678,
        type: 'srflx',
      );

      final priority = candidatePairPriority(local, remote, true);
      expect(priority, greaterThan(0));
    });

    test('computes priority for controlled agent', () {
      final local = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '192.168.1.1',
        port: 1234,
        type: 'srflx',
      );

      final remote = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '10.0.0.1',
        port: 5678,
        type: 'host',
      );

      final priority = candidatePairPriority(local, remote, false);
      expect(priority, greaterThan(0));
    });

    test('different roles produce different priorities', () {
      final local = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      final remote = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 5678,
        type: 'srflx',
      );

      final controllingPriority = candidatePairPriority(local, remote, true);
      final controlledPriority = candidatePairPriority(local, remote, false);

      expect(controllingPriority, isNot(equals(controlledPriority)));
    });

    test('higher priority candidates produce higher pair priorities', () {
      final highPriorityLocal = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431, // host
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      final lowPriorityLocal = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815, // srflx
        host: '192.168.1.2',
        port: 1235,
        type: 'srflx',
      );

      final remote = RTCIceCandidate(
        foundation: '3',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 5678,
        type: 'srflx',
      );

      final highPriority =
          candidatePairPriority(highPriorityLocal, remote, true);
      final lowPriority = candidatePairPriority(lowPriorityLocal, remote, true);

      expect(highPriority, greaterThan(lowPriority));
    });
  });

  group('sortCandidatePairs', () {
    test('sorts pairs by priority (highest first)', () {
      final local1 = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      final local2 = RTCIceCandidate(
        foundation: '2',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '192.168.1.2',
        port: 1235,
        type: 'srflx',
      );

      final remote = RTCIceCandidate(
        foundation: '3',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 5678,
        type: 'srflx',
      );

      final pair1 = CandidatePair(
        id: 'pair1',
        localCandidate: local1,
        remoteCandidate: remote,
        iceControlling: true,
      );

      final pair2 = CandidatePair(
        id: 'pair2',
        localCandidate: local2,
        remoteCandidate: remote,
        iceControlling: true,
      );

      final sorted = sortCandidatePairs([pair2, pair1]);

      expect(sorted[0].id, equals('pair1')); // Higher priority first
      expect(sorted[1].id, equals('pair2'));
    });

    test('handles empty list', () {
      final sorted = sortCandidatePairs([]);
      expect(sorted, isEmpty);
    });

    test('handles single pair', () {
      final pair = CandidatePair(
        id: 'pair1',
        localCandidate: RTCIceCandidate(
          foundation: '1',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '192.168.1.1',
          port: 1234,
          type: 'host',
        ),
        remoteCandidate: RTCIceCandidate(
          foundation: '2',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '10.0.0.1',
          port: 5678,
          type: 'host',
        ),
        iceControlling: true,
      );

      final sorted = sortCandidatePairs([pair]);
      expect(sorted, hasLength(1));
      expect(sorted[0], equals(pair));
    });
  });

  group('validateRemoteCandidate', () {
    test('accepts host candidate', () {
      final candidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      expect(() => validateRemoteCandidate(candidate), returnsNormally);
    });

    test('accepts srflx candidate', () {
      final candidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '10.0.0.1',
        port: 1234,
        type: 'srflx',
      );

      expect(() => validateRemoteCandidate(candidate), returnsNormally);
    });

    test('accepts relay candidate', () {
      final candidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '20.0.0.1',
        port: 1234,
        type: 'relay',
      );

      expect(() => validateRemoteCandidate(candidate), returnsNormally);
    });

    test('rejects prflx candidate', () {
      final candidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '10.0.0.1',
        port: 1234,
        type: 'prflx',
      );

      expect(() => validateRemoteCandidate(candidate), throwsArgumentError);
    });

    test('rejects unknown candidate type', () {
      final candidate = RTCIceCandidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '10.0.0.1',
        port: 1234,
        type: 'unknown',
      );

      expect(() => validateRemoteCandidate(candidate), throwsArgumentError);
    });
  });
}
