/// Recording Pipeline Components
///
/// Implements the processing pipeline for MediaRecorder:
/// RTP Source -> Jitter Buffer -> NTP Time -> Depacketizer -> LipSync -> WebM
///
/// Ported from werift-webrtc processor callbacks
library;

import 'dart:typed_data';

import '../../codec/vp8.dart';
import '../../codec/vp9.dart';
import '../../codec/h264.dart';
import '../../codec/av1.dart';
import '../../rtp/jitter_buffer.dart';
import '../../rtp/rtx.dart';
import '../../rtp/rtcp_reports.dart';
import '../../srtp/rtp_packet.dart';

/// Max unsigned 32-bit integer for wraparound handling
const int _max32Uint = 0xFFFFFFFF;

/// Depacketized codec frame
class CodecFrame {
  final Uint8List data;
  final bool isKeyframe;

  /// Presentation time in milliseconds
  final int timeMs;

  /// RTP sequence number of last packet in frame
  final int? rtpSeq;

  /// RTP timestamp
  final int? rtpTimestamp;

  CodecFrame({
    required this.data,
    required this.isKeyframe,
    required this.timeMs,
    this.rtpSeq,
    this.rtpTimestamp,
  });

  @override
  String toString() =>
      'CodecFrame(size=${data.length}, keyframe=$isKeyframe, time=$timeMs)';
}

/// Supported depacketizer codecs
enum DepacketizerCodec {
  vp8,
  vp9,
  h264,
  av1,
  opus,
}

/// NTP timestamp processor
///
/// Converts RTP timestamps to NTP-based presentation times using RTCP SR info.
/// Ported from werift NtpTimeBase
class NtpTimeProcessor {
  final int clockRate;

  BigInt? _baseNtpTimestamp;
  int? _baseRtpTimestamp;
  BigInt? _latestNtpTimestamp;
  int? _latestRtpTimestamp;
  double _currentElapsed = 0;
  final List<RtpPacket> _buffer = [];
  bool started = false;

  NtpTimeProcessor(this.clockRate);

  /// Process RTCP SR packet to update NTP-RTP mapping
  void processRtcp(RtcpSenderReport sr) {
    final ntpTimestamp = BigInt.from(sr.ntpTimestamp);
    final rtpTimestamp = sr.rtpTimestamp;

    _latestNtpTimestamp = ntpTimestamp;
    _latestRtpTimestamp = rtpTimestamp;

    if (_baseNtpTimestamp == null) {
      _baseNtpTimestamp = ntpTimestamp;
      _baseRtpTimestamp = rtpTimestamp;
    }

    started = true;
  }

  /// Process RTP packet and return time-stamped outputs
  ///
  /// Returns list of (rtp, timeMs) tuples. Empty if not yet synced.
  List<({RtpPacket rtp, int timeMs})> processRtp(RtpPacket rtp) {
    _buffer.add(rtp);

    if (_baseRtpTimestamp == null ||
        _baseNtpTimestamp == null ||
        _latestNtpTimestamp == null ||
        _latestRtpTimestamp == null) {
      return [];
    }

    final results = <({RtpPacket rtp, int timeMs})>[];
    for (final packet in _buffer) {
      final ntpSec = _updateNtp(packet.timestamp);
      final timeMs = (ntpSec * 1000).round();
      results.add((rtp: packet, timeMs: timeMs));
    }
    _buffer.clear();
    return results;
  }

  double _calcNtp({
    required int rtpTimestamp,
    required int baseRtpTimestamp,
    required BigInt baseNtpTimestamp,
    required double elapsedOffset,
  }) {
    // Handle 32-bit wraparound
    final rotate =
        (rtpTimestamp - baseRtpTimestamp).abs() > (_max32Uint / 4) * 3;

    final elapsed = rotate
        ? rtpTimestamp + _max32Uint - baseRtpTimestamp
        : rtpTimestamp - baseRtpTimestamp;
    final elapsedSec = elapsed / clockRate;

    // Convert NTP timestamp to seconds
    final ntpSec = _ntpTime2Sec(baseNtpTimestamp) + elapsedOffset + elapsedSec;
    return ntpSec;
  }

