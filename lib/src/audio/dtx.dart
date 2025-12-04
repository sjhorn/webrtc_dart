/// DTX (Discontinuous Transmission) Support
///
/// Implements DTX handling for audio codecs, primarily Opus.
/// DTX allows sending only during active speech, saving bandwidth during silence.
///
/// RFC 7587 - RTP Payload Format for the Opus Speech and Audio Codec
/// Section 3.1.3 - Discontinuous Transmission (DTX)
library;

import 'dart:typed_data';

/// Opus packet type configuration (TOC byte analysis)
/// RFC 6716 Section 3.1
class OpusTocByte {
  /// Configuration number (0-31)
  final int config;

  /// Stereo flag (0 = mono, 1 = stereo)
  final int stereo;

  /// Frame count code (0 = 1 frame, 1 = 2 frames, 2 = 2 frames CBR, 3 = arbitrary)
  final int frameCountCode;

  OpusTocByte({
    required this.config,
    required this.stereo,
    required this.frameCountCode,
  });

  /// Parse TOC byte from first byte of Opus packet
  factory OpusTocByte.parse(int tocByte) {
    return OpusTocByte(
      config: (tocByte >> 3) & 0x1F,
      stereo: (tocByte >> 2) & 0x01,
      frameCountCode: tocByte & 0x03,
    );
  }

  /// Check if this is a SILK-only configuration (configs 0-11)
  bool get isSilk => config <= 11;

  /// Check if this is a Hybrid configuration (configs 12-15)
  bool get isHybrid => config >= 12 && config <= 15;

  /// Check if this is a CELT-only configuration (configs 16-31)
  bool get isCelt => config >= 16;

  /// Get the bandwidth from config
  OpusBandwidth get bandwidth {
    if (config <= 3) return OpusBandwidth.narrowband;
    if (config <= 7) return OpusBandwidth.mediumband;
    if (config <= 11) return OpusBandwidth.wideband;
    if (config <= 13) return OpusBandwidth.superwideband;
    if (config <= 15) return OpusBandwidth.fullband;
    if (config <= 19) return OpusBandwidth.narrowband;
    if (config <= 23) return OpusBandwidth.wideband;
    if (config <= 27) return OpusBandwidth.superwideband;
    return OpusBandwidth.fullband;
  }

  @override
  String toString() =>
      'OpusTocByte(config=$config, stereo=$stereo, frameCount=$frameCountCode)';
}

/// Opus bandwidth modes
enum OpusBandwidth {
  narrowband, // 4 kHz
  mediumband, // 6 kHz
  wideband, // 8 kHz
  superwideband, // 12 kHz
  fullband, // 20 kHz (default for WebRTC)
}

/// Opus DTX packet types
enum OpusDtxPacketType {
  /// Normal speech packet
  speech,

  /// Comfort noise packet (DTX packet with minimal data)
  comfortNoise,

  /// Silence frame (no audio data)
  silence,
}

/// Opus packet analyzer for DTX detection
class OpusPacketAnalyzer {
  /// Minimum size for a DTX/comfort noise packet
  /// Very small packets (1-3 bytes) are typically DTX frames
  static const int minDtxPacketSize = 1;
  static const int maxDtxPacketSize = 3;

  /// Analyze an Opus packet to determine its DTX type
  static OpusDtxPacketType analyzePacket(Uint8List packet) {
    if (packet.isEmpty) {
      return OpusDtxPacketType.silence;
    }

    // Very small packets are typically comfort noise / DTX frames
    if (packet.length <= maxDtxPacketSize) {
      return OpusDtxPacketType.comfortNoise;
    }

    return OpusDtxPacketType.speech;
  }

  /// Check if a packet is a DTX frame
  static bool isDtxPacket(Uint8List packet) {
    final type = analyzePacket(packet);
    return type == OpusDtxPacketType.comfortNoise ||
        type == OpusDtxPacketType.silence;
  }

  /// Parse the TOC byte from an Opus packet
  static OpusTocByte? parseTocByte(Uint8List packet) {
    if (packet.isEmpty) return null;
    return OpusTocByte.parse(packet[0]);
  }
}

/// Opus codec parameters for DTX
class OpusDtxParameters {
  /// Enable DTX (usedtx=1 in SDP)
  final bool useDtx;

  /// Enable in-band FEC (useinbandfec=1 in SDP)
  final bool useInbandFec;

  /// Minimum packet time in ms (minptime in SDP)
  final int? minPtime;

  /// Maximum average bitrate (maxaveragebitrate in SDP)
  final int? maxAverageBitrate;

