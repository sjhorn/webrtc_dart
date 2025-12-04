import 'dart:typed_data';

import 'container.dart';
import 'ebml/ebml.dart';

/// Maximum signed 16-bit integer (32767)
/// Used as threshold for cluster timestamp wrap-around
const int maxSigned16Int = (0x01 << 16) ~/ 2 - 1;

/// Input frame for WebM processor
class WebmFrame {
  final Uint8List data;
  final bool isKeyframe;
  final int timeMs;
  final int trackNumber;

  WebmFrame({
    required this.data,
    required this.isKeyframe,
    required this.timeMs,
    required this.trackNumber,
  });
}

/// Output from WebM processor
class WebmOutput {
  /// Data to write to file
  final Uint8List? data;

  /// Type of output
  final WebmOutputKind kind;

  /// Previous cluster duration in ms (for progress tracking)
  final int? previousDurationMs;

  /// End of stream info
  final WebmEndOfStream? endOfStream;

  WebmOutput({
    this.data,
    required this.kind,
    this.previousDurationMs,
    this.endOfStream,
  });
}

/// Types of WebM output
enum WebmOutputKind {
  initial,
  cluster,
  block,
  cuePoints,
  endOfStream,
}

/// End of stream information
class WebmEndOfStream {
  final int durationMs;
  final Uint8List durationElement;
  final Uint8List header;

  WebmEndOfStream({
    required this.durationMs,
    required this.durationElement,
    required this.header,
  });
}

/// Track timestamp management for clusters
class _ClusterTimestamp {
  int? baseTimeMs;
  int elapsedMs = 0;
  int _offsetMs = 0;

  void shift(int elapsedMs) {
    _offsetMs += elapsedMs;
  }

  int update(int timeMs) {
    if (baseTimeMs == null) {
      throw StateError('baseTime not initialized');
    }
    elapsedMs = timeMs - baseTimeMs! - _offsetMs;
    return elapsedMs;
  }
}

/// Cue point for seeking
class _CuePoint {
  final WebmContainer builder;
  final int trackNumber;
  final int relativeTimestampMs;
  int position;
  int blockNumber = 0;
  int cuesLength = 0;

  _CuePoint(this.builder, this.trackNumber, this.relativeTimestampMs, this.position);

  EbmlData build() {
    return builder.createCuePoint(
      relativeTimestampMs,
      trackNumber,
      position - 48 + cuesLength,
      blockNumber,
    );
  }
}

/// WebM processor options
class WebmProcessorOptions {
  /// Expected duration in milliseconds
  final int? durationMs;

  /// Strict timestamp mode (reject out-of-order frames)
  final bool strictTimestamp;

  WebmProcessorOptions({
    this.durationMs,
    this.strictTimestamp = false,
  });
}

/// WebM frame processor
///
/// Handles cluster management, timestamp tracking, and cue point generation.
/// Produces WebM data chunks that can be written to a file or stream.
class WebmProcessor {
  final WebmContainer _container;
  final List<WebmTrack> _tracks;
  final WebmProcessorOptions _options;
  final void Function(WebmOutput) _onOutput;

  final Map<int, _ClusterTimestamp> _timestamps = {};
  final List<_CuePoint> _cuePoints = [];

  int _relativeTimestampMs = 0;
  int _position = 0;
  int _clusterCount = 0;
  int? _elapsedMs;

  bool _stopped = false;
  bool _audioStopped = false;
  bool _videoStopped = false;
  bool _videoKeyframeReceived = false;
  bool _started = false;

  WebmProcessor({
    required List<WebmTrack> tracks,
    required void Function(WebmOutput) onOutput,
    WebmProcessorOptions? options,
  })  : _tracks = tracks,
        _container = WebmContainer(tracks),
        _options = options ?? WebmProcessorOptions(),
        _onOutput = onOutput {
    for (final track in tracks) {
      _timestamps[track.trackNumber] = _ClusterTimestamp();
    }
  }

  /// Whether the processor has stopped
  bool get stopped => _stopped;

  /// Whether audio track has stopped
  bool get audioStopped => _audioStopped;

  /// Whether video track has stopped
  bool get videoStopped => _videoStopped;

  /// Whether video keyframe has been received
  bool get videoKeyframeReceived => _videoKeyframeReceived;

  /// Start the processor - writes header and segment
  void start() {
    if (_started) return;
    _started = true;

    final header = _container.ebmlHeader;
    final segment = _container.createSegment(
      duration: _options.durationMs?.toDouble(),
    );

    final staticPart = Uint8List(header.length + segment.length);
    staticPart.setAll(0, header);
    staticPart.setAll(header.length, segment);

    _onOutput(WebmOutput(
      data: staticPart,
      kind: WebmOutputKind.initial,
    ));
    _position += staticPart.length;

    // Add initial cue point for video track
    final videoTrack = _tracks.where((t) => t.kind == TrackKind.video).firstOrNull;
    if (videoTrack != null) {
      _cuePoints.add(_CuePoint(_container, videoTrack.trackNumber, 0, _position));
    }
  }

  /// Process an audio frame
  void processAudioFrame(WebmFrame frame) {
    final track = _tracks.where((t) => t.kind == TrackKind.audio).firstOrNull;
    if (track != null) {
      _processFrame(frame.copyWith(trackNumber: track.trackNumber));
    }
  }

