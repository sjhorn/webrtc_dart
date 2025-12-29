import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/rtcp/rtpfb/twcc.dart';

/// Extension info for tracking received packets
class _ExtensionInfo {
  /// Transport-wide sequence number
  final int tsn;

  /// Receive timestamp in microseconds
  final int timestamp;

  _ExtensionInfo({
    required this.tsn,
    required this.timestamp,
  });
}

/// Callback for sending RTCP packets
typedef OnSendRtcp = Future<void> Function(Uint8List rtcpPacket);

/// Receiver-side Transport-Wide Congestion Control
///
/// Matches werift-webrtc ReceiverTWCC class:
/// - Tracks incoming transport-wide sequence numbers with timestamps
/// - Periodically sends TWCC feedback to the sender
/// - Sends feedback when buffer exceeds threshold
///
/// Usage:
/// ```dart
/// final twcc = ReceiverTWCC(
///   rtcpSsrc: localSsrc,
///   mediaSourceSsrc: remoteSsrc,
///   onSendRtcp: (packet) => transport.sendRtcp(packet),
/// );
///
/// // Call when receiving RTP with transport-wide sequence number
/// twcc.handleTWCC(transportSequenceNumber);
///
/// // Start the feedback loop
/// twcc.start();
///
/// // Stop when done
/// twcc.stop();
/// ```
class ReceiverTWCC {
  /// SSRC for outgoing RTCP (receiver's SSRC)
  final int rtcpSsrc;

  /// SSRC of the media source (sender's SSRC)
  final int mediaSourceSsrc;

  /// Callback to send RTCP feedback
  final OnSendRtcp onSendRtcp;

  /// Extension info for received packets, keyed by transport sequence number
  final Map<int, _ExtensionInfo> _extensionInfo = {};

  /// Whether the TWCC feedback loop is running
  bool _running = false;

  /// Feedback packet count (8-bit, wraps at 256)
  int _fbPktCount = 0;

  /// Last timestamp for delta calculation
  int? _lastTimestamp;

  /// Timer for periodic feedback
  Timer? _timer;

  /// Interval between TWCC feedback packets (milliseconds)
  final int intervalMs;

  /// Threshold for sending feedback based on buffered packets
  final int bufferThreshold;

  ReceiverTWCC({
    required this.rtcpSsrc,
    required this.mediaSourceSsrc,
    required this.onSendRtcp,
    this.intervalMs = 100,
    this.bufferThreshold = 10,
  });

  /// Whether the TWCC feedback loop is running
  bool get isRunning => _running;

  /// Start the TWCC feedback loop
  void start() {
    if (_running) return;
    _running = true;
    _runTWCC();
  }

  /// Stop the TWCC feedback loop
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Handle incoming RTP packet with transport-wide sequence number
  ///
  /// Call this when receiving an RTP packet that has the transport-wide CC
  /// header extension. The sequence number should be extracted from the
  /// extension data.
  void handleTWCC(int transportSequenceNumber) {
    final now = DateTime.now().microsecondsSinceEpoch;

    _extensionInfo[transportSequenceNumber] = _ExtensionInfo(
      tsn: transportSequenceNumber,
      timestamp: now,
    );

    // Send immediately if buffer exceeds threshold
    if (_extensionInfo.length > bufferThreshold) {
      _sendTWCC();
    }
  }

  /// Run the TWCC feedback loop
  void _runTWCC() {
    if (!_running) return;

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_running) {
        _sendTWCC();
      }
    });
  }

  /// Send TWCC feedback packet
  void _sendTWCC() {
    if (_extensionInfo.isEmpty) return;

    // Sort by sequence number
    final extensionsArr = _extensionInfo.values.toList()
      ..sort((a, b) => a.tsn.compareTo(b.tsn));

    final minTSN = extensionsArr.first.tsn;
    final maxTSN = extensionsArr.last.tsn;

    final packetChunks = <RunLengthChunk>[];
    final baseSequenceNumber = extensionsArr.first.tsn;
    final packetStatusCount = (maxTSN - minTSN + 1) & 0xFFFF;

    int? referenceTime;
    _LastPacketStatus? lastPacketStatus;
    final recvDeltas = <RecvDelta>[];

    for (var i = minTSN; i <= maxTSN; i++) {
      final info = _extensionInfo[i];
      final timestamp = info?.timestamp;

      if (timestamp != null) {
        _lastTimestamp ??= timestamp;
        referenceTime ??= _lastTimestamp;

        final delta = timestamp - _lastTimestamp!;
        _lastTimestamp = timestamp;

        final recvDelta = RecvDelta(delta: delta);
        recvDelta.parseDelta();
        recvDeltas.add(recvDelta);

        // When status changed
        if (lastPacketStatus != null &&
            lastPacketStatus.status != recvDelta.type) {
          packetChunks.add(
            RunLengthChunk(
              packetStatus: lastPacketStatus.status,
              runLength: i - lastPacketStatus.minTSN,
            ),
          );
          lastPacketStatus = _LastPacketStatus(
            minTSN: i,
            status: recvDelta.type!,
          );
        }

        // Last status
        if (i == maxTSN) {
          if (lastPacketStatus != null) {
            packetChunks.add(
              RunLengthChunk(
                packetStatus: lastPacketStatus.status,
                runLength: i - lastPacketStatus.minTSN + 1,
              ),
            );
          } else {
            packetChunks.add(
              RunLengthChunk(
                packetStatus: recvDelta.type ?? PacketStatus.receivedSmallDelta,
                runLength: 1,
              ),
            );
          }
        }

        lastPacketStatus ??= _LastPacketStatus(
          minTSN: i,
          status: recvDelta.type!,
        );
      }
    }

    if (referenceTime == null) {
      return;
    }

    // Build the TWCC packet
    final twcc = TransportWideCC(
      senderSsrc: rtcpSsrc,
      mediaSourceSsrc: mediaSourceSsrc,
      baseSequenceNumber: baseSequenceNumber,
      packetStatusCount: packetStatusCount,
      // Reference time is in 64ms units (divide by 64000 to convert from µs)
      referenceTime: (referenceTime ~/ 64000) & 0xFFFFFF,
      fbPktCount: _fbPktCount,
      recvDeltas: recvDeltas,
      packetChunks: packetChunks,
    );

    // Serialize and send
    final rtcpPacket = twcc.serialize();
    onSendRtcp(rtcpPacket).catchError((_) {
      // Ignore send errors
    });

    // Clear buffer and increment counter
    _extensionInfo.clear();
    _fbPktCount = (_fbPktCount + 1) & 0xFF;
  }
}

/// Extension method to parse delta for RecvDelta
extension RecvDeltaParse on RecvDelta {
  /// Parse delta value for serialization
  void parseDelta() {
    final scaledDelta = delta ~/ 250;

    if (scaledDelta < 0 || scaledDelta > 255) {
      type = PacketStatus.receivedLargeDelta;
    } else {
      type = PacketStatus.receivedSmallDelta;
    }
  }
}

/// Helper class for tracking last packet status
class _LastPacketStatus {
  final int minTSN;
  final PacketStatus status;

  _LastPacketStatus({
    required this.minTSN,
    required this.status,
  });
}
