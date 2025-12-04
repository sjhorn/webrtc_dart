/// NtpTime Processor - NTP/RTP timestamp correlation
///
/// Correlates RTP timestamps with NTP time from RTCP Sender Reports
/// to provide wall-clock time for media frames.
///
/// Ported from werift-webrtc ntpTime.ts
library;

import 'dart:math';

import 'dart:typed_data';

import '../../srtp/rtp_packet.dart';
import '../../srtp/rtcp_packet.dart';
import 'interface.dart';

/// Maximum 32-bit unsigned integer value
const int _max32Uint = 0xFFFFFFFF;

/// Convert NTP timestamp (64-bit) to seconds
///
/// NTP timestamp format:
/// - Upper 32 bits: seconds since 1900
/// - Lower 32 bits: fractional seconds
double _ntpTime2Sec(int ntpTimestamp) {
  final seconds = (ntpTimestamp >> 32) & 0xFFFFFFFF;
  final fraction = ntpTimestamp & 0xFFFFFFFF;
  return seconds + fraction / 4294967296.0;
}

/// Input for NTP time processor
class NtpTimeInput {
  /// RTP packet to process
  final RtpPacket? rtp;

  /// RTCP packet (for Sender Reports)
  final RtcpPacket? rtcp;

  /// End of life signal
  final bool eol;

  NtpTimeInput({this.rtp, this.rtcp, this.eol = false});
}

/// Output from NTP time processor
class NtpTimeOutput {
  /// Original RTP packet
  final RtpPacket? rtp;

  /// Calculated time in milliseconds (wall-clock time)
  final int? timeMs;

  /// End of life signal
  final bool eol;

  NtpTimeOutput({this.rtp, this.timeMs, this.eol = false});
}

/// Generate a UUID v4 string
String _generateUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// NTP time processor for correlating RTP and wall-clock time
///
/// Uses RTCP Sender Reports to establish NTP/RTP timestamp mapping,
/// then calculates wall-clock time for each RTP packet.
class NtpTimeProcessor extends CallbackProcessor<NtpTimeInput, NtpTimeOutput> {
  /// Unique processor ID
  final String id = _generateUuid();

  /// Clock rate of the media stream
  final int clockRate;

  /// Base NTP timestamp from first SR
  int? _baseNtpTimestamp;

  /// Base RTP timestamp corresponding to base NTP
  int? _baseRtpTimestamp;

  /// Latest NTP timestamp from most recent SR
  int? _latestNtpTimestamp;

  /// Latest RTP timestamp from most recent SR
  int? _latestRtpTimestamp;

  /// Accumulated elapsed time offset
  double _currentElapsed = 0;

  /// Buffer for RTP packets waiting for SR
  List<RtpPacket> _buffer = [];

  /// Internal statistics
  final Map<String, dynamic> _internalStats = {};

  /// Whether we've received at least one SR
  bool started = false;

  /// Create NTP time processor with given clock rate
  NtpTimeProcessor({required this.clockRate});

  @override
  Map<String, dynamic> toJson() {
    return {
      ..._internalStats,
      'id': id,
      'baseRtpTimestamp': _baseRtpTimestamp,
      'latestRtpTimestamp': _latestRtpTimestamp,
      'baseNtpTimestamp':
          _baseNtpTimestamp != null ? _ntpTime2Sec(_baseNtpTimestamp!) : null,
      'latestNtpTimestamp': _latestNtpTimestamp != null
          ? _ntpTime2Sec(_latestNtpTimestamp!)
          : null,
      'bufferLength': _buffer.length,
      'currentElapsed': _currentElapsed,
      'clockRate': clockRate,
    };
  }

  void _stop() {
    _buffer = [];
    _internalStats.clear();
  }