  double _updateNtp(int rtpTimestamp) {
    final baseNtp = _calcNtp(
      rtpTimestamp: rtpTimestamp,
      baseNtpTimestamp: _baseNtpTimestamp!,
      baseRtpTimestamp: _baseRtpTimestamp!,
      elapsedOffset: _currentElapsed,
    );

    final latestNtp = _calcNtp(
      rtpTimestamp: rtpTimestamp,
      baseNtpTimestamp: _latestNtpTimestamp!,
      baseRtpTimestamp: _latestRtpTimestamp!,
      elapsedOffset: 0,
    );

    if (baseNtp < latestNtp) {
      // Update base NTP
      _baseNtpTimestamp = _latestNtpTimestamp;
      _baseRtpTimestamp = _latestRtpTimestamp;
      _currentElapsed = 0;
      return latestNtp;
    } else {
      final elapsedSec = (rtpTimestamp - _baseRtpTimestamp!) / clockRate;
      _currentElapsed += elapsedSec;
      _baseRtpTimestamp = rtpTimestamp;
      return baseNtp;
    }
  }

  /// Convert NTP 64-bit timestamp to seconds
  static double _ntpTime2Sec(BigInt ntpTimestamp) {
    final seconds = (ntpTimestamp >> 32).toInt();
    final fraction = (ntpTimestamp & BigInt.from(0xFFFFFFFF)).toDouble();
    return seconds + fraction / 0x100000000;
  }

  void reset() {
    _baseNtpTimestamp = null;
    _baseRtpTimestamp = null;
    _latestNtpTimestamp = null;
    _latestRtpTimestamp = null;
    _currentElapsed = 0;
    _buffer.clear();
    started = false;
  }

  Map<String, dynamic> toJson() => {
        'clockRate': clockRate,
        'started': started,
        'bufferLength': _buffer.length,
        'baseRtpTimestamp': _baseRtpTimestamp,
        'latestRtpTimestamp': _latestRtpTimestamp,
      };
}

/// RTP timestamp processor (fallback when no RTCP SR available)
///
/// Uses RTP timestamp directly for timing instead of NTP
class RtpTimeProcessor {
  final int clockRate;
  int? _baseTimestamp;

  RtpTimeProcessor(this.clockRate);

  /// Process RTP packet and return time in milliseconds
  int processRtp(RtpPacket rtp) {
    _baseTimestamp ??= rtp.timestamp;

    // Handle 32-bit wraparound
    final diff = (rtp.timestamp - _baseTimestamp!) & _max32Uint;
    final rotate = diff > (_max32Uint / 4) * 3;

    final elapsed = rotate ? diff - _max32Uint : diff;
    return (elapsed * 1000 ~/ clockRate);
  }

  void reset() {
    _baseTimestamp = null;
  }
}

/// Depacketizer for reassembling frames from RTP packets
///
/// Handles frame assembly for video codecs (VP8, VP9, H264, AV1)
/// and simple passthrough for audio (Opus)
class Depacketizer {
  final DepacketizerCodec codec;
  final bool Function(RtpPacket)? isFinalPacketInSequence;
  final bool waitForKeyframe;

  final List<_BufferedPacket> _rtpBuffer = [];
  int? _lastSeqNum;
  bool _frameBroken = false;
  bool _keyframeReceived = false;
  int _frameCount = 0;

  Depacketizer(
    this.codec, {
    this.isFinalPacketInSequence,
    this.waitForKeyframe = false,
  });

