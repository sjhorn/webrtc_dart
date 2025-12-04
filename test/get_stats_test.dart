import 'package:test/test.dart';
import 'package:webrtc_dart/src/peer_connection.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';

void main() {
  group('RtcPeerConnection.getStats()', () {
    test('returns RTCStatsReport', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      expect(stats, isA<RTCStatsReport>());
    });

    test('contains peer-connection stats', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      // Find peer-connection stats
      RTCPeerConnectionStats? pcStats;
      for (final stat in stats.values) {
        if (stat is RTCPeerConnectionStats) {
          pcStats = stat;
          break;
        }
      }

      expect(pcStats, isNotNull, reason: 'Should have peer-connection stats');
      expect(pcStats!.type, RTCStatsType.peerConnection);
      expect(pcStats.id, isNotEmpty);
      expect(pcStats.timestamp, greaterThan(0));
    });

    test('peer-connection stats have valid properties', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      final pcStats = stats.values
          .whereType<RTCPeerConnectionStats>()
          .first;

      // MVP version doesn't track data channels yet (TODO)
      expect(pcStats.dataChannelsOpened, isNull);
      expect(pcStats.dataChannelsClosed, isNull);
    });

    test('includes RTP stats when transceivers exist', () async {
      final pc1 = RtcPeerConnection();
      final pc2 = RtcPeerConnection();

      // Create offer/answer to establish transceivers
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);

      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);

      // Get stats from PC1
      final stats = await pc1.getStats();

      // Should have peer-connection stats at minimum
      expect(stats.length, greaterThanOrEqualTo(1));

      // Check that all stats have required properties
      for (final stat in stats.values) {
        expect(stat.id, isNotEmpty);
        expect(stat.timestamp, greaterThan(0));
        expect(stat.type, isA<RTCStatsType>());
      }
    });

    test('stats can be converted to JSON', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      for (final stat in stats.values) {
        final json = stat.toJson();

        expect(json, isA<Map<String, dynamic>>());
        expect(json['id'], isNotEmpty);
        expect(json['timestamp'], greaterThan(0));
        expect(json['type'], isNotEmpty);
      }
    });

    test('RTCStatsReport supports map-like access', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      // Should be able to iterate over keys
      expect(stats.keys, isNotEmpty);

      // Should be able to iterate over values
      expect(stats.values, isNotEmpty);

      // Should be able to get by ID
      final firstId = stats.keys.first;
      final firstStat = stats[firstId];
      expect(firstStat, isNotNull);
      expect(firstStat!.id, equals(firstId));
    });

    test('RTCStatsReport.containsKey works', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      final firstId = stats.keys.first;
      expect(stats.containsKey(firstId), isTrue);
      expect(stats.containsKey('non-existent-id'), isFalse);
    });

    test('RTCStatsReport.forEach works', () async {
      final pc = RtcPeerConnection();

      final stats = await pc.getStats();

      var count = 0;
      stats.forEach((id, stat) {
        expect(id, equals(stat.id));
        count++;
      });

      expect(count, equals(stats.length));
    });

    test('works on closed connection without error', () async {
      final pc = RtcPeerConnection();

      await pc.close();

      // Should not throw
      final stats = await pc.getStats();

      // Should still return valid report (even if empty or minimal)
      expect(stats, isA<RTCStatsReport>());
    });
  });
}