  /// Process a video frame
  void processVideoFrame(WebmFrame frame) {
    if (frame.isKeyframe) {
      _videoKeyframeReceived = true;
    }
    if (!_videoKeyframeReceived && !frame.isKeyframe) {
      return;
    }

    final track = _tracks.where((t) => t.kind == TrackKind.video).firstOrNull;
    if (track != null) {
      _processFrame(frame.copyWith(trackNumber: track.trackNumber));
    }
  }

  /// Process a frame with explicit track number
  void processFrame(WebmFrame frame) {
    _processFrame(frame);
  }

  void _processFrame(WebmFrame frame) {
    if (_stopped) return;

    final track = _tracks.where((t) => t.trackNumber == frame.trackNumber).firstOrNull;
    if (track == null) {
      throw ArgumentError('Track ${frame.trackNumber} not found');
    }

    if (track.kind == TrackKind.audio) {
      _audioStopped = false;
    } else {
      _videoStopped = false;
    }

    _onFrameReceived(frame);
  }

  void _onFrameReceived(WebmFrame frame) {
    final track = _tracks.where((t) => t.trackNumber == frame.trackNumber).firstOrNull;
    if (track == null) return;

    final timestampManager = _timestamps[track.trackNumber]!;

    // Initialize base time for all tracks on first frame
    if (timestampManager.baseTimeMs == null) {
      for (final t in _timestamps.values) {
        t.baseTimeMs = frame.timeMs;
      }
    }

    var elapsedMs = timestampManager.update(frame.timeMs);

    // Create first cluster or new cluster on keyframe/timestamp overflow
    if (_clusterCount == 0) {
      _createCluster(0, 0);
    } else if ((track.kind == TrackKind.video && frame.isKeyframe) ||
        elapsedMs > maxSigned16Int) {
      _relativeTimestampMs += elapsedMs;

      if (elapsedMs != 0) {
        _cuePoints.add(_CuePoint(
          _container,
          track.trackNumber,
          _relativeTimestampMs,
          _position,
        ));

        _createCluster(_relativeTimestampMs, elapsedMs);
        for (final t in _timestamps.values) {
          t.shift(elapsedMs);
        }
        elapsedMs = timestampManager.update(frame.timeMs);
      }
    }

    if (elapsedMs >= 0) {
      _createSimpleBlock(frame, track.trackNumber, elapsedMs);
    }
  }

  void _createCluster(int timestampMs, int durationMs) {
    final cluster = _container.createCluster(timestampMs);
    _clusterCount++;
    _onOutput(WebmOutput(
      data: cluster,
      kind: WebmOutputKind.cluster,
      previousDurationMs: durationMs,
    ));
    _position += cluster.length;
    _elapsedMs = null;
  }

  void _createSimpleBlock(WebmFrame frame, int trackNumber, int elapsedMs) {
    _elapsedMs ??= elapsedMs;

    // Strict timestamp mode: reject out-of-order frames
    if (elapsedMs < _elapsedMs! && _options.strictTimestamp) {
      return;
    }
    _elapsedMs = elapsedMs;

    final block = _container.createSimpleBlock(
      frame.data,
      frame.isKeyframe,
      trackNumber,
      elapsedMs,
    );

    _onOutput(WebmOutput(
      data: block,
      kind: WebmOutputKind.block,
    ));
    _position += block.length;

    // Update block count in latest cue point
    if (_cuePoints.isNotEmpty) {
      _cuePoints.last.blockNumber++;
    }
  }

  /// Mark audio track as ended
  void endAudio() {
    _audioStopped = true;
    if (_tracks.length == 2 && _videoStopped) {
      stop();
    }
  }

  /// Mark video track as ended
  void endVideo() {
    _videoStopped = true;
    if (_tracks.length == 2 && _audioStopped) {
      stop();
    }
  }

  /// Stop the processor and finalize the file
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _videoStopped = true;
    _audioStopped = true;

    // Calculate total duration
    final latestTimestamp = _timestamps.values
        .map((t) => t.elapsedMs)
        .fold(0, (a, b) => a > b ? a : b);
    final durationMs = _relativeTimestampMs + latestTimestamp;

    // Write cue points
    final cues = _container.createCues(_cuePoints.map((c) => c.build()).toList());
    _onOutput(WebmOutput(
      data: cues,
      kind: WebmOutputKind.cuePoints,
      previousDurationMs: durationMs,
    ));

    // Generate updated header with duration
    final durationElement = _container.createDuration(durationMs.toDouble());
    final header = _container.ebmlHeader;
    final segment = _container.createSegment(duration: durationMs.toDouble());
    final fullHeader = Uint8List(header.length + segment.length);
    fullHeader.setAll(0, header);
    fullHeader.setAll(header.length, segment);

    _onOutput(WebmOutput(
      data: null,
      kind: WebmOutputKind.endOfStream,
      endOfStream: WebmEndOfStream(
        durationMs: durationMs,
        durationElement: durationElement,
        header: fullHeader,
      ),
    ));

    _timestamps.clear();
    _cuePoints.clear();
  }
}

extension on WebmFrame {
  WebmFrame copyWith({
    Uint8List? data,
    bool? isKeyframe,
    int? timeMs,
    int? trackNumber,
  }) {
    return WebmFrame(
      data: data ?? this.data,
      isKeyframe: isKeyframe ?? this.isKeyframe,
      timeMs: timeMs ?? this.timeMs,
      trackNumber: trackNumber ?? this.trackNumber,
    );
  }
}
