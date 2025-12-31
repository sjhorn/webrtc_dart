import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/rtcp/bye.dart';
import 'package:webrtc_dart/src/rtcp/nack.dart';
import 'package:webrtc_dart/src/rtcp/psfb/psfb.dart';
import 'package:webrtc_dart/src/rtcp/sdes.dart';
import 'package:webrtc_dart/src/rtp/header_extension.dart';
import 'package:webrtc_dart/src/rtp/nack_handler.dart';
import 'package:webrtc_dart/src/rtp/retransmission_buffer.dart';
import 'package:webrtc_dart/src/rtp/rtcp_reports.dart';
import 'package:webrtc_dart/src/rtp/rtp_statistics.dart';
import 'package:webrtc_dart/src/rtp/rtx.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';
import 'package:webrtc_dart/src/stats/rtp_stats.dart';

final _log = WebRtcLogging.rtp;

/// Configuration for header extension regeneration.
///
/// Used when forwarding RTP packets to regenerate header extensions with
/// fresh values (e.g., abs-send-time, transport-cc, mid).
/// Matches werift-webrtc rtpSender.ts:sendRtp header extension handling.
class HeaderExtensionConfig {
  /// Extension ID for abs-send-time (null if not negotiated)
  final int? absSendTimeId;

  /// Extension ID for transport-wide CC (null if not negotiated)
  final int? transportWideCCId;

  /// Extension ID for SDES MID (null if not negotiated)
  final int? sdesMidId;

  /// The media ID (mid) value to use for SDES MID extension
  final String? mid;

  const HeaderExtensionConfig({
    this.absSendTimeId,
    this.transportWideCCId,
    this.sdesMidId,
    this.mid,
  });

  /// Check if any extensions are configured
  bool get hasExtensions =>
      absSendTimeId != null || transportWideCCId != null || sdesMidId != null;
}

/// RTP Session
/// Manages RTP/RTCP streams with encryption and statistics tracking
class RtpSession {
  /// Local SSRC
  final int localSsrc;

  /// CNAME for RTCP SDES packets (Canonical Name)
  /// Per RFC 3550, CNAME should remain constant for a participant
  final String? cname;

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

  /// Callback for received RTCP BYE (goodbye) packets
  /// Called when a remote source signals it's leaving the session
  final void Function(RtcpBye bye)? onGoodbye;

  /// Retransmission buffer for sent packets
  final RetransmissionBuffer _retransmissionBuffer;

  /// NACK handler for packet loss detection
  NackHandler? _nackHandler;

  /// RTX handler for retransmission packets
  RtxHandler? _rtxHandler;

  /// Enable RTX (retransmission) support
  final bool rtxEnabled;

  /// Enable NACK (negative acknowledgement) support
  final bool nackEnabled;

  /// RTX payload type (if RTX is enabled)
  final int? rtxPayloadType;

  /// RTX SSRC (if RTX is enabled)
  final int? rtxSsrc;

  /// Map of RTX SSRC to original SSRC
  final Map<int, int> _rtxSsrcMap = {};

  /// Map of original payload type to RTX payload type
  final Map<int, int> _rtxPayloadTypeMap = {};

  /// Transport-wide sequence number counter for TWCC extensions.
  /// Matches werift-webrtc dtlsTransport.transportSequenceNumber.
  int _transportSequenceNumber = 0;

  /// Get the next transport-wide sequence number (with wrapping at 16-bit).
  int _nextTransportSequenceNumber() {
    _transportSequenceNumber = (_transportSequenceNumber + 1) & 0xFFFF;
    return _transportSequenceNumber;
  }

  /// Sequence number offset for forwarding packets.
  /// Matches werift rtpSender.ts seqOffset.
  int _seqOffset = 0;

  /// Timestamp offset for forwarding packets.
  /// Matches werift rtpSender.ts timestampOffset.
  int _timestampOffset = 0;

  /// Last sent sequence number (for calculating offsets).
  int? _lastSequenceNumber;

  /// Last sent timestamp (for calculating offsets).
  int? _lastTimestamp;

  /// Whether offsets have been initialized for forwarding.
  bool _offsetsInitialized = false;