  /// Process input and return depacketized frames
  List<CodecFrame> processInput({
    RtpPacket? rtp,
    int? timeMs,
    bool eol = false,
  }) {
    final output = <CodecFrame>[];

    if (rtp == null) {
      if (eol) {
        _stop();
      }
      return output;
    }

    if (isFinalPacketInSequence != null) {
      // Buffered mode: collect packets until final packet marker
      final isFinal = _checkFinalPacket(rtp, timeMs);
      if (isFinal) {
        final frame = _depacketize(
          _rtpBuffer.map((b) => b.rtp).toList(),
          _rtpBuffer.isNotEmpty ? _rtpBuffer.last.timeMs : timeMs,
        );

        if (frame != null) {
          if (frame.isKeyframe) {
            _keyframeReceived = true;
          }

          if (waitForKeyframe && !_keyframeReceived) {
            return [];
          }

          if (!_frameBroken && frame.data.isNotEmpty) {
            output.add(frame);
          }

          if (_frameBroken) {
            _frameBroken = false;
          }
        }

        _clearBuffer();
      }
    } else {
      // Immediate mode: depacketize each packet
      final frame = _depacketize([rtp], timeMs);
      if (frame != null) {
        output.add(frame);
      }
    }

    return output;
  }

  bool _checkFinalPacket(RtpPacket rtp, int? timeMs) {
    final sequenceNumber = rtp.sequenceNumber;

    if (_lastSeqNum != null) {
      final expect = uint16Add(_lastSeqNum!, 1);
      if (uint16Gt(expect, sequenceNumber)) {
        // Unexpected older packet
        return false;
      }
      if (uint16Gt(sequenceNumber, expect)) {
        // Packet loss detected
        _frameBroken = true;
        _clearBuffer();
      }
    }

    _rtpBuffer.add(_BufferedPacket(rtp, timeMs));
    _lastSeqNum = sequenceNumber;

    // Check if this is the final packet
    for (final buffered in _rtpBuffer) {
      if (isFinalPacketInSequence!(buffered.rtp)) {
        return true;
      }
    }

    return false;
  }

  CodecFrame? _depacketize(List<RtpPacket> packets, int? timeMs) {
    if (packets.isEmpty) return null;

    switch (codec) {
      case DepacketizerCodec.vp8:
        return _depacketizeVp8(packets, timeMs);
      case DepacketizerCodec.vp9:
        return _depacketizeVp9(packets, timeMs);
      case DepacketizerCodec.h264:
        return _depacketizeH264(packets, timeMs);
      case DepacketizerCodec.av1:
        return _depacketizeAv1(packets, timeMs);
      case DepacketizerCodec.opus:
        return _depacketizeOpus(packets, timeMs);
    }
  }

  CodecFrame? _depacketizeVp8(List<RtpPacket> packets, int? timeMs) {
    final payloads = <Uint8List>[];
    bool isKeyframe = false;

    for (final packet in packets) {
      final vp8 = Vp8RtpPayload.deserialize(packet.payload);
      if (vp8.isPartitionHead && vp8.isKeyframe) {
        isKeyframe = true;
      }
      if (vp8.payload.isNotEmpty) {
        payloads.add(vp8.payload);
      }
    }

    if (payloads.isEmpty) return null;

    final totalLength = payloads.fold<int>(0, (sum, p) => sum + p.length);
    final data = Uint8List(totalLength);
    var offset = 0;
    for (final p in payloads) {
      data.setAll(offset, p);
      offset += p.length;
    }

    _frameCount++;
    return CodecFrame(
      data: data,
      isKeyframe: isKeyframe,
      timeMs: timeMs ?? 0,
      rtpSeq: packets.last.sequenceNumber,
      rtpTimestamp: packets.last.timestamp,
    );
  }