  /// Stereo mode (stereo=1 in SDP)
  final bool stereo;

  /// Constant bitrate mode (cbr=1 in SDP)
  final bool cbr;

  /// Packetization time in ms (ptime)
  final int ptime;

  const OpusDtxParameters({
    this.useDtx = false,
    this.useInbandFec = true,
    this.minPtime,
    this.maxAverageBitrate,
    this.stereo = true,
    this.cbr = false,
    this.ptime = 20,
  });

  /// Parse from SDP fmtp parameters string
  /// Example: "minptime=10;useinbandfec=1;usedtx=1"
  factory OpusDtxParameters.fromSdpFmtp(String fmtp, {int ptime = 20}) {
    final params = <String, String>{};

    for (final part in fmtp.split(';')) {
      final kv = part.split('=');
      if (kv.length == 2) {
        params[kv[0].trim().toLowerCase()] = kv[1].trim();
      }
    }

    return OpusDtxParameters(
      useDtx: params['usedtx'] == '1',
      useInbandFec: params['useinbandfec'] == '1',
      minPtime: int.tryParse(params['minptime'] ?? ''),
      maxAverageBitrate: int.tryParse(params['maxaveragebitrate'] ?? ''),
      stereo: params['stereo'] == '1',
      cbr: params['cbr'] == '1',
      ptime: ptime,
    );
  }

  /// Convert to SDP fmtp parameters string
  String toSdpFmtp() {
    final parts = <String>[];

    if (minPtime != null) {
      parts.add('minptime=$minPtime');
    }
    if (useInbandFec) {
      parts.add('useinbandfec=1');
    }
    if (useDtx) {
      parts.add('usedtx=1');
    }
    if (stereo) {
      parts.add('stereo=1');
    }
    if (cbr) {
      parts.add('cbr=1');
    }
    if (maxAverageBitrate != null) {
      parts.add('maxaveragebitrate=$maxAverageBitrate');
    }

    return parts.join(';');
  }

  @override
  String toString() =>
      'OpusDtxParameters(useDtx=$useDtx, useInbandFec=$useInbandFec, ptime=$ptime)';
}

/// Audio frame for DTX processing
class DtxAudioFrame {
  /// RTP timestamp
  final int timestamp;

  /// Audio data (may be null for silence frames)
  final Uint8List? data;

  /// Frame type
  final OpusDtxPacketType type;

  /// Is this a keyframe (for audio, always true)
  final bool isKeyframe;

  DtxAudioFrame({
    required this.timestamp,
    this.data,
    required this.type,
    this.isKeyframe = true,
  });

  /// Check if this is a silence frame
  bool get isSilence => type == OpusDtxPacketType.silence;

  /// Check if this is a comfort noise frame
  bool get isComfortNoise => type == OpusDtxPacketType.comfortNoise;

  /// Check if this is a speech frame
  bool get isSpeech => type == OpusDtxPacketType.speech;

  @override
  String toString() => 'DtxAudioFrame(timestamp=$timestamp, type=$type, '
      'size=${data?.length ?? 0})';
}

/// DTX processor for handling discontinuous audio transmission
///
/// This processor detects gaps in audio RTP stream and fills them
/// with silence or comfort noise frames to maintain timing.
class DtxProcessor {
  /// Packetization time in RTP timestamp units
  final int ptimeTimestampUnits;

  /// Clock rate (typically 48000 for Opus)
  final int clockRate;

  /// Dummy/silence packet to insert for gaps
  final Uint8List silencePacket;

  /// Previous timestamp processed
  int? _previousTimestamp;

  /// Number of filled gaps
  int _fillCount = 0;

  /// Whether DTX is enabled
  bool enabled;

  /// Create a DTX processor
  ///
  /// [ptime] - Packetization time in milliseconds (default 20ms for Opus)
  /// [clockRate] - RTP clock rate (default 48000 for Opus)
  /// [silencePacket] - Packet to use for filling gaps (default: empty Opus frame)
  DtxProcessor({
    int ptime = 20,
    this.clockRate = 48000,
    Uint8List? silencePacket,
    this.enabled = true,
  })  : ptimeTimestampUnits = (ptime * clockRate) ~/ 1000,
        silencePacket = silencePacket ?? createOpusSilenceFrame();

  /// Create a minimal Opus silence frame
  /// This is a valid Opus packet that decodes to silence
  static Uint8List createOpusSilenceFrame() {
    // Minimal Opus DTX frame: TOC byte indicating SILK narrowband, mono, 1 frame
    // with no audio data following it
    return Uint8List.fromList([0xF8]); // CELT config, mono, 1 frame - minimal
  }