  /// Initialize offsets for packet forwarding.
  /// This should be called when starting to forward packets from a new source.
  /// Matches werift replaceTrack offset calculation.
  void initializeForwardingOffsets(int firstSeqNum, int firstTimestamp) {
    if (_lastSequenceNumber != null && _lastTimestamp != null) {
      // Calculate offsets to continue from current position
      // seqOffset = (lastSeqNum + 1) - firstSeqNum
      _seqOffset = ((_lastSequenceNumber! + 1) - firstSeqNum) & 0xFFFF;
      _timestampOffset = (_lastTimestamp! - firstTimestamp) & 0xFFFFFFFF;
    } else {
      // First time, no offset needed but use random start for sequence number
      _seqOffset = 0;
      _timestampOffset = 0;
    }
    _offsetsInitialized = true;
  }

  /// Reset forwarding offsets (for new forwarding sessions).
  void resetForwardingOffsets() {
    _offsetsInitialized = false;
    _seqOffset = 0;
    _timestampOffset = 0;
  }

  RtpSession({
    required this.localSsrc,
    this.cname,
    this.srtpSession,
    this.rtcpIntervalMs = 5000,
    this.onSendRtcp,
    this.onSendRtp,
    this.onReceiveRtp,
    this.onGoodbye,
    this.rtxEnabled = false,
    this.nackEnabled = false,
    this.rtxPayloadType,
    this.rtxSsrc,
    int? retransmissionBufferSize,
  })  : senderStats = RtpSenderStatistics(ssrc: localSsrc),
        _retransmissionBuffer = RetransmissionBuffer(
          bufferSize: retransmissionBufferSize ??
              RetransmissionBuffer.defaultBufferSize,
        ) {
    // Initialize RTX handler if enabled
    if (rtxEnabled && rtxPayloadType != null && rtxSsrc != null) {
      _rtxHandler = RtxHandler(
        rtxPayloadType: rtxPayloadType!,
        rtxSsrc: rtxSsrc!,
      );
    }

    // Initialize NACK handler if enabled
    if (nackEnabled) {
      _nackHandler = NackHandler(
        senderSsrc: localSsrc,
        onSendNack: _sendNack,
        onPacketLost: (seqNum) {
          // Packet permanently lost, could log or emit event
        },
      );
    }
  }

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

    // Store in retransmission buffer
    _retransmissionBuffer.store(packet);

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