  CodecFrame? _depacketizeVp9(List<RtpPacket> packets, int? timeMs) {
    final payloads = <Uint8List>[];
    bool isKeyframe = false;

    for (final packet in packets) {
      final vp9 = Vp9RtpPayload.deserialize(packet.payload);
      if (vp9.isKeyframe) {
        isKeyframe = true;
      }
      if (vp9.payload.isNotEmpty) {
        payloads.add(vp9.payload);
      }
    }

    if (payloads.isEmpty) return null;

    final totalLength = payloads.fold<int>(0, (sum, p) => sum + p.length);
    final data = Uint8List(totalLength);
    var offset = 0;
    for (final p in payloads) {
      data.setAll(offset, p);
      offset += p.length;
    }

    _frameCount++;
    return CodecFrame(
      data: data,
      isKeyframe: isKeyframe,
      timeMs: timeMs ?? 0,
      rtpSeq: packets.last.sequenceNumber,
      rtpTimestamp: packets.last.timestamp,
    );
  }

  CodecFrame? _depacketizeH264(List<RtpPacket> packets, int? timeMs) {
    final payloads = <Uint8List>[];
    bool isKeyframe = false;

    for (final packet in packets) {
      final h264 = H264RtpPayload.deserialize(packet.payload);
      if (h264.isKeyframe) {
        isKeyframe = true;
      }
      if (h264.payload.isNotEmpty) {
        payloads.add(h264.payload);
      }
    }

    if (payloads.isEmpty) return null;

    final totalLength = payloads.fold<int>(0, (sum, p) => sum + p.length);
    final data = Uint8List(totalLength);
    var offset = 0;
    for (final p in payloads) {
      data.setAll(offset, p);
      offset += p.length;
    }

    _frameCount++;
    return CodecFrame(
      data: data,
      isKeyframe: isKeyframe,
      timeMs: timeMs ?? 0,
      rtpSeq: packets.last.sequenceNumber,
      rtpTimestamp: packets.last.timestamp,
    );
  }

  CodecFrame? _depacketizeAv1(List<RtpPacket> packets, int? timeMs) {
    final av1Payloads = <Av1RtpPayload>[];
    bool isKeyframe = false;

    for (final packet in packets) {
      final av1 = Av1RtpPayload.deserialize(packet.payload);
      if (av1.isKeyframe) {
        isKeyframe = true;
      }
      av1Payloads.add(av1);
    }

    if (av1Payloads.isEmpty) return null;

    // Use AV1's getFrame to properly reassemble OBUs
    final data = Av1RtpPayload.getFrame(av1Payloads);
    if (data.isEmpty) return null;

    _frameCount++;
    return CodecFrame(
      data: data,
      isKeyframe: isKeyframe,
      timeMs: timeMs ?? 0,
      rtpSeq: packets.last.sequenceNumber,
      rtpTimestamp: packets.last.timestamp,
    );
  }

  CodecFrame? _depacketizeOpus(List<RtpPacket> packets, int? timeMs) {
    // Opus: payload is the raw Opus packet
    if (packets.isEmpty) return null;

    final packet = packets.last;
    _frameCount++;
    return CodecFrame(
      data: packet.payload,
      isKeyframe: true, // Opus frames are independent
      timeMs: timeMs ?? 0,
      rtpSeq: packet.sequenceNumber,
      rtpTimestamp: packet.timestamp,
    );
  }

  void _clearBuffer() {
    _rtpBuffer.clear();
  }

  void _stop() {
    _clearBuffer();
  }

  void reset() {
    _clearBuffer();
    _lastSeqNum = null;
    _frameBroken = false;
    _keyframeReceived = false;
    _frameCount = 0;
  }

  Map<String, dynamic> toJson() => {
        'codec': codec.name,
        'bufferLength': _rtpBuffer.length,
        'lastSeqNum': _lastSeqNum,
        'frameCount': _frameCount,
        'keyframeReceived': _keyframeReceived,
      };
}

class _BufferedPacket {
  final RtpPacket rtp;
  final int? timeMs;

  _BufferedPacket(this.rtp, this.timeMs);
}

/// Track processing pipeline
///
/// Combines JitterBuffer -> NtpTime -> Depacketizer for a single track
class TrackPipeline {
  final int trackNumber;
  final DepacketizerCodec codec;
  final int clockRate;
  final bool isVideo;
  final bool disableNtp;
  final JitterBufferOptions jitterBufferOptions;

