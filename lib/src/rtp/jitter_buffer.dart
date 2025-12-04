import '../srtp/rtp_packet.dart';
import 'rtx.dart'; // for uint16Add, uint16Gt, uint16Lt

/// Output from jitter buffer processing
class JitterBufferOutput {
  /// The RTP packet (if available)
  final RtpPacket? rtp;

  /// End of stream indicator
  final bool eol;

  /// Packet loss range (if detected)
  final PacketLossRange? isPacketLost;

  const JitterBufferOutput({
    this.rtp,
    this.eol = false,
    this.isPacketLost,
  });
}

/// Represents a range of lost packets
class PacketLossRange {
  /// First lost sequence number
  final int from;

  /// Last lost sequence number (exclusive - up to but not including)
  final int to;

  const PacketLossRange({required this.from, required this.to});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PacketLossRange && from == other.from && to == other.to;

  @override
  int get hashCode => from.hashCode ^ to.hashCode;

  @override
  String toString() => 'PacketLossRange(from: $from, to: $to)';
}

/// Jitter buffer configuration options
class JitterBufferOptions {
  /// Maximum latency in milliseconds before considering packet lost
  final int latencyMs;

  /// Maximum number of packets to buffer
  final int bufferSize;

  const JitterBufferOptions({
    this.latencyMs = 200,
    this.bufferSize = 10000,
  });
}

/// Jitter buffer for reordering RTP packets
///
/// Handles out-of-order packet delivery by buffering packets and
/// releasing them in sequence order. Detects packet loss based on
/// timestamp-based timeout.
///
/// Ported from werift-webrtc JitterBufferBase
class JitterBuffer {
  /// Clock rate in Hz (e.g., 90000 for video, 48000 for audio)
  final int clockRate;

  /// Buffer options
  final JitterBufferOptions options;

  /// Current "present" sequence number - last sequence we output
  int? _presentSeqNum;

  /// Buffer of out-of-order packets keyed by sequence number
  final Map<int, RtpPacket> _rtpBuffer = {};

  /// Internal stats for debugging
  final Map<String, dynamic> _internalStats = {};

  JitterBuffer(
    this.clockRate, {
    JitterBufferOptions? options,
  }) : options = options ?? const JitterBufferOptions();

  /// Get expected next sequence number
  int get _expectNextSeqNum => uint16Add(_presentSeqNum!, 1);

  /// Get current buffer length
  int get bufferLength => _rtpBuffer.length;

  /// Get current present sequence number (for testing)
  int? get presentSeqNum => _presentSeqNum;

  /// Get stats as JSON-serializable map
  Map<String, dynamic> toJson() {
    return {
      ..._internalStats,
      'rtpBufferLength': _rtpBuffer.length,
      'presentSeqNum': _presentSeqNum,
      'expectNextSeqNum': _presentSeqNum != null ? _expectNextSeqNum : null,
    };
  }

  /// Clear the buffer
  void _stop() {
    _rtpBuffer.clear();
  }

  /// Process input (RTP packet or end-of-stream)
  ///
  /// Returns list of outputs (may be empty, single, or multiple packets)
  List<JitterBufferOutput> processInput({RtpPacket? rtp, bool eol = false}) {
    final output = <JitterBufferOutput>[];

    if (rtp == null) {
      if (eol) {
        // Flush all remaining buffered packets in order
        final packets = _sortAndClearBuffer(_rtpBuffer);
        for (final packet in packets) {
          output.add(JitterBufferOutput(rtp: packet));
        }
        output.add(const JitterBufferOutput(eol: true));
        _stop();
      }
      return output;
    }

    final result = _processRtp(rtp);

    if (result.timeoutSeqNum != null) {
      // Packet loss detected due to timeout
      final isPacketLost = PacketLossRange(
        from: _expectNextSeqNum,
        to: result.timeoutSeqNum!,
      );
      _presentSeqNum = rtp.sequenceNumber;
      output.add(JitterBufferOutput(isPacketLost: isPacketLost));

      if (result.packets != null) {
        for (final packet in [...result.packets!, rtp]) {
          output.add(JitterBufferOutput(rtp: packet));
        }
      }
      _internalStats['jitterBuffer'] = DateTime.now().toIso8601String();
      return output;
    } else {
      if (result.packets != null) {
        for (final packet in result.packets!) {
          output.add(JitterBufferOutput(rtp: packet));
        }
        _internalStats['jitterBuffer'] = DateTime.now().toIso8601String();
        return output;
      }
      return [];
    }
  }

  /// Process a single RTP packet
  _ProcessResult _processRtp(RtpPacket rtp) {
    final sequenceNumber = rtp.sequenceNumber;
    final timestamp = rtp.timestamp;

    // Initialize on first packet
    if (_presentSeqNum == null) {
      _presentSeqNum = sequenceNumber;
      return _ProcessResult(packets: [rtp]);
    }

    // Duplicate or old packet - discard
    if (_uint16Gte(_presentSeqNum!, sequenceNumber)) {
      _internalStats['duplicate'] = {
        'count': ((_internalStats['duplicate'] as Map?)?['count'] ?? 0) + 1,
        'sequenceNumber': sequenceNumber,
        'timestamp': DateTime.now().toIso8601String(),
      };
      return _ProcessResult(nothing: true);
    }

    // Expected next packet - output immediately
    if (sequenceNumber == _expectNextSeqNum) {
      _presentSeqNum = sequenceNumber;

      // Try to resolve any buffered packets that follow
      final rtpBuffer = _resolveBuffer(uint16Add(sequenceNumber, 1));
      if (rtpBuffer.isNotEmpty) {
        _presentSeqNum = rtpBuffer.last.sequenceNumber;
      }

      _disposeTimeoutPackets(timestamp);

      return _ProcessResult(packets: [rtp, ...rtpBuffer]);
    }

    // Out of order - buffer the packet
    _pushRtpBuffer(rtp);

    final disposeResult = _disposeTimeoutPackets(timestamp);

    if (disposeResult.latestTimeoutSeqNum != null) {
      return _ProcessResult(
        timeoutSeqNum: disposeResult.latestTimeoutSeqNum,
        packets: disposeResult.sorted,
      );
    } else {
      return _ProcessResult(nothing: true);
    }
  }

