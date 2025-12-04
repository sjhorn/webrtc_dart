/// MuteHandler - Silence frame insertion during gaps
///
/// Inserts dummy/silence frames during periods when no media is received,
/// maintaining consistent timing for playback.
///
/// Ported from werift-webrtc mute.ts
library;

import 'dart:math';
import 'dart:typed_data';

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

/// Input frame for mute handler
class MuteInput {
  /// Codec frame data
  final MuteFrame? frame;

  /// End of life signal
  final bool eol;

  MuteInput({this.frame, this.eol = false});
}

/// Frame data for mute processing
class MuteFrame {
  /// Frame data
  final Uint8List data;

  /// Whether this is a keyframe
  final bool isKeyframe;

  /// Timestamp in milliseconds
  final int timeMs;

  MuteFrame({
    required this.data,
    required this.isKeyframe,
    required this.timeMs,
  });
}

/// Output is same as input
typedef MuteOutput = MuteInput;

/// Mute handler options
class MuteHandlerOptions {
  /// Packet time in milliseconds (e.g., 20ms for Opus)
  final int ptime;

  /// Dummy/silence packet to insert
  final Uint8List dummyPacket;

  /// Interval for checking and inserting silence (ms)
  final int interval;

  /// Buffer length (number of slots)
  final int bufferLength;

  const MuteHandlerOptions({
    required this.ptime,
    required this.dummyPacket,
    this.interval = 1000,
    this.bufferLength = 10,
  });
}

/// Mute handler for inserting silence frames during gaps
///
/// This processor buffers incoming frames and inserts dummy packets
/// when gaps are detected, ensuring continuous output for playback.
class MuteHandler {
  /// Unique ID for this processor
  final String id = _generateUuid();

  /// Output callback
  final void Function(MuteOutput output) _output;

  /// Handler options
  final MuteHandlerOptions options;

  /// Circular buffer for frames
  late List<List<MuteFrame>> _buffer;

  /// Current buffer index
  int _index = 0;

  /// Whether processing has ended
  bool _ended = false;

  /// Base timestamp (first frame time)
  int? _baseTime;

  /// Current timestamp being processed
  int _currentTimestamp = 0;

  /// Last committed frame time
  int _lastCommittedTime = 0;

  /// Last execution time
  int _lastExecutionTime = 0;

  /// Last frame received timestamp (wall clock)
  DateTime? _lastFrameReceivedAt;

  /// Buffer duration (half of interval)
  late int _bufferDuration;

  /// Actual buffer length (doubled)
  late int _bufferLength;

  /// Internal statistics
  final Map<String, dynamic> _internalStats = {};

  MuteHandler({
    required void Function(MuteOutput output) output,
    required this.options,
  }) : _output = output {
    _bufferDuration = options.interval ~/ 2;
    _bufferLength = options.bufferLength * 2;
    _buffer = List.generate(_bufferLength, (_) => <MuteFrame>[]);
  }

  /// Get statistics as JSON
  Map<String, dynamic> toJson() => {..._internalStats, 'id': id};

  /// Process input frame
  List<MuteOutput> processInput(MuteInput input) {
    if (input.frame == null) {
      _stop();
      return [MuteOutput(eol: input.eol)];
    }

    if (_ended) {
      return [];
    }

    final frame = input.frame!;

    if (_baseTime == null) {
      _baseTime = frame.timeMs;
      _currentTimestamp = _baseTime!;
      _lastExecutionTime = _baseTime!;
      _lastCommittedTime = _baseTime!;
      _lastFrameReceivedAt = DateTime.now();
    }

    // Drop frames from the past
    if (frame.timeMs < _lastCommittedTime) {
      return [];
    }

    // Check for NTP sync issues
    final now = DateTime.now();
    const gap = 5000; // RTCP SR interval
    final lastCommittedElapsed = frame.timeMs - _lastCommittedTime;
    final lastFrameReceivedElapsed =
        now.difference(_lastFrameReceivedAt!).inMilliseconds;

    if (gap < lastFrameReceivedElapsed && lastCommittedElapsed < gap) {
      _internalStats['invalidFrameTime'] = {
        'count': ((_internalStats['invalidFrameTime']
                    as Map<String, dynamic>?)?['count'] ??
                0) +
            1,
        'at': DateTime.now().toIso8601String(),
        'lastCommittedElapsed': lastCommittedElapsed,
        'lastFrameReceivedElapsed': lastFrameReceivedElapsed,
      };
      return [];
    }
    _lastFrameReceivedAt = now;

    // Calculate buffer index based on elapsed time
    final elapsed = frame.timeMs - _baseTime!;
    final index = (elapsed ~/ _bufferDuration) % _bufferLength;
    _buffer[index].add(frame);

    // Check if we should execute task
    final lastExecution = frame.timeMs - _lastExecutionTime;
    if (lastExecution >= options.interval) {
      final times = (lastExecution ~/ _bufferDuration) - 1;
      _lastExecutionTime = _currentTimestamp;
      for (var i = 0; i < times; i++) {
        _executeTask();
        _lastExecutionTime += _bufferDuration;
      }
    }

    return [];
  }

  void _executeTask() {
    final buffer = _buffer[_index]..sort((a, b) => a.timeMs - b.timeMs);
    final last = buffer.isNotEmpty ? buffer.last : null;

    final expect = last != null ? last.timeMs + options.ptime : _currentTimestamp;

    // Insert dummy packets to fill gaps
    if (expect < _currentTimestamp + _bufferDuration) {
      for (var time = expect;
          time < _currentTimestamp + _bufferDuration;
          time += options.ptime) {
        buffer.add(MuteFrame(
          data: options.dummyPacket,
          isKeyframe: true,
          timeMs: time,
        ));
      }
    }

    _currentTimestamp += _bufferDuration;
    _internalStats['mute'] = DateTime.now().toIso8601String();

    // Clear buffer slot and output frames
    _buffer[_index] = [];
    for (final frame in buffer) {
      _output(MuteOutput(frame: frame));
      _lastCommittedTime = frame.timeMs;
    }

    _index++;
    if (_index == _bufferLength) {
      _index = 0;
    }
  }

  void _stop() {
    _ended = true;
    _buffer = [];
  }

  /// Check if handler has ended
  bool get ended => _ended;
}

/// Factory for creating audio mute handlers with Opus silence
class OpusMuteHandler {
  /// Create a mute handler for Opus audio
  ///
  /// Uses Opus comfort noise / silence packet as dummy.
  static MuteHandler create({
    required void Function(MuteOutput output) output,
    int ptime = 20,
    int interval = 1000,
    int bufferLength = 10,
  }) {
    // Opus silence/comfort noise packet (DTX packet)
    // This is a minimal Opus packet that decodes to silence
    final dummyPacket = Uint8List.fromList([0xF8, 0xFF, 0xFE]);

    return MuteHandler(
      output: output,
      options: MuteHandlerOptions(
        ptime: ptime,
        dummyPacket: dummyPacket,
        interval: interval,
        bufferLength: bufferLength,
      ),
    );
  }
}