  late final JitterBuffer _jitterBuffer;
  late final NtpTimeProcessor? _ntpTime;
  late final RtpTimeProcessor? _rtpTime;
  late final Depacketizer _depacketizer;

  void Function(CodecFrame frame)? onFrame;

  TrackPipeline({
    required this.trackNumber,
    required this.codec,
    required this.clockRate,
    required this.isVideo,
    this.disableNtp = false,
    this.jitterBufferOptions = const JitterBufferOptions(),
    this.onFrame,
  }) {
    _jitterBuffer = JitterBuffer(clockRate, options: jitterBufferOptions);

    if (disableNtp) {
      _rtpTime = RtpTimeProcessor(clockRate);
      _ntpTime = null;
    } else {
      _ntpTime = NtpTimeProcessor(clockRate);
      _rtpTime = null;
    }

    _depacketizer = Depacketizer(
      codec,
      isFinalPacketInSequence: isVideo ? (rtp) => rtp.marker : null,
      waitForKeyframe: isVideo,
    );
  }

  /// Process incoming RTP packet
  void processRtp(RtpPacket rtp) {
    // 1. Jitter buffer for reordering
    final jitterOutputs = _jitterBuffer.processInput(rtp: rtp);

    for (final jitterOut in jitterOutputs) {
      if (jitterOut.rtp == null) continue;

      // 2. Time conversion (NTP or RTP-based)
      if (_ntpTime != null) {
        final timeOutputs = _ntpTime.processRtp(jitterOut.rtp!);
        for (final timeOut in timeOutputs) {
          // 3. Depacketize
          final frames = _depacketizer.processInput(
            rtp: timeOut.rtp,
            timeMs: timeOut.timeMs,
          );
          for (final frame in frames) {
            onFrame?.call(frame);
          }
        }
      } else if (_rtpTime != null) {
        final timeMs = _rtpTime.processRtp(jitterOut.rtp!);
        final frames = _depacketizer.processInput(
          rtp: jitterOut.rtp,
          timeMs: timeMs,
        );
        for (final frame in frames) {
          onFrame?.call(frame);
        }
      }
    }
  }

  /// Process incoming RTCP packet (for NTP sync)
  void processRtcp(RtcpSenderReport sr) {
    _ntpTime?.processRtcp(sr);
  }

  /// Signal end of stream
  void endOfStream() {
    // Flush jitter buffer
    final jitterOutputs = _jitterBuffer.processInput(eol: true);
    for (final jitterOut in jitterOutputs) {
      if (jitterOut.rtp != null) {
        if (_ntpTime != null) {
          final timeOutputs = _ntpTime.processRtp(jitterOut.rtp!);
          for (final timeOut in timeOutputs) {
            final frames = _depacketizer.processInput(
              rtp: timeOut.rtp,
              timeMs: timeOut.timeMs,
            );
            for (final frame in frames) {
              onFrame?.call(frame);
            }
          }
        } else if (_rtpTime != null) {
          final timeMs = _rtpTime.processRtp(jitterOut.rtp!);
          final frames = _depacketizer.processInput(
            rtp: jitterOut.rtp,
            timeMs: timeMs,
          );
          for (final frame in frames) {
            onFrame?.call(frame);
          }
        }
      }
    }

    // Signal EOL to depacketizer
    _depacketizer.processInput(eol: true);
  }

  void reset() {
    _ntpTime?.reset();
    _rtpTime?.reset();
    _depacketizer.reset();
  }

  Map<String, dynamic> toJson() => {
        'trackNumber': trackNumber,
        'codec': codec.name,
        'clockRate': clockRate,
        'isVideo': isVideo,
        'jitterBuffer': _jitterBuffer.toJson(),
        'ntpTime': _ntpTime?.toJson(),
        'depacketizer': _depacketizer.toJson(),
      };
}
