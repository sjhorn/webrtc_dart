import 'package:test/test.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';

void main() {
  double now() => DateTime.now().millisecondsSinceEpoch.toDouble();

  group('RTCStatsType', () {
    test('enum values have correct string values', () {
      expect(RTCStatsType.codec.value, equals('codec'));
      expect(RTCStatsType.inboundRtp.value, equals('inbound-rtp'));
      expect(RTCStatsType.outboundRtp.value, equals('outbound-rtp'));
      expect(RTCStatsType.remoteInboundRtp.value, equals('remote-inbound-rtp'));
      expect(
          RTCStatsType.remoteOutboundRtp.value, equals('remote-outbound-rtp'));
      expect(RTCStatsType.mediaSource.value, equals('media-source'));
      expect(RTCStatsType.peerConnection.value, equals('peer-connection'));
      expect(RTCStatsType.dataChannel.value, equals('data-channel'));
      expect(RTCStatsType.transport.value, equals('transport'));
      expect(RTCStatsType.candidatePair.value, equals('candidate-pair'));
      expect(RTCStatsType.localCandidate.value, equals('local-candidate'));
      expect(RTCStatsType.remoteCandidate.value, equals('remote-candidate'));
      expect(RTCStatsType.certificate.value, equals('certificate'));
    });

    test('toString returns value', () {
      expect(RTCStatsType.codec.toString(), equals('codec'));
      expect(RTCStatsType.inboundRtp.toString(), equals('inbound-rtp'));
    });
  });

  group('RTCStatsReport', () {
    test('construction with no stats', () {
      final report = RTCStatsReport();
      expect(report.length, equals(0));
      expect(report.values.isEmpty, isTrue);
      expect(report.keys.isEmpty, isTrue);
    });

    test('construction with stats list', () {
      final stats = RTCPeerConnectionStats(
        timestamp: now(),
        id: 'pc-1',
      );
      final report = RTCStatsReport([stats]);
      expect(report.length, equals(1));
      expect(report['pc-1'], equals(stats));
    });

    test('operator[] returns stats by ID', () {
      final stats = RTCPeerConnectionStats(timestamp: now(), id: 'pc-1');
      final report = RTCStatsReport([stats]);
      expect(report['pc-1'], equals(stats));
      expect(report['nonexistent'], isNull);
    });

    test('containsKey returns correct result', () {
      final stats = RTCPeerConnectionStats(timestamp: now(), id: 'pc-1');
      final report = RTCStatsReport([stats]);
      expect(report.containsKey('pc-1'), isTrue);
      expect(report.containsKey('nonexistent'), isFalse);
    });

    test('forEach iterates over all stats', () {
      final stats1 = RTCPeerConnectionStats(timestamp: now(), id: 'pc-1');
      final stats2 = RTCPeerConnectionStats(timestamp: now(), id: 'pc-2');
      final report = RTCStatsReport([stats1, stats2]);

      final ids = <String>[];
      report.forEach((id, stats) => ids.add(id));
      expect(ids, containsAll(['pc-1', 'pc-2']));
    });

    test('toString returns readable format', () {
      final stats = RTCPeerConnectionStats(timestamp: now(), id: 'pc-1');
      final report = RTCStatsReport([stats]);
      expect(report.toString(), contains('1 stats'));
    });
  });

  group('generateStatsId', () {
    test('returns type when no parts', () {
      expect(generateStatsId('transport'), equals('transport'));
      expect(generateStatsId('transport', null), equals('transport'));
      expect(generateStatsId('transport', []), equals('transport'));
    });

    test('joins parts with underscores', () {
      expect(generateStatsId('transport', ['1']), equals('transport_1'));
      expect(generateStatsId('transport', ['1', '2']), equals('transport_1_2'));
    });

    test('filters out null parts', () {
      expect(generateStatsId('transport', [null, '1', null, '2']),
          equals('transport_1_2'));
    });

    test('converts parts to strings', () {
      expect(generateStatsId('transport', [123, 'abc']),
          equals('transport_123_abc'));
    });
  });

  group('getStatsTimestamp', () {
    test('returns current timestamp as double', () {
      final before = DateTime.now().millisecondsSinceEpoch.toDouble();
      final timestamp = getStatsTimestamp();
      final after = DateTime.now().millisecondsSinceEpoch.toDouble();

      expect(timestamp, greaterThanOrEqualTo(before));
      expect(timestamp, lessThanOrEqualTo(after));
      expect(timestamp, isA<double>());
    });
  });

  group('RTCPeerConnectionStats', () {
    test('construction with required values', () {
      final timestamp = now();
      final stats = RTCPeerConnectionStats(
        timestamp: timestamp,
        id: 'pc-1',
      );

      expect(stats.timestamp, equals(timestamp));
      expect(stats.id, equals('pc-1'));
      expect(stats.type, equals(RTCStatsType.peerConnection));
      expect(stats.dataChannelsOpened, isNull);
      expect(stats.dataChannelsClosed, isNull);
    });

    test('construction with all values', () {
      final stats = RTCPeerConnectionStats(
        timestamp: now(),
        id: 'pc-1',
        dataChannelsOpened: 5,
        dataChannelsClosed: 2,
      );

      expect(stats.dataChannelsOpened, equals(5));
      expect(stats.dataChannelsClosed, equals(2));
    });

    test('toJson includes all values', () {
      final timestamp = now();
      final stats = RTCPeerConnectionStats(
        timestamp: timestamp,
        id: 'pc-1',
        dataChannelsOpened: 5,
        dataChannelsClosed: 2,
      );

      final json = stats.toJson();
      expect(json['timestamp'], equals(timestamp));
      expect(json['id'], equals('pc-1'));
      expect(json['type'], equals('peer-connection'));
      expect(json['dataChannelsOpened'], equals(5));
      expect(json['dataChannelsClosed'], equals(2));
    });

    test('toJson omits null values', () {
      final stats = RTCPeerConnectionStats(
        timestamp: now(),
        id: 'pc-1',
      );

      final json = stats.toJson();
      expect(json.containsKey('dataChannelsOpened'), isFalse);
      expect(json.containsKey('dataChannelsClosed'), isFalse);
    });

    test('toString returns readable format', () {
      final stats = RTCPeerConnectionStats(
        timestamp: now(),
        id: 'pc-1',
      );

      final str = stats.toString();
      expect(str, contains('pc-1'));
      expect(str, contains('peer-connection'));
    });
  });
}
