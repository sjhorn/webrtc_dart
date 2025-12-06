/// Lip Sync (A/V Synchronization)
///
/// Implements audio/video synchronization for WebRTC.
/// Uses NTP timestamps from RTCP Sender Reports to align
/// audio and video streams for proper playback timing.
///
/// RFC 3550 - RTP: A Transport Protocol for Real-Time Applications
/// Section 6.4 - SR: Sender Report RTCP Packet
library;

import 'dart:typed_data';

/// Media kind for lip sync
enum MediaKind {
  audio,
  video,
}

/// Media frame for lip sync processing
class MediaFrame {
  /// Presentation timestamp in milliseconds (NTP-based)
  final int timestamp;

  /// Frame data
  final Uint8List data;

  /// Whether this is a keyframe (for video) or always true for audio
  final bool isKeyframe;

  /// Media kind (audio or video)
  final MediaKind kind;

  MediaFrame({
    required this.timestamp,
    required this.data,
    this.isKeyframe = true,
    required this.kind,
  });

  @override
  String toString() =>
      'MediaFrame(kind=$kind, timestamp=$timestamp, size=${data.length}, keyframe=$isKeyframe)';
}

/// NTP timestamp pair from RTCP SR
/// Used to map RTP timestamps to wall-clock time
class NtpRtpMapping {
  /// NTP timestamp (seconds since 1900)
  final int ntpSeconds;

  /// NTP fraction (fractional seconds)
  final int ntpFraction;

  /// Corresponding RTP timestamp
  final int rtpTimestamp;

  /// Clock rate for RTP timestamp
  final int clockRate;

  NtpRtpMapping({
    required this.ntpSeconds,
    required this.ntpFraction,
    required this.rtpTimestamp,
    required this.clockRate,
  });

  /// Convert RTP timestamp to NTP time in milliseconds
  int rtpToNtpMillis(int rtp) {
    // Calculate the difference in RTP timestamps
    final rtpDiff = (rtp - rtpTimestamp) & 0xFFFFFFFF;

    // Convert to milliseconds
    final msDiff = (rtpDiff * 1000) ~/ clockRate;

    // Get base NTP time in milliseconds
    final ntpMillis = ntpSeconds * 1000 + (ntpFraction * 1000) ~/ 0xFFFFFFFF;

    return ntpMillis + msDiff;
  }

  /// NTP time in milliseconds
  int get ntpMillis => ntpSeconds * 1000 + (ntpFraction * 1000) ~/ 0xFFFFFFFF;

  @override
  String toString() =>
      'NtpRtpMapping(ntp=$ntpSeconds.$ntpFraction, rtp=$rtpTimestamp, rate=$clockRate)';
}

/// Lip sync options
class LipSyncOptions {
  /// Sync interval in milliseconds (how often to flush frames)
  final int syncInterval;

  /// Buffer length (number of sync intervals to buffer)
  final int bufferLength;

  /// Packetization time in milliseconds (for audio)
  final int ptime;

  /// Optional dummy audio packet for gap filling
  final Uint8List? fillDummyAudioPacket;

  /// Maximum allowed drift before resync in milliseconds
  final int maxDrift;

  const LipSyncOptions({
    this.syncInterval = 500,
    this.bufferLength = 10,
    this.ptime = 20,
    this.fillDummyAudioPacket,
    this.maxDrift = 80,
  });

  /// Buffer duration is half of sync interval
  int get bufferDuration => syncInterval ~/ 2;
}

/// Lip sync processor for A/V synchronization
///
/// Buffers audio and video frames, then outputs them in synchronized order
/// based on their NTP-derived timestamps.
class LipSyncProcessor {
  /// Configuration options
  final LipSyncOptions options;

  /// Audio output callback
  final void Function(MediaFrame frame)? onAudioFrame;

  /// Video output callback
  final void Function(MediaFrame frame)? onVideoFrame;

  /// Audio frame buffers (circular buffer of lists)
  late List<List<MediaFrame>> _audioBuffer;

  /// Video frame buffers (circular buffer of lists)
  late List<List<MediaFrame>> _videoBuffer;

  /// Base timestamp (first received frame time)
  int? _baseTime;

  /// Current timestamp being processed
  int _currentTimestamp = 0;

  /// Last committed (output) timestamp
  int _lastCommittedTime = 0;

  /// Last execution time
  int _lastExecutionTime = 0;

  /// Current buffer index
  int _bufferIndex = 0;

  /// Whether the processor is stopped
  bool _stopped = false;

  /// Last frame received wall-clock time (for NTP sync validation)
  int _lastFrameReceivedAt = 0;

  /// Statistics
  int _audioFramesReceived = 0;
  int _videoFramesReceived = 0;
  int _audioFramesOutput = 0;
  int _videoFramesOutput = 0;
  int _droppedFrames = 0;
  int _dummyPacketsInserted = 0;

  LipSyncProcessor({
    this.options = const LipSyncOptions(),
    this.onAudioFrame,
    this.onVideoFrame,
  }) {
    _initBuffers();
  }

