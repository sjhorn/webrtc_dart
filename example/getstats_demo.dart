/// getStats() Demonstration
///
/// This example shows how to use the getStats() method to collect
/// WebRTC statistics from a data channel connection.
///
/// Usage: dart run examples/getstats_demo.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

Future<void> main() async {
  print('=== RTCPeerConnection.getStats() Demo ===\n');

  // Create peer connections
  final pc1 = RtcPeerConnection();
  final pc2 = RtcPeerConnection();

  try {
    // 1. Basic getStats() call on new connection
    print('1. Basic getStats() on new connection:');
    final initialStats = await pc1.getStats();
    print('   Number of stats objects: ${initialStats.length}');

    for (final stat in initialStats.values) {
      print('   - ${stat.type}: ${stat.id}');
    }
    print('');

    // 2. Create data channel and check stats
    print('2. After creating data channel:');
    final dataChannel = pc1.createDataChannel(
      'demo',
      maxRetransmits: 3,
    );
    print('   DataChannel created: ${dataChannel.label}');

    final dcStats = await pc1.getStats();
    print('   Number of stats objects: ${dcStats.length}');

    // Look for peer-connection stats
    dcStats.forEach((id, stat) {
      if (stat.type == RTCStatsType.peerConnection) {
        final pcStat = stat as RTCPeerConnectionStats;
        print('   Data channels opened: ${pcStat.dataChannelsOpened ?? 0}');
        print('   Data channels closed: ${pcStat.dataChannelsClosed ?? 0}');
      }
    });
    print('');

    // 3. Add media track and check stats
    print('3. After adding media track:');
    final audioTrack = AudioStreamTrack(
      id: 'audio-demo',
      label: 'Demo Audio Track',
    );
    pc1.addTrack(audioTrack);

    final mediaStats = await pc1.getStats();
    print('   Number of stats objects: ${mediaStats.length}');

    // Check for media-source stats
    var mediaSourceCount = 0;
    mediaStats.forEach((id, stat) {
      if (stat.type == RTCStatsType.mediaSource) {
        mediaSourceCount++;
      }
    });
    print('   Media source stats found: $mediaSourceCount');
    print('');

    // 4. Track selector filtering
    print('4. getStats() with track selector:');
    final trackStats = await pc1.getStats(audioTrack);
    print('   Stats for audio track: ${trackStats.length} objects');

    for (final stat in trackStats.values) {
      print('   - ${stat.type}: ${stat.id}');
    }
    print('');

    // 5. Stats properties inspection
    print('5. Detailed stats inspection:');
    final detailedStats = await pc1.getStats();

    detailedStats.forEach((id, stat) {
      print('   ${stat.type} ($id):');
      print('     timestamp: ${stat.timestamp}');

      // Show type-specific properties
      if (stat.type == RTCStatsType.peerConnection) {
        final pcStat = stat as RTCPeerConnectionStats;
        print('     dataChannelsOpened: ${pcStat.dataChannelsOpened ?? 0}');
        print('     dataChannelsClosed: ${pcStat.dataChannelsClosed ?? 0}');
      } else if (stat.type == RTCStatsType.inboundRtp) {
        final rtpStat = stat as RTCInboundRtpStreamStats;
        print('     packetsReceived: ${rtpStat.packetsReceived}');
        print('     bytesReceived: ${rtpStat.bytesReceived}');
        print('     packetsLost: ${rtpStat.packetsLost}');
        print('     jitter: ${rtpStat.jitter}');
      } else if (stat.type == RTCStatsType.outboundRtp) {
        final rtpStat = stat as RTCOutboundRtpStreamStats;
        print('     packetsSent: ${rtpStat.packetsSent}');
        print('     bytesSent: ${rtpStat.bytesSent}');
      }
      print('');
    });

    // 6. Stats timing
    print('6. Stats timing consistency:');
    final stats1 = await pc1.getStats();
    await Future.delayed(Duration(milliseconds: 10));
    final stats2 = await pc1.getStats();

    if (stats1.length > 0 && stats2.length > 0) {
      final timestamp1 = stats1.values.first.timestamp;
      final timestamp2 = stats2.values.first.timestamp;

      print('   First call timestamp: $timestamp1');
      print('   Second call timestamp: $timestamp2');
      print(
          '   Time difference: ${(timestamp2 - timestamp1).toStringAsFixed(2)}ms');
    }
    print('');

    print('✅ getStats() demonstration completed successfully!');
  } catch (e, st) {
    print('❌ Error during getStats() demonstration: $e');
    print(st);
  } finally {
    // Clean up
    await pc1.close();
    await pc2.close();
  }
}