  @override
  List<NtpTimeOutput> processInput(NtpTimeInput input) {
    if (input.eol) {
      _stop();
      return [NtpTimeOutput(eol: true)];
    }

    // Process RTCP Sender Report
    if (input.rtcp != null &&
        input.rtcp!.packetType == RtcpPacketType.senderReport) {
      // Parse SR payload: NTP timestamp (8 bytes) + RTP timestamp (4 bytes)
      // See RFC 3550 Section 6.4.1
      final payload = input.rtcp!.payload;
      if (payload.length >= 12) {
        final buffer = ByteData.sublistView(payload);
        // NTP timestamp: 8 bytes (upper 32 bits seconds, lower 32 bits fraction)
        final ntpHigh = buffer.getUint32(0);
        final ntpLow = buffer.getUint32(4);
        final ntpTimestamp = (ntpHigh << 32) | ntpLow;
        // RTP timestamp: 4 bytes
        final rtpTimestamp = buffer.getUint32(8);

        _latestNtpTimestamp = ntpTimestamp;
        _latestRtpTimestamp = rtpTimestamp;

        if (_baseNtpTimestamp == null) {
          _baseNtpTimestamp = ntpTimestamp;
          _baseRtpTimestamp = rtpTimestamp;
        }

        _internalStats['ntpReceived'] = DateTime.now().toIso8601String();
        started = true;
      }
    }

    // Process RTP packet
    if (input.rtp != null) {
      _buffer.add(input.rtp!);
      _internalStats['payloadType'] = input.rtp!.payloadType;

      final results = <NtpTimeOutput>[];

      // Can't calculate time without SR timestamps
      if (_baseRtpTimestamp == null ||
          _baseNtpTimestamp == null ||
          _latestNtpTimestamp == null ||
          _latestRtpTimestamp == null) {
        return [];
      }

      // Process buffered packets
      for (final rtp in _buffer) {
        final ntp = _updateNtp(rtp.timestamp);
        final ms = (ntp * 1000).round();
        results.add(NtpTimeOutput(rtp: rtp, timeMs: ms));

        _internalStats['timeSource'] =
            '${DateTime.now().toIso8601String()} time:$ms';
      }
      _buffer = [];
      return results;
    }

    return [];
  }

  /// Calculate NTP time for an RTP timestamp
  ({double ntp, double elapsedSec}) _calcNtp({
    required int rtpTimestamp,
    required int baseRtpTimestamp,
    required int baseNtpTimestamp,
    required double elapsedOffset,
  }) {
    // Handle RTP timestamp wraparound
    final rotate =
        (rtpTimestamp - baseRtpTimestamp).abs() > (_max32Uint / 4) * 3;

    final elapsed = rotate
        ? rtpTimestamp + _max32Uint - baseRtpTimestamp
        : rtpTimestamp - baseRtpTimestamp;
    final elapsedSec = elapsed / clockRate;

    // Calculate NTP time in seconds
    final ntp = _ntpTime2Sec(baseNtpTimestamp) + elapsedOffset + elapsedSec;
    return (ntp: ntp, elapsedSec: elapsedSec);
  }

  double _updateNtp(int rtpTimestamp) {
    _internalStats['inputRtp'] = rtpTimestamp;

    final base = _calcNtp(
      rtpTimestamp: rtpTimestamp,
      baseNtpTimestamp: _baseNtpTimestamp!,
      baseRtpTimestamp: _baseRtpTimestamp!,
      elapsedOffset: _currentElapsed,
    );

    final latest = _calcNtp(
      rtpTimestamp: rtpTimestamp,
      baseNtpTimestamp: _latestNtpTimestamp!,
      baseRtpTimestamp: _latestRtpTimestamp!,
      elapsedOffset: 0,
    );

    _internalStats['calcBaseNtp'] = base.ntp;
    _internalStats['calcLatestNtp'] = latest.ntp;

    if (base.ntp < latest.ntp) {
      // Update base to latest SR
      _baseNtpTimestamp = _latestNtpTimestamp;
      _baseRtpTimestamp = _latestRtpTimestamp;
      _currentElapsed = 0;
      _internalStats['calcNtp'] = latest.ntp;
      return latest.ntp;
    } else {
      _currentElapsed += base.elapsedSec;
      _baseRtpTimestamp = rtpTimestamp;
      _internalStats['calcNtp'] = base.ntp;
      return base.ntp;
    }
  }
}