  /// Number of silence frames inserted
  int get fillCount => _fillCount;

  /// Reset the processor state
  void reset() {
    _previousTimestamp = null;
    _fillCount = 0;
  }

  /// Process an incoming audio frame
  ///
  /// Returns a list of frames, possibly including inserted silence frames
  /// if there was a gap in the timestamp sequence.
  List<DtxAudioFrame> processFrame(DtxAudioFrame frame) {
    if (!enabled) {
      _previousTimestamp = frame.timestamp;
      return [frame];
    }

    if (_previousTimestamp == null) {
      _previousTimestamp = frame.timestamp;
      return [frame];
    }

    final expectedTimestamp = _previousTimestamp! + ptimeTimestampUnits;

    // Check if there's a gap (accounting for timestamp wraparound)
    final gap = _calculateTimestampGap(expectedTimestamp, frame.timestamp);

    if (gap > 0 && gap < 100 * ptimeTimestampUnits) {
      // There's a gap - fill with silence frames
      final filledFrames = <DtxAudioFrame>[];

      var fillTimestamp = expectedTimestamp;
      while (_timestampLessThan(fillTimestamp, frame.timestamp)) {
        filledFrames.add(DtxAudioFrame(
          timestamp: fillTimestamp,
          data: silencePacket,
          type: OpusDtxPacketType.silence,
        ));
        _fillCount++;
        fillTimestamp += ptimeTimestampUnits;
      }

      filledFrames.add(frame);
      _previousTimestamp = frame.timestamp;
      return filledFrames;
    }

    _previousTimestamp = frame.timestamp;
    return [frame];
  }

  /// Process RTP packet data
  ///
  /// Convenience method that creates an DtxAudioFrame from raw RTP payload
  List<DtxAudioFrame> processPacket(int timestamp, Uint8List payload) {
    final type = OpusPacketAnalyzer.analyzePacket(payload);
    final frame = DtxAudioFrame(
      timestamp: timestamp,
      data: payload,
      type: type,
    );
    return processFrame(frame);
  }

  /// Calculate gap between expected and actual timestamp
  int _calculateTimestampGap(int expected, int actual) {
    // Handle 32-bit timestamp wraparound
    final diff = (actual - expected) & 0xFFFFFFFF;
    if (diff > 0x80000000) {
      // Negative difference (actual is before expected)
      return 0;
    }
    return diff;
  }

  /// Compare timestamps with wraparound handling
  bool _timestampLessThan(int a, int b) {
    final diff = (b - a) & 0xFFFFFFFF;
    return diff > 0 && diff < 0x80000000;
  }

  /// Get statistics as a map
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'fillCount': _fillCount,
      'clockRate': clockRate,
      'ptimeTimestampUnits': ptimeTimestampUnits,
    };
  }
}

/// DTX state tracker for monitoring DTX behavior
class DtxStateTracker {
  /// Whether currently in DTX (silence) mode
  bool _inDtxMode = false;

  /// Timestamp when DTX mode started
  int? _dtxStartTimestamp;

  /// Total duration spent in DTX mode (in timestamp units)
  int _totalDtxDuration = 0;

  /// Number of DTX periods
  int _dtxPeriodCount = 0;

  /// Whether currently in DTX mode
  bool get inDtxMode => _inDtxMode;

  /// Number of DTX silence periods
  int get dtxPeriodCount => _dtxPeriodCount;

  /// Total DTX duration in timestamp units
  int get totalDtxDuration => _totalDtxDuration;

  /// Update state based on incoming frame
  void updateState(DtxAudioFrame frame) {
    if (frame.isSpeech) {
      if (_inDtxMode && _dtxStartTimestamp != null) {
        // Exiting DTX mode
        _totalDtxDuration += frame.timestamp - _dtxStartTimestamp!;
      }
      _inDtxMode = false;
      _dtxStartTimestamp = null;
    } else {
      if (!_inDtxMode) {
        // Entering DTX mode
        _inDtxMode = true;
        _dtxStartTimestamp = frame.timestamp;
        _dtxPeriodCount++;
      }
    }
  }

  /// Reset tracking state
  void reset() {
    _inDtxMode = false;
    _dtxStartTimestamp = null;
    _totalDtxDuration = 0;
    _dtxPeriodCount = 0;
  }

  /// Get statistics
  Map<String, dynamic> toJson() {
    return {
      'inDtxMode': _inDtxMode,
      'dtxPeriodCount': _dtxPeriodCount,
      'totalDtxDuration': _totalDtxDuration,
    };
  }
}