  /// Add packet to buffer (with overflow protection)
  void _pushRtpBuffer(RtpPacket rtp) {
    if (_rtpBuffer.length > options.bufferSize) {
      _internalStats['buffer_overflow'] = {
        'count':
            ((_internalStats['buffer_overflow'] as Map?)?['count'] ?? 0) + 1,
        'timestamp': DateTime.now().toIso8601String(),
      };
      return;
    }

    _rtpBuffer[rtp.sequenceNumber] = rtp;
  }

  /// Resolve consecutive packets from buffer starting at seqNumFrom
  List<RtpPacket> _resolveBuffer(int seqNumFrom) {
    final resolve = <RtpPacket>[];

    var index = seqNumFrom;
    while (true) {
      final rtp = _rtpBuffer[index];
      if (rtp != null) {
        resolve.add(rtp);
        _rtpBuffer.remove(index);
        index = uint16Add(index, 1);
      } else {
        break;
      }
    }

    return resolve;
  }

  /// Sort and clear buffer, returning packets in sequence order
  List<RtpPacket> _sortAndClearBuffer(Map<int, RtpPacket> rtpBuffer) {
    final buffer = <RtpPacket>[];
    var index = _presentSeqNum ?? 0;

    while (rtpBuffer.isNotEmpty) {
      final rtp = rtpBuffer[index];
      if (rtp != null) {
        buffer.add(rtp);
        rtpBuffer.remove(index);
      }
      index = uint16Add(index, 1);

      // Safety: prevent infinite loop if buffer is corrupted
      if (buffer.length > options.bufferSize) break;
    }

    return buffer;
  }

  /// Dispose packets that have timed out based on timestamp
  _DisposeResult _disposeTimeoutPackets(int baseTimestamp) {
    int? latestTimeoutSeqNum;

    final packets = <RtpPacket>[];

    for (final rtp in _rtpBuffer.values.toList()) {
      final timestamp = rtp.timestamp;
      final sequenceNumber = rtp.sequenceNumber;

      // Skip packets with future timestamps
      if (_uint32Gt(timestamp, baseTimestamp)) {
        continue;
      }

      // Calculate elapsed time
      final elapsedSec = _uint32Add(baseTimestamp, -timestamp) / clockRate;

      if (elapsedSec * 1000 > options.latencyMs) {
        _internalStats['timeout_packet'] = {
          'count':
              ((_internalStats['timeout_packet'] as Map?)?['count'] ?? 0) + 1,
          'at': DateTime.now().toIso8601String(),
          'sequenceNumber': sequenceNumber,
          'elapsedSec': elapsedSec,
          'baseTimestamp': baseTimestamp,
          'timestamp': timestamp,
        };

        latestTimeoutSeqNum ??= sequenceNumber;

        // Find the sequence number furthest from presentSeqNum
        // (the one with the largest gap)
        if (uint16Add(sequenceNumber, -_presentSeqNum!) >
            uint16Add(latestTimeoutSeqNum, -_presentSeqNum!)) {
          latestTimeoutSeqNum = sequenceNumber;
        }

        final packet = _rtpBuffer.remove(sequenceNumber);
        if (packet != null) {
          packets.add(packet);
        }
      }
    }

    // Sort the timed-out packets by sequence number
    final packetMap = <int, RtpPacket>{};
    for (final p in packets) {
      packetMap[p.sequenceNumber] = p;
    }
    final sorted = _sortAndClearBuffer(packetMap);

    return _DisposeResult(
      latestTimeoutSeqNum: latestTimeoutSeqNum,
      sorted: sorted,
    );
  }

  /// Uint16 greater-than-or-equal comparison with wraparound
  bool _uint16Gte(int a, int b) {
    return a == b || uint16Gt(a, b);
  }

  /// Uint32 greater-than comparison with wraparound
  bool _uint32Gt(int a, int b) {
    const halfMod = 0x80000000;
    return (a < b && b - a > halfMod) || (a > b && a - b < halfMod);
  }

  /// Uint32 addition with wraparound
  int _uint32Add(int a, int b) {
    return ((BigInt.from(a) + BigInt.from(b)) & BigInt.from(0xffffffff))
        .toInt();
  }
}

/// Internal result type for _processRtp
class _ProcessResult {
  final List<RtpPacket>? packets;
  final int? timeoutSeqNum;
  final bool nothing;

  _ProcessResult({
    this.packets,
    this.timeoutSeqNum,
    this.nothing = false,
  });
}

/// Internal result type for _disposeTimeoutPackets
class _DisposeResult {
  final int? latestTimeoutSeqNum;
  final List<RtpPacket> sorted;

  _DisposeResult({
    this.latestTimeoutSeqNum,
    required this.sorted,
  });
}
