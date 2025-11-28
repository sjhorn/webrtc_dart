import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/rtp/rtp_statistics.dart';
import 'package:webrtc_dart/src/rtp/rtcp_reports.dart';

/// RTP Session
/// Manages RTP/RTCP streams with encryption and statistics tracking
class RtpSession {
  /// Local SSRC
  final int localSsrc;

  /// SRTP session for encryption/decryption
  SrtpSession? srtpSession;

  /// Sender statistics
  final RtpSenderStatistics senderStats;

  /// Receiver statistics by SSRC
  final Map<int, RtpStatistics> _receiverStats = {};

  /// RTCP report interval (milliseconds)
  final int rtcpIntervalMs;

  /// Timer for RTCP reports
  Timer? _rtcpTimer;

  /// Callback for sending RTCP packets
  final Future<void> Function(Uint8List rtcpPacket)? onSendRtcp;

  /// Callback for sending RTP packets
  final Future<void> Function(Uint8List rtpPacket)? onSendRtp;

  /// Callback for received RTP packets
  final void Function(RtpPacket packet)? onReceiveRtp;

  /// Last SR send time (NTP format)
  int? _lastSrSendTime;

  RtpSession({
    required this.localSsrc,
    this.srtpSession,
    this.rtcpIntervalMs = 5000,
    this.onSendRtcp,
    this.onSendRtp,
    this.onReceiveRtp,
  }) : senderStats = RtpSenderStatistics(ssrc: localSsrc);

  /// Start the session
  void start() {
    // Schedule periodic RTCP reports
    _rtcpTimer?.cancel();
    _rtcpTimer = Timer.periodic(
      Duration(milliseconds: rtcpIntervalMs),
      (_) => _sendRtcpReports(),
    );
  }

  /// Stop the session
  void stop() {
    _rtcpTimer?.cancel();
    _rtcpTimer = null;
  }

  /// Send RTP packet
  Future<void> sendRtp({
    required int payloadType,
    required Uint8List payload,
    required int timestampIncrement,
    bool marker = false,
  }) async {
    // Create RTP packet
    final packet = RtpPacket(
      payloadType: payloadType,
      sequenceNumber: senderStats.getNextSequence(),
      timestamp: senderStats.getNextTimestamp(timestampIncrement),
      ssrc: localSsrc,
      marker: marker,
      payload: payload,
    );

    // Update statistics
    senderStats.updateSent(payloadSize: payload.length);

    // Encrypt if SRTP is enabled
    final Uint8List data;
    if (srtpSession != null) {
      data = await srtpSession!.encryptRtp(packet);
    } else {
      data = packet.serialize();
    }

    // Send packet
    if (onSendRtp != null) {
      await onSendRtp!(data);
    }
  }

  /// Receive RTP/SRTP packet
  Future<void> receiveRtp(Uint8List data) async {
    // Decrypt if SRTP is enabled
    final RtpPacket packet;
    if (srtpSession != null) {
      packet = await srtpSession!.decryptSrtp(data);
    } else {
      packet = RtpPacket.parse(data);
    }

    // Get or create statistics for this SSRC
    final stats = _receiverStats.putIfAbsent(
      packet.ssrc,
      () => RtpStatistics(ssrc: packet.ssrc),
    );

    // Update statistics
    final arrivalTime = DateTime.now().millisecondsSinceEpoch;
    stats.updateReceived(
      sequenceNumber: packet.sequenceNumber,
      timestamp: packet.timestamp,
      payloadSize: packet.payload.length,
      arrivalTime: arrivalTime,
    );

    // Notify callback
    if (onReceiveRtp != null) {
      onReceiveRtp!(packet);
    }
  }

  /// Receive RTCP/SRTCP packet
  Future<void> receiveRtcp(Uint8List data) async {
    // Decrypt if SRTCP is enabled
    final RtcpPacket packet;
    if (srtpSession != null) {
      packet = await srtpSession!.decryptSrtcp(data);
    } else {
      packet = RtcpPacket.parse(data);
    }

    // Handle different RTCP packet types
    _handleRtcpPacket(packet);
  }

  /// Send RTCP reports
  Future<void> _sendRtcpReports() async {
    if (onSendRtcp == null) return;

    // Determine if we should send SR or RR
    final bool hasSentPackets = senderStats.packetsSent > 0;

    if (hasSentPackets) {
      // Send Sender Report
      await _sendSenderReport();
    } else {
      // Send Receiver Report
      await _sendReceiverReport();
    }
  }

  /// Send RTCP Sender Report
  Future<void> _sendSenderReport() async {
    if (onSendRtcp == null) return;

    // Generate NTP timestamp
    final ntpTimestamp = _generateNtpTimestamp();

    // Get RTP timestamp (using current timestamp from sender stats)
    final rtpTimestamp = senderStats.timestamp;

    // Create reception reports for all received streams
    final receptionReports = _createReceptionReports();

    // Create SR
    final sr = RtcpSenderReport(
      ssrc: localSsrc,
      ntpTimestamp: ntpTimestamp,
      rtpTimestamp: rtpTimestamp,
      packetCount: senderStats.packetsSent,
      octetCount: senderStats.bytesSent,
      receptionReports: receptionReports,
    );

    // Update last SR send time
    _lastSrSendTime = ntpTimestamp;
    senderStats.updateWithSentSr(ntpTimestamp: ntpTimestamp);

    // Convert to RTCP packet
    final packet = sr.toPacket();

    // Encrypt if SRTCP is enabled
    final Uint8List data;
    if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(packet);
    } else {
      data = packet.serialize();
    }