  /// Send a pre-formed RTP packet (for forwarding/relaying)
  /// This is useful for SFU scenarios where packets are forwarded without re-encoding
  ///
  /// Parameters:
  /// - [replaceSsrc]: If true (default), replaces packet SSRC with localSsrc
  /// - [payloadType]: If provided, overrides the packet's payload type with this value.
  ///   This is essential when forwarding RTP from an external source (e.g., Ring camera)
  ///   to a browser, as the browser expects the negotiated payload type.
  /// - [extensionConfig]: If provided, regenerates header extensions with fresh values.
  ///   This is critical for echo/loopback scenarios where browsers expect updated
  ///   abs-send-time and transport-cc values.
  ///
  /// Matches TypeScript werift rtpSender.ts:sendRtp behavior:
  /// - Rewrites SSRC to sender's SSRC
  /// - Rewrites payloadType to codec's payloadType
  /// - Regenerates header extensions (abs-send-time, transport-cc, mid)
  Future<void> sendRawRtpPacket(
    RtpPacket packet, {
    bool replaceSsrc = true,
    int? payloadType,
    HeaderExtensionConfig? extensionConfig,
    bool applyOffsets = true,
  }) async {
    // Guard: Only send if SRTP session is established (DTLS complete)
    // This matches TypeScript werift rtpSender.ts:sendRtp check:
    // if (this.dtlsTransport.state !== "connected" || !this.codec) return;
    if (srtpSession == null) {
      // DTLS not yet complete, drop packet - matching werift behavior
      return;
    }

    // Initialize forwarding offsets on first packet if not already done.
    // This matches werift's replaceTrack behavior where offsets are calculated
    // to ensure continuous sequence numbers when forwarding from a new source.
    if (applyOffsets && !_offsetsInitialized) {
      initializeForwardingOffsets(packet.sequenceNumber, packet.timestamp);
    }

    // Apply sequence number and timestamp offsets for continuous stream.
    // Matches werift rtpSender.ts:sendRtp:
    //   header.timestamp = uint32Add(header.timestamp, this.timestampOffset);
    //   header.sequenceNumber = uint16Add(header.sequenceNumber, this.seqOffset);
    final int adjustedSeqNum;
    final int adjustedTimestamp;
    if (applyOffsets) {
      adjustedSeqNum = (packet.sequenceNumber + _seqOffset) & 0xFFFF;
      adjustedTimestamp = (packet.timestamp + _timestampOffset) & 0xFFFFFFFF;
    } else {
      adjustedSeqNum = packet.sequenceNumber;
      adjustedTimestamp = packet.timestamp;
    }

    // Regenerate header extensions if config provided
    // Matches werift rtpSender.ts:sendRtp extension regeneration
    RtpExtension? newExtensionHeader = packet.extensionHeader;
    if (extensionConfig != null && extensionConfig.hasExtensions) {
      newExtensionHeader = _regenerateExtensions(
        packet.extensionHeader,
        extensionConfig,
      );
    }

    // Create modified packet with all adjustments
    final packetToSend = RtpPacket(
      version: packet.version,
      padding: packet.padding,
      extension: newExtensionHeader != null,
      marker: packet.marker,
      payloadType: payloadType ?? packet.payloadType,
      sequenceNumber: adjustedSeqNum,
      timestamp: adjustedTimestamp,
      ssrc: replaceSsrc ? localSsrc : packet.ssrc,
      csrcs: packet.csrcs,
      extensionHeader: newExtensionHeader,
      payload: packet.payload,
    );

    // Track last sent values for future offset calculations.
    // Matches werift: this.timestamp = header.timestamp; this.sequenceNumber = header.sequenceNumber;
    _lastSequenceNumber = adjustedSeqNum;
    _lastTimestamp = adjustedTimestamp;

    // Update statistics with the actual packet values being sent
    // This is critical for RTCP Sender Reports to report accurate timestamps
    senderStats.updateSent(
      payloadSize: packet.payload.length,
      timestamp: adjustedTimestamp,
      sequenceNumber: adjustedSeqNum,
    );

    // Encrypt with SRTP
    final data = await srtpSession!.encryptRtp(packetToSend);

    // Send packet
    if (onSendRtp != null) {
      await onSendRtp!(data);
    }
  }

  /// Regenerate header extensions for forwarded packets.
  ///
  /// This preserves original extensions and overwrites specific ones with
  /// fresh values for:
  /// - abs-send-time: current NTP timestamp
  /// - transport-cc: incrementing sequence number
  /// - sdes-mid: the configured MID value
  ///
  /// Matches werift rtpSender.ts:sendRtp header extension regeneration which
  /// preserves original extensions and merges regenerated ones.
  RtpExtension? _regenerateExtensions(
    RtpExtension? original,
    HeaderExtensionConfig config,
  ) {
    // Build map of extension ID -> payload
    // Start with original extensions to preserve them
    final extensionMap = <int, Uint8List>{};

    // Parse original extensions (one-byte header format 0xBEDE)
    if (original != null && original.profile == 0xBEDE) {
      final data = original.data;
      var offset = 0;
      while (offset < data.length) {
        final firstByte = data[offset];

        // Check for padding (0x00)
        if (firstByte == 0) {
          offset++;
          continue;
        }

        final id = (firstByte >> 4) & 0x0F;
        final length = (firstByte & 0x0F) + 1; // Length is L+1

        if (id == 0 || id == 15) {
          // Reserved values
          offset++;
          continue;
        }

        offset++; // Move past header byte

        if (offset + length > data.length) break;

        final payload = data.sublist(offset, offset + length);
        extensionMap[id] = payload;
        offset += length;
      }
    }

    // Override with regenerated extensions (fresh timing values)
    if (config.absSendTimeId != null) {
      final ntpTimestamp = ntpTime();
      extensionMap[config.absSendTimeId!] =
          serializeAbsSendTimeFromNtp(ntpTimestamp);
    }

    if (config.transportWideCCId != null) {
      final twccSeq = _nextTransportSequenceNumber();
      extensionMap[config.transportWideCCId!] = serializeTransportWideCC(twccSeq);
    }

    if (config.sdesMidId != null && config.mid != null) {
      extensionMap[config.sdesMidId!] = serializeSdesMid(config.mid!);
    }

    if (extensionMap.isEmpty) {
      return original;
    }

    // Sort by extension ID (like werift does)
    final sortedIds = extensionMap.keys.toList()..sort();

    // Build one-byte header extension format
    // Profile = 0xBEDE for one-byte headers
    final extensionData = <int>[];
    for (final id in sortedIds) {
      if (id < 1 || id > 14) continue;
      final payload = extensionMap[id]!;
      final length = payload.length;
      if (length < 1 || length > 16) continue;

      // One-byte header: ID (4 bits) + L (4 bits), where length = L + 1
      final header = (id << 4) | ((length - 1) & 0x0F);
      extensionData.add(header);
      extensionData.addAll(payload);
    }

    // Pad to 4-byte boundary
    while (extensionData.length % 4 != 0) {
      extensionData.add(0);
    }

    return RtpExtension(
      profile: 0xBEDE, // One-byte header profile
      data: Uint8List.fromList(extensionData),
    );
  }