  void _initBuffers() {
    final totalBuffers = options.bufferLength * 2;
    _audioBuffer = List.generate(totalBuffers, (_) => <MediaFrame>[]);
    _videoBuffer = List.generate(totalBuffers, (_) => <MediaFrame>[]);
  }

  /// Whether the processor is stopped
  bool get isStopped => _stopped;

  /// Base timestamp (when synced)
  int? get baseTime => _baseTime;

  /// Buffer duration in ms
  int get bufferDuration => options.bufferDuration;

  /// Process an incoming audio frame
  void processAudioFrame(MediaFrame frame) {
    if (_stopped) return;
    _audioFramesReceived++;
    _processFrame(frame, _audioBuffer);
  }

  /// Process an incoming video frame
  void processVideoFrame(MediaFrame frame) {
    if (_stopped) return;
    _videoFramesReceived++;
    _processFrame(frame, _videoBuffer);
  }

  /// Process a frame into the appropriate buffer
  void _processFrame(MediaFrame frame, List<List<MediaFrame>> buffer) {
    if (_stopped) return;

    // Initialize base time on first frame
    if (_baseTime == null) {
      _baseTime = frame.timestamp;
      _currentTimestamp = frame.timestamp;
      _lastExecutionTime = frame.timestamp;
      _lastCommittedTime = frame.timestamp;
      _lastFrameReceivedAt = DateTime.now().millisecondsSinceEpoch;
    }

    // Drop frames older than last committed
    if (frame.timestamp < _lastCommittedTime) {
      _droppedFrames++;
      return;
    }

    // Validate NTP sync (detect large gaps that might indicate clock issues)
    final now = DateTime.now().millisecondsSinceEpoch;
    const gap = 5000; // RTCP SR interval
    final lastCommittedElapsed = frame.timestamp - _lastCommittedTime;
    final lastFrameReceivedElapsed = now - _lastFrameReceivedAt;

    if (gap < lastFrameReceivedElapsed && lastCommittedElapsed < gap) {
      // Possible NTP sync issue - drop frame
      _droppedFrames++;
      return;
    }
    _lastFrameReceivedAt = now;

    // Calculate buffer index based on elapsed time
    final elapsed = frame.timestamp - _baseTime!;
    final totalBuffers = options.bufferLength * 2;
    final index = (elapsed ~/ bufferDuration) % totalBuffers;

    buffer[index].add(frame);

    // Check if it's time to flush
    final diff = frame.timestamp - _lastExecutionTime;
    if (diff >= options.syncInterval) {
      final times = (diff ~/ bufferDuration) - 1;
      _lastExecutionTime = _currentTimestamp;
      for (var i = 0; i < times; i++) {
        _executeFlush();
        _lastExecutionTime += bufferDuration;
      }
    }
  }

  /// Flush the current buffer and output synchronized frames
  void _executeFlush() {
    if (_stopped) return;

    // Sort audio buffer by timestamp
    final audioBuffer = _audioBuffer[_bufferIndex]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Fill audio gaps with dummy packets if configured
    if (options.fillDummyAudioPacket != null && audioBuffer.isNotEmpty) {
      final lastAudio = audioBuffer.last;
      final expectedNext = lastAudio.timestamp + options.ptime;
      final targetEnd = _currentTimestamp + bufferDuration;

      if (expectedNext < targetEnd) {
        for (var time = expectedNext; time < targetEnd; time += options.ptime) {
          audioBuffer.add(MediaFrame(
            timestamp: time,
            data: options.fillDummyAudioPacket!,
            kind: MediaKind.audio,
          ));
          _dummyPacketsInserted++;
        }
      }
    }

    _currentTimestamp += bufferDuration;

    // Merge and filter audio and video frames
    final allFrames = <MediaFrame>[
      ...audioBuffer,
      ..._videoBuffer[_bufferIndex],
    ].where((f) => f.timestamp >= _lastCommittedTime).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Clear buffers
    _audioBuffer[_bufferIndex] = <MediaFrame>[];
    _videoBuffer[_bufferIndex] = <MediaFrame>[];

    // Output synchronized frames
    for (final frame in allFrames) {
      if (frame.kind == MediaKind.audio) {
        onAudioFrame?.call(frame);
        _audioFramesOutput++;
      } else {
        onVideoFrame?.call(frame);
        _videoFramesOutput++;
      }
      _lastCommittedTime = frame.timestamp;
    }

    // Advance buffer index
    _bufferIndex++;
    if (_bufferIndex >= options.bufferLength * 2) {
      _bufferIndex = 0;
    }
  }

  /// Force flush all remaining buffered frames
  void flush() {
    if (_stopped) return;

    final totalBuffers = options.bufferLength * 2;
    for (var i = 0; i < totalBuffers; i++) {
      _executeFlush();
    }
  }

  /// Stop the processor and clear buffers
  void stop() {
    _stopped = true;
    for (final buffer in _audioBuffer) {
      buffer.clear();
    }
    for (final buffer in _videoBuffer) {
      buffer.clear();
    }
  }

