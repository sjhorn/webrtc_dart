import 'dart:async';

/// Media Track Kind
enum MediaStreamTrackKind {
  audio,
  video,
}

/// Media Track State
enum MediaStreamTrackState {
  live,
  ended,
}

/// Media Stream Track
/// Represents a single media track (audio or video)
/// Based on W3C MediaStreamTrack API
abstract class MediaStreamTrack {
  /// Unique identifier
  final String id;

  /// Track label
  final String label;

  /// Track kind (audio or video)
  final MediaStreamTrackKind kind;

  /// Restriction Identifier (RID) for simulcast
  /// Identifies which simulcast layer this track belongs to (e.g., 'high', 'mid', 'low')
  final String? rid;

  /// Current state
  MediaStreamTrackState _state = MediaStreamTrackState.live;

  /// Muted flag
  bool _muted = false;

  /// Enabled flag (controls whether track is active)
  bool _enabled = true;

  /// State change stream
  final _stateController = StreamController<MediaStreamTrackState>.broadcast();

  /// Mute change stream
  final _muteController = StreamController<bool>.broadcast();

  /// Ended event stream
  final _endedController = StreamController<void>.broadcast();

  MediaStreamTrack({
    required this.id,
    required this.label,
    required this.kind,
    this.rid,
  });

  /// Get current state
  MediaStreamTrackState get state => _state;

  /// Check if track is muted
  bool get muted => _muted;

  /// Check if track is enabled
  bool get enabled => _enabled;

  /// Set enabled state
  set enabled(bool value) {
    if (_enabled != value) {
      _enabled = value;
    }
  }

  /// Stream of state changes
  Stream<MediaStreamTrackState> get onStateChange => _stateController.stream;

  /// Stream of mute changes
  Stream<bool> get onMute => _muteController.stream;

  /// Stream of ended events
  Stream<void> get onEnded => _endedController.stream;

  /// Check if track is audio
  bool get isAudio => kind == MediaStreamTrackKind.audio;

  /// Check if track is video
  bool get isVideo => kind == MediaStreamTrackKind.video;

  /// Stop the track
  void stop() {
    if (_state != MediaStreamTrackState.ended) {
      _state = MediaStreamTrackState.ended;
      _stateController.add(_state);
      _endedController.add(null);
    }
  }

  /// Clone the track
  MediaStreamTrack clone();

  /// Set muted state (internal use)
  void setMuted(bool muted) {
    if (_muted != muted) {
      _muted = muted;
      _muteController.add(_muted);
    }
  }

  /// Dispose resources
  void dispose() {
    stop();
    _stateController.close();
    _muteController.close();
    _endedController.close();
  }

  @override
  String toString() {
    return 'MediaStreamTrack(id=$id, kind=$kind, label=$label, state=$state)';
  }
}

/// Audio Stream Track
/// Represents an audio track
class AudioStreamTrack extends MediaStreamTrack {
  /// Audio samples stream (PCM format)
  final StreamController<AudioFrame> _audioFrameController =
      StreamController<AudioFrame>.broadcast();

  AudioStreamTrack({
    required super.id,
    required super.label,
    super.rid,
  }) : super(kind: MediaStreamTrackKind.audio);

  /// Stream of audio frames
  Stream<AudioFrame> get onAudioFrame => _audioFrameController.stream;

  /// Send audio frame (for source tracks)
  void sendAudioFrame(AudioFrame frame) {
    if (_state == MediaStreamTrackState.live && _enabled) {
      _audioFrameController.add(frame);
    }
  }

  @override
  AudioStreamTrack clone() {
    return AudioStreamTrack(
      id: '${id}_clone_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      rid: rid,
    );
  }

  @override
  void dispose() {
    _audioFrameController.close();
    super.dispose();
  }
}

/// Video Stream Track
/// Represents a video track
class VideoStreamTrack extends MediaStreamTrack {
  /// Video frames stream
  final StreamController<VideoFrame> _videoFrameController =
      StreamController<VideoFrame>.broadcast();

  VideoStreamTrack({
    required super.id,
    required super.label,
    super.rid,
  }) : super(kind: MediaStreamTrackKind.video);

  /// Stream of video frames
  Stream<VideoFrame> get onVideoFrame => _videoFrameController.stream;

  /// Send video frame (for source tracks)
  void sendVideoFrame(VideoFrame frame) {
    if (_state == MediaStreamTrackState.live && _enabled) {
      _videoFrameController.add(frame);
    }
  }

  @override
  VideoStreamTrack clone() {
    return VideoStreamTrack(
      id: '${id}_clone_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      rid: rid,
    );
  }

  @override
  void dispose() {
    _videoFrameController.close();
    super.dispose();
  }
}

/// Audio Frame
/// Container for audio samples
class AudioFrame {
  /// PCM audio samples (interleaved for multi-channel)
  final List<int> samples;

  /// Sample rate (Hz)
  final int sampleRate;

  /// Number of channels (1=mono, 2=stereo)
  final int channels;

  /// Timestamp (microseconds)
  final int timestamp;

  AudioFrame({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.timestamp,
  });

  /// Get duration in microseconds
  int get durationUs {
    final samplesPerChannel = samples.length ~/ channels;
    return (samplesPerChannel * 1000000) ~/ sampleRate;
  }

  @override
  String toString() {
    return 'AudioFrame(samples=${samples.length}, rate=$sampleRate, channels=$channels)';
  }
}

/// Video Frame
/// Container for video frame data
class VideoFrame {
  /// Video frame data (raw or encoded)
  final List<int> data;

  /// Frame width
  final int width;

  /// Frame height
  final int height;

  /// Timestamp (microseconds)
  final int timestamp;

  /// Frame format (e.g., 'I420', 'NV12', 'H264')
  final String format;

  /// Whether this is a keyframe (I-frame)
  final bool keyframe;

  /// Spatial layer ID (for SVC)
  final int? spatialId;

  /// Temporal layer ID (for SVC)
  final int? temporalId;

  VideoFrame({
    required this.data,
    required this.width,
    required this.height,
    required this.timestamp,
    required this.format,
    this.keyframe = false,
    this.spatialId,
    this.temporalId,
  });

  @override
  String toString() {
    final keyInfo = keyframe ? ', keyframe' : '';
    final svcInfo = (spatialId != null || temporalId != null)
        ? ', svc=S${spatialId ?? 0}T${temporalId ?? 0}'
        : '';
    return 'VideoFrame(${width}x$height, format=$format, size=${data.length}$keyInfo$svcInfo)';
  }
}