  /// Receive RTP/SRTP packet
  Future<void> receiveRtp(Uint8List data) async {
    // Decrypt if SRTP is enabled
    RtpPacket packet;
    if (srtpSession != null) {
      packet = await srtpSession!.decryptSrtp(data);
    } else {
      packet = RtpPacket.parse(data);
    }

    // Check if this is an RTX packet and unwrap if needed
    // We can unwrap RTX packets if we have the SSRC mapping, regardless of
    // whether we're sending RTX ourselves (unwrapRtx is a static method)
    final originalSsrc = _rtxSsrcMap[packet.ssrc];
    if (originalSsrc != null) {
      // This is an RTX packet, unwrap it
      final originalPayloadType = _getOriginalPayloadType(packet.payloadType);
      if (originalPayloadType != null) {
        packet = RtxHandler.unwrapRtx(
          packet,
          originalPayloadType,
          originalSsrc,
        );
      }
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

    // Feed to NACK handler for loss detection
    if (nackEnabled && _nackHandler != null) {
      _nackHandler!.addPacket(packet);
    }

    // Notify callback
    if (onReceiveRtp != null) {
      onReceiveRtp!(packet);
    }
  }

  /// Receive RTCP/SRTCP packet
  /// [srtpSession] is optional - when provided, overrides this session's SRTP session
  /// (used for bundlePolicy:disable where each transport has its own SRTP session)
  Future<void> receiveRtcp(Uint8List data, {SrtpSession? srtpSession}) async {
    // Use provided SRTP session or fall back to this session's SRTP session
    final effectiveSrtpSession = srtpSession ?? this.srtpSession;

    // Decrypt if SRTCP is enabled
    final RtcpPacket packet;
    try {
      if (effectiveSrtpSession != null) {
        packet = await effectiveSrtpSession.decryptSrtcp(data);
      } else {
        packet = RtcpPacket.parse(data);
      }
    } on FormatException catch (e) {
      // Skip malformed RTCP packets
      _log.warning('Skipping malformed RTCP packet: $e');
      return;
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

  /// Send RTCP Sender Report (with SDES if cname is set)
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

    // Update sender statistics with SR send time
    senderStats.updateWithSentSr(ntpTimestamp: ntpTimestamp);

    // Build compound RTCP packet: SR + SDES (if cname is set)
    // Per RFC 3550, compound RTCP should include SR/RR + SDES
    final Uint8List data;
    if (cname != null && srtpSession != null) {
      // Create SDES packet with CNAME
      final sdes = RtcpSourceDescription.withCname(ssrc: localSsrc, cname: cname!);

      // Serialize compound: SR + SDES
      final srBytes = sr.toPacket().serialize();
      final sdesBytes = sdes.serialize();
      final compound = Uint8List(srBytes.length + sdesBytes.length);
      compound.setRange(0, srBytes.length, srBytes);
      compound.setRange(srBytes.length, compound.length, sdesBytes);

      // Encrypt compound packet
      data = await srtpSession!.encryptRtcpCompound(compound);
    } else if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(sr.toPacket());
    } else {
      data = sr.toPacket().serialize();
    }

    // Send
    await onSendRtcp!(data);
  }

  /// Send RTCP Receiver Report (with SDES if cname is set)
  Future<void> _sendReceiverReport() async {
    if (onSendRtcp == null) return;

    // Create reception reports for all received streams
    final receptionReports = _createReceptionReports();

    // Create RR
    final rr = RtcpReceiverReport(
      ssrc: localSsrc,
      receptionReports: receptionReports,
    );

    // Build compound RTCP packet: RR + SDES (if cname is set)
    // Per RFC 3550, compound RTCP should include SR/RR + SDES
    final Uint8List data;
    if (cname != null && srtpSession != null) {
      // Create SDES packet with CNAME
      final sdes = RtcpSourceDescription.withCname(ssrc: localSsrc, cname: cname!);

      // Serialize compound: RR + SDES
      final rrBytes = rr.toPacket().serialize();
      final sdesBytes = sdes.serialize();
      final compound = Uint8List(rrBytes.length + sdesBytes.length);
      compound.setRange(0, rrBytes.length, rrBytes);
      compound.setRange(rrBytes.length, compound.length, sdesBytes);

      // Encrypt compound packet
      data = await srtpSession!.encryptRtcpCompound(compound);
    } else if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(rr.toPacket());
    } else {
      data = rr.toPacket().serialize();
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
      case RtcpPacketType.transportFeedback:
        // Handle NACK (FMT=1)
        if (packet.reportCount == GenericNack.fmt) {
          _handleNack(packet);
        }
        break;
      case RtcpPacketType.sourceDescription:
        // SDES packets contain CNAME, NAME, etc. - not processed for now
        // werift also doesn't actively process these (informational only)
        break;
      case RtcpPacketType.goodbye:
        // BYE packets indicate peer is leaving
        _handleGoodbye(packet);
        break;
      case RtcpPacketType.applicationDefined:
        // APP packets are application-specific - not used in WebRTC
        break;
      case RtcpPacketType.payloadFeedback:
        // PSFB packets (PLI, FIR, etc.) handled by higher layer (RtpTransceiver)
        // werift routes these to onPictureLossIndication/onFir callbacks
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

  /// Handle received RTCP BYE packet
  void _handleGoodbye(RtcpPacket packet) {
    try {
      final bye = RtcpBye.fromPacket(packet);
      _log.fine('[RTP] Received BYE from SSRCs: ${bye.ssrcs}'
          '${bye.reason != null ? ", reason: ${bye.reason}" : ""}');

      // Invoke callback if registered
      onGoodbye?.call(bye);

      // Clean up receiver statistics for departing sources
      for (final ssrc in bye.ssrcs) {
        _receiverStats.remove(ssrc);
      }
    } catch (e) {
      _log.warning('[RTP] Failed to parse BYE packet: $e');
    }
  }

  /// Send RTCP BYE packet to signal leaving the session
  /// Optionally include a reason string
  Future<void> sendBye({String? reason}) async {
    final bye = RtcpBye.single(localSsrc, reason: reason);
    final packet = bye.toPacket();

    _log.fine('[RTP] Sending BYE for SSRC: $localSsrc'
        '${reason != null ? ", reason: $reason" : ""}');

    // Encrypt if SRTP is enabled
    Uint8List data;
    if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(packet);
    } else {
      data = packet.serialize();
    }
    await onSendRtcp?.call(data);
  }

  /// Handle reception report about our stream
  /// This provides feedback about how the remote peer is receiving our packets
  void _handleReceptionReport(RtcpReceptionReportBlock report) {
    // Reception report contains:
    // - report.fractionLost: packet loss in last interval (0-255, 255 = 100% loss)
    // - report.totalLost: cumulative packets lost
    // - report.highestSeqReceived: highest sequence number received
    // - report.jitter: interarrival jitter estimate
    // - report.lastSr: middle 32 bits of NTP timestamp from last SR
    // - report.delaySinceLastSr: time since last SR in 1/65536 seconds
    //
    // This data can be used for:
    // - Congestion control (adjust bitrate based on loss)
    // - RTT calculation: RTT = now - lastSr - delaySinceLastSr
    // - Quality monitoring and statistics
    //
    // werift exposes this via getStats() but doesn't implement congestion control
    // Full GCC implementation is a Phase 5 feature (beyond werift parity)
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

  /// Handle received NACK packet
  void _handleNack(RtcpPacket packet) async {
    try {
      final nack = GenericNack.deserialize(packet);

      // Retransmit requested packets
      for (final seqNum in nack.lostSeqNumbers) {
        final originalPacket = _retransmissionBuffer.retrieve(seqNum);

        if (originalPacket != null) {
          // Packet found in buffer, retransmit
          RtpPacket packetToSend;

          if (rtxEnabled && _rtxHandler != null) {
            // Wrap as RTX packet
            packetToSend = _rtxHandler!.wrapRtx(originalPacket);
          } else {
            // Resend original packet
            packetToSend = originalPacket;
          }

          // Encrypt if needed
          final Uint8List data;
          if (srtpSession != null) {
            data = await srtpSession!.encryptRtp(packetToSend);
          } else {
            data = packetToSend.serialize();
          }

          // Send retransmission
          if (onSendRtp != null) {
            await onSendRtp!(data);
          }
        }
      }
    } catch (e) {
      // Invalid NACK packet, ignore
    }
  }

  /// Send NACK packet
  Future<void> _sendNack(GenericNack nack) async {
    if (onSendRtcp == null) return;

    final packet = nack.toRtcpPacket();

    // Encrypt if SRTCP is enabled
    final Uint8List data;
    if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(packet);
    } else {
      data = packet.serialize();
    }

    await onSendRtcp!(data);
  }

  /// Send Picture Loss Indication (PLI) to request a keyframe
  ///
  /// [mediaSsrc] is the SSRC of the video stream to request a keyframe for.
  /// This is typically the remote sender's SSRC.
  Future<void> sendPli(int mediaSsrc) async {
    if (onSendRtcp == null) return;

    final psfb = PayloadSpecificFeedback.pli(
      senderSsrc: localSsrc,
      mediaSsrc: mediaSsrc,
    );
    final packet = psfb.toRtcpPacket();

    // Encrypt if SRTCP is enabled
    final Uint8List data;
    if (srtpSession != null) {
      data = await srtpSession!.encryptRtcp(packet);
    } else {
      data = packet.serialize();
    }

    await onSendRtcp!(data);
  }

  /// Get original payload type from RTX payload type
  int? _getOriginalPayloadType(int rtxPayloadType) {
    for (final entry in _rtxPayloadTypeMap.entries) {
      if (entry.value == rtxPayloadType) {
        return entry.key;
      }
    }
    return null;
  }

  /// Register RTX mapping
  /// Maps RTX SSRC and payload type to original stream
  void registerRtxMapping({
    required int originalSsrc,
    required int rtxSsrc,
    required int originalPayloadType,
    required int rtxPayloadType,
  }) {
    _rtxSsrcMap[rtxSsrc] = originalSsrc;
    _rtxPayloadTypeMap[originalPayloadType] = rtxPayloadType;
  }

  /// Get RTP statistics as RTCStatsReport
  RTCStatsReport getStats() {
    final stats = <RTCStats>[];
    final timestamp = getStatsTimestamp();

    // Add outbound RTP stats (sender)
    if (senderStats.packetsSent > 0) {
      final outboundId = generateStatsId('outbound-rtp', [localSsrc]);
      stats.add(RTCOutboundRtpStreamStats(
        timestamp: timestamp,
        id: outboundId,
        ssrc: localSsrc,
        packetsSent: senderStats.packetsSent,
        bytesSent: senderStats.bytesSent,
      ));
    }

    // Add inbound RTP stats (receivers)
    for (final entry in _receiverStats.entries) {
      final ssrc = entry.key;
      final receiverStats = entry.value;

      final inboundId = generateStatsId('inbound-rtp', [ssrc]);
      stats.add(RTCInboundRtpStreamStats(
        timestamp: timestamp,
        id: inboundId,
        ssrc: ssrc,
        packetsReceived: receiverStats.packetsReceived,
        packetsLost: receiverStats.lostPackets,
        jitter: receiverStats.jitter,
        bytesReceived: receiverStats.bytesReceived,
      ));
    }

    return RTCStatsReport(stats);
  }

  /// Reset session statistics
  void reset() {
    senderStats.reset();
    _receiverStats.clear();
    _retransmissionBuffer.clear();
  }

  /// Dispose resources
  void dispose() {
    stop();
    _nackHandler?.close();
    reset();
  }

  @override
  String toString() {
    return 'RtpSession(ssrc=0x${localSsrc.toRadixString(16)}, sent=${senderStats.packetsSent}, receivers=${_receiverStats.length})';
  }
}