  /// Reset the processor to initial state
  void reset() {
    _stopped = false;
    _baseTime = null;
    _currentTimestamp = 0;
    _lastCommittedTime = 0;
    _lastExecutionTime = 0;
    _bufferIndex = 0;
    _lastFrameReceivedAt = 0;
    _audioFramesReceived = 0;
    _videoFramesReceived = 0;
    _audioFramesOutput = 0;
    _videoFramesOutput = 0;
    _droppedFrames = 0;
    _dummyPacketsInserted = 0;
    _initBuffers();
  }

  /// Get statistics
  Map<String, dynamic> toJson() {
    return {
      'baseTime': _baseTime,
      'currentTimestamp': _currentTimestamp,
      'lastCommittedTime': _lastCommittedTime,
      'stopped': _stopped,
      'audioBufferedFrames':
          _audioBuffer.fold<int>(0, (sum, b) => sum + b.length),
      'videoBufferedFrames':
          _videoBuffer.fold<int>(0, (sum, b) => sum + b.length),
      'audioFramesReceived': _audioFramesReceived,
      'videoFramesReceived': _videoFramesReceived,
      'audioFramesOutput': _audioFramesOutput,
      'videoFramesOutput': _videoFramesOutput,
      'droppedFrames': _droppedFrames,
      'dummyPacketsInserted': _dummyPacketsInserted,
    };
  }
}

/// A/V synchronization calculator
///
/// Calculates the sync offset between audio and video streams
/// based on their NTP-RTP timestamp mappings from RTCP SR packets.
class AVSyncCalculator {
  NtpRtpMapping? _audioMapping;
  NtpRtpMapping? _videoMapping;

  /// Update audio NTP-RTP mapping from RTCP SR
  void updateAudioMapping(NtpRtpMapping mapping) {
    _audioMapping = mapping;
  }

  /// Update video NTP-RTP mapping from RTCP SR
  void updateVideoMapping(NtpRtpMapping mapping) {
    _videoMapping = mapping;
  }

  /// Check if we have both mappings for sync calculation
  bool get hasBothMappings => _audioMapping != null && _videoMapping != null;

  /// Calculate the NTP time for an audio RTP timestamp
  int? audioRtpToNtp(int rtpTimestamp) {
    return _audioMapping?.rtpToNtpMillis(rtpTimestamp);
  }

  /// Calculate the NTP time for a video RTP timestamp
  int? videoRtpToNtp(int rtpTimestamp) {
    return _videoMapping?.rtpToNtpMillis(rtpTimestamp);
  }

  /// Calculate the A/V sync offset in milliseconds
  ///
  /// Returns the offset between audio and video NTP times.
  /// Positive value means video is ahead of audio.
  /// Negative value means audio is ahead of video.
  int? calculateOffset(int audioRtp, int videoRtp) {
    if (!hasBothMappings) return null;

    final audioNtp = audioRtpToNtp(audioRtp);
    final videoNtp = videoRtpToNtp(videoRtp);

    if (audioNtp == null || videoNtp == null) return null;

    return videoNtp - audioNtp;
  }

  /// Clear stored mappings
  void reset() {
    _audioMapping = null;
    _videoMapping = null;
  }

  /// Get statistics
  Map<String, dynamic> toJson() {
    return {
      'hasAudioMapping': _audioMapping != null,
      'hasVideoMapping': _videoMapping != null,
      'hasBothMappings': hasBothMappings,
      if (_audioMapping != null) 'audioMapping': _audioMapping.toString(),
      if (_videoMapping != null) 'videoMapping': _videoMapping.toString(),
    };
  }
}

/// Drift detector for A/V sync monitoring
class DriftDetector {
  /// Maximum samples to keep
  final int maxSamples;

  /// Recent offset samples
  final List<int> _samples = [];

  /// Drift threshold in ms
  final int driftThreshold;

  DriftDetector({
    this.maxSamples = 50,
    this.driftThreshold = 80,
  });

  /// Add an offset sample
  void addSample(int offsetMs) {
    _samples.add(offsetMs);
    if (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// Get average offset
  double get averageOffset {
    if (_samples.isEmpty) return 0;
    return _samples.reduce((a, b) => a + b) / _samples.length;
  }

  /// Check if drift exceeds threshold
  bool get hasDrift => averageOffset.abs() > driftThreshold;

  /// Get current drift direction
  /// Returns positive if video is ahead, negative if audio is ahead
  int get driftDirection {
    final avg = averageOffset;
    if (avg > driftThreshold) return 1; // Video ahead
    if (avg < -driftThreshold) return -1; // Audio ahead
    return 0; // In sync
  }

  /// Reset drift detection
  void reset() {
    _samples.clear();
  }

  /// Get statistics
  Map<String, dynamic> toJson() {
    return {
      'sampleCount': _samples.length,
      'averageOffset': averageOffset,
      'hasDrift': hasDrift,
      'driftDirection': driftDirection,
    };
  }
}