    // Send
    await onSendRtcp!(data);
  }

  /// Send RTCP Receiver Report
  Future<void> _sendReceiverReport() async {
    if (onSendRtcp == null) return;

    // Create reception reports for all received streams
    final receptionReports = _createReceptionReports();

    // Create RR
    final rr = RtcpReceiverReport(
      ssrc: localSsrc,
      receptionReports: receptionReports,
    );

    // Convert to RTCP packet
    final packet = rr.toPacket();

    // Encrypt if SRTCP is enabled
    final Uint8List data;
    if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(packet);
    } else {
      data = packet.serialize();
    }

    // Send
    await onSendRtcp!(data);
  }

  /// Create reception report blocks for all received streams
  List<RtcpReceptionReportBlock> _createReceptionReports() {
    final reports = <RtcpReceptionReportBlock>[];
    final currentTime = DateTime.now().millisecondsSinceEpoch;

    for (final stats in _receiverStats.values) {
      // Calculate extended highest sequence
      final extendedHighest = (stats.cycles << 16) | stats.highestSequence;

      // Calculate DLSR
      final dlsr = stats.calculateDlsr(currentTime);

      // Get last SR timestamp (middle 32 bits of NTP)
      final lastSr = stats.lastSrTimestamp != null
          ? ((stats.lastSrTimestamp! >> 16) & 0xFFFFFFFF)
          : 0;

      reports.add(RtcpReceptionReportBlock(
        ssrc: stats.ssrc,
        fractionLost: stats.lossFraction,
        cumulativeLost: stats.lostPackets,
        extendedHighestSequence: extendedHighest,
        jitter: stats.jitter.floor(),
        lastSr: lastSr,
        delaySinceLastSr: dlsr,
      ));
    }

    return reports;
  }

  /// Handle received RTCP packet
  void _handleRtcpPacket(RtcpPacket packet) {
    switch (packet.packetType) {
      case RtcpPacketType.senderReport:
        _handleSenderReport(packet);
        break;
      case RtcpPacketType.receiverReport:
        _handleReceiverReport(packet);
        break;
      case RtcpPacketType.sourceDescription:
      case RtcpPacketType.goodbye:
      case RtcpPacketType.applicationDefined:
      case RtcpPacketType.transportFeedback:
      case RtcpPacketType.payloadFeedback:
        // TODO: Implement other RTCP packet types
        break;
    }
  }

  /// Handle received Sender Report
  void _handleSenderReport(RtcpPacket packet) {
    try {
      final sr = RtcpSenderReport.fromPacket(packet);
      final receiveTime = DateTime.now().millisecondsSinceEpoch;

      // Update statistics for this sender
      final stats = _receiverStats[sr.ssrc];
      if (stats != null) {
        stats.updateWithSenderReport(
          ntpTimestamp: sr.ntpTimestamp,
          rtpTimestamp: sr.rtpTimestamp,
          packetCount: sr.packetCount,
          octetCount: sr.octetCount,
          receiveTime: receiveTime,
        );
      }

      // Process reception reports (feedback about our sending)
      for (final report in sr.receptionReports) {
        if (report.ssrc == localSsrc) {
          // This is feedback about our stream
          _handleReceptionReport(report);
        }
      }
    } catch (e) {
      // Invalid SR packet, ignore
    }
  }

  /// Handle received Receiver Report
  void _handleReceiverReport(RtcpPacket packet) {
    try {
      final rr = RtcpReceiverReport.fromPacket(packet);

      // Process reception reports (feedback about our sending)
      for (final report in rr.receptionReports) {
        if (report.ssrc == localSsrc) {
          // This is feedback about our stream
          _handleReceptionReport(report);
        }
      }
    } catch (e) {
      // Invalid RR packet, ignore
    }
  }

  /// Handle reception report about our stream
  void _handleReceptionReport(RtcpReceptionReportBlock report) {
    // TODO: Process feedback about our sending
    // - Packet loss rate
    // - Jitter
    // - Round-trip time calculation using LSR/DLSR
    // This can be used for congestion control and quality monitoring
  }

  /// Generate NTP timestamp (64-bit)
  /// Returns milliseconds since NTP epoch (Jan 1, 1900)
  int _generateNtpTimestamp() {
    final now = DateTime.now();

    // NTP epoch is Jan 1, 1900
    // Unix epoch is Jan 1, 1970
    // Difference is 70 years = 2208988800 seconds
    const ntpEpochOffset = 2208988800;

    final unixSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final ntpSeconds = unixSeconds + ntpEpochOffset;

    // Get fractional part (milliseconds -> fraction of second)
    final millis = now.millisecondsSinceEpoch % 1000;
    final fraction = (millis * 0x100000000 / 1000).floor();

    // Combine into 64-bit timestamp
    return (ntpSeconds << 32) | fraction;
  }

  /// Get statistics for a received stream
  RtpStatistics? getReceiverStatistics(int ssrc) {
    return _receiverStats[ssrc];
  }

  /// Get all receiver statistics
  Map<int, RtpStatistics> getAllReceiverStatistics() {
    return Map.unmodifiable(_receiverStats);
  }

  /// Get sender statistics
  RtpSenderStatistics getSenderStatistics() {
    return senderStats;
  }

  /// Reset session statistics
  void reset() {
    senderStats.reset();
    _receiverStats.clear();
    _lastSrSendTime = null;
  }

  /// Dispose resources
  void dispose() {
    stop();
    reset();
  }

  @override
  String toString() {
    return 'RtpSession(ssrc=0x${localSsrc.toRadixString(16)}, sent=${senderStats.packetsSent}, receivers=${_receiverStats.length})';
  }
}
