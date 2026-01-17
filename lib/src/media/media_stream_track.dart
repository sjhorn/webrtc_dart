import 'dart:async';

import '../srtp/rtp_packet.dart';
import '../srtp/rtcp_packet.dart';

/// Media Track Kind
enum MediaStreamTrackKind {
  audio,
  video,
}

// =============================================================================
// W3C MediaTrackSettings, MediaTrackCapabilities, MediaTrackConstraints
// =============================================================================

/// Media Track Settings
/// Contains the actual values of the constrainable properties of a track.
/// Based on W3C MediaTrackSettings dictionary.
class MediaTrackSettings {
  // Video settings
  final int? width;
  final int? height;
  final double? aspectRatio;
  final double? frameRate;
  final String? facingMode;
  final String? resizeMode;

  // Audio settings
  final int? sampleRate;
  final int? sampleSize;
  final bool? echoCancellation;
  final bool? autoGainControl;
  final bool? noiseSuppression;
  final double? latency;
  final int? channelCount;

  // Common
  final String? deviceId;
  final String? groupId;

  const MediaTrackSettings({
    this.width,
    this.height,
    this.aspectRatio,
    this.frameRate,
    this.facingMode,
    this.resizeMode,
    this.sampleRate,
    this.sampleSize,
    this.echoCancellation,
    this.autoGainControl,
    this.noiseSuppression,
    this.latency,
    this.channelCount,
    this.deviceId,
    this.groupId,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (width != null) json['width'] = width;
    if (height != null) json['height'] = height;
    if (aspectRatio != null) json['aspectRatio'] = aspectRatio;
    if (frameRate != null) json['frameRate'] = frameRate;
    if (facingMode != null) json['facingMode'] = facingMode;
    if (resizeMode != null) json['resizeMode'] = resizeMode;
    if (sampleRate != null) json['sampleRate'] = sampleRate;
    if (sampleSize != null) json['sampleSize'] = sampleSize;
    if (echoCancellation != null) json['echoCancellation'] = echoCancellation;
    if (autoGainControl != null) json['autoGainControl'] = autoGainControl;
    if (noiseSuppression != null) json['noiseSuppression'] = noiseSuppression;
    if (latency != null) json['latency'] = latency;
    if (channelCount != null) json['channelCount'] = channelCount;
    if (deviceId != null) json['deviceId'] = deviceId;
    if (groupId != null) json['groupId'] = groupId;
    return json;
  }

  @override
  String toString() => 'MediaTrackSettings(${toJson()})';
}

/// Range constraint for numeric values
class DoubleRange {
  final double? min;
  final double? max;

  const DoubleRange({this.min, this.max});

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (min != null) json['min'] = min;
    if (max != null) json['max'] = max;
    return json;
  }
}

/// Range constraint for integer values
class ULongRange {
  final int? min;
  final int? max;

  const ULongRange({this.min, this.max});

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (min != null) json['min'] = min;
    if (max != null) json['max'] = max;
    return json;
  }
}

/// Media Track Capabilities
/// Describes the range of values supported by the track.
/// Based on W3C MediaTrackCapabilities dictionary.
class MediaTrackCapabilities {
  // Video capabilities
  final ULongRange? width;
  final ULongRange? height;
  final DoubleRange? aspectRatio;
  final DoubleRange? frameRate;
  final List<String>? facingMode;
  final List<String>? resizeMode;

  // Audio capabilities
  final ULongRange? sampleRate;
  final ULongRange? sampleSize;
  final List<bool>? echoCancellation;
  final List<bool>? autoGainControl;
  final List<bool>? noiseSuppression;
  final DoubleRange? latency;
  final ULongRange? channelCount;

  // Common
  final String? deviceId;
  final String? groupId;

  const MediaTrackCapabilities({
    this.width,
    this.height,
    this.aspectRatio,
    this.frameRate,
    this.facingMode,
    this.resizeMode,
    this.sampleRate,
    this.sampleSize,
    this.echoCancellation,
    this.autoGainControl,
    this.noiseSuppression,
    this.latency,
    this.channelCount,
    this.deviceId,
    this.groupId,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (width != null) json['width'] = width!.toJson();
    if (height != null) json['height'] = height!.toJson();
    if (aspectRatio != null) json['aspectRatio'] = aspectRatio!.toJson();
    if (frameRate != null) json['frameRate'] = frameRate!.toJson();
    if (facingMode != null) json['facingMode'] = facingMode;
    if (resizeMode != null) json['resizeMode'] = resizeMode;
    if (sampleRate != null) json['sampleRate'] = sampleRate!.toJson();
    if (sampleSize != null) json['sampleSize'] = sampleSize!.toJson();
    if (echoCancellation != null) json['echoCancellation'] = echoCancellation;
    if (autoGainControl != null) json['autoGainControl'] = autoGainControl;
    if (noiseSuppression != null) json['noiseSuppression'] = noiseSuppression;
    if (latency != null) json['latency'] = latency!.toJson();
    if (channelCount != null) json['channelCount'] = channelCount!.toJson();
    if (deviceId != null) json['deviceId'] = deviceId;
    if (groupId != null) json['groupId'] = groupId;
    return json;
  }

  @override
  String toString() => 'MediaTrackCapabilities(${toJson()})';
}

/// Constraint value that can be exact, ideal, min, or max
class ConstraintValue<T> {
  final T? exact;
  final T? ideal;
  final T? min;
  final T? max;

  const ConstraintValue({this.exact, this.ideal, this.min, this.max});

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (exact != null) json['exact'] = exact;
    if (ideal != null) json['ideal'] = ideal;
    if (min != null) json['min'] = min;
    if (max != null) json['max'] = max;
    return json;
  }
}

/// Media Track Constraints
/// Specifies the desired values for constrainable properties.
/// Based on W3C MediaTrackConstraints dictionary.
class MediaTrackConstraints {
  // Video constraints
  final dynamic width; // int, ConstraintValue<int>, or null
  final dynamic height;
  final dynamic aspectRatio;
  final dynamic frameRate;
  final dynamic facingMode;
  final dynamic resizeMode;

  // Audio constraints
  final dynamic sampleRate;
  final dynamic sampleSize;
  final dynamic echoCancellation;
  final dynamic autoGainControl;
  final dynamic noiseSuppression;
  final dynamic latency;
  final dynamic channelCount;

  // Common
  final dynamic deviceId;
  final dynamic groupId;

  // Advanced constraints (array of constraint sets)
  final List<MediaTrackConstraints>? advanced;

  const MediaTrackConstraints({
    this.width,
    this.height,
    this.aspectRatio,
    this.frameRate,
    this.facingMode,
    this.resizeMode,
    this.sampleRate,
    this.sampleSize,
    this.echoCancellation,
    this.autoGainControl,
    this.noiseSuppression,
    this.latency,
    this.channelCount,
    this.deviceId,
    this.groupId,
    this.advanced,
  });

  /// Create empty constraints
  factory MediaTrackConstraints.empty() => const MediaTrackConstraints();

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (width != null) json['width'] = _constraintToJson(width);
    if (height != null) json['height'] = _constraintToJson(height);
    if (aspectRatio != null) {
      json['aspectRatio'] = _constraintToJson(aspectRatio);
    }
    if (frameRate != null) json['frameRate'] = _constraintToJson(frameRate);
    if (facingMode != null) json['facingMode'] = _constraintToJson(facingMode);
    if (resizeMode != null) json['resizeMode'] = _constraintToJson(resizeMode);
    if (sampleRate != null) json['sampleRate'] = _constraintToJson(sampleRate);
    if (sampleSize != null) json['sampleSize'] = _constraintToJson(sampleSize);
    if (echoCancellation != null) {
      json['echoCancellation'] = _constraintToJson(echoCancellation);
    }
    if (autoGainControl != null) {
      json['autoGainControl'] = _constraintToJson(autoGainControl);
    }
    if (noiseSuppression != null) {
      json['noiseSuppression'] = _constraintToJson(noiseSuppression);
    }
    if (latency != null) json['latency'] = _constraintToJson(latency);
    if (channelCount != null) {
      json['channelCount'] = _constraintToJson(channelCount);
    }
    if (deviceId != null) json['deviceId'] = _constraintToJson(deviceId);
    if (groupId != null) json['groupId'] = _constraintToJson(groupId);
    if (advanced != null) {
      json['advanced'] = advanced!.map((c) => c.toJson()).toList();
    }
    return json;
  }

  dynamic _constraintToJson(dynamic value) {
    if (value is ConstraintValue) {
      return value.toJson();
    }
    return value;
  }

  @override
  String toString() => 'MediaTrackConstraints(${toJson()})';
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

  /// Raw RTP packet stream (for raw RTP forwarding)
  final _rtpController = StreamController<RtpPacket>.broadcast();

  /// Raw RTCP packet stream
  final _rtcpController = StreamController<RtcpPacket>.broadcast();

  /// Applied constraints (stored when applyConstraints is called)
  MediaTrackConstraints _constraints = const MediaTrackConstraints();

  /// Current settings (can be updated by subclasses)
  MediaTrackSettings _settings = const MediaTrackSettings();

  MediaStreamTrack({
    required this.id,
    required this.label,
    required this.kind,
    this.rid,
  });

  /// Get current state
  MediaStreamTrackState get state => _state;

  /// Ready state (W3C standard name for 'state')
  MediaStreamTrackState get readyState => _state;

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

  /// Stream of received RTP packets (raw packets before depacketization)
  /// Use this for forwarding/relaying RTP to other destinations
  Stream<RtpPacket> get onReceiveRtp => _rtpController.stream;

  /// Stream of received RTCP packets
  Stream<RtcpPacket> get onReceiveRtcp => _rtcpController.stream;

  /// Check if track is audio
  bool get isAudio => kind == MediaStreamTrackKind.audio;

  /// Check if track is video
  bool get isVideo => kind == MediaStreamTrackKind.video;

  // ===========================================================================
  // W3C Standard Constraints API
  // ===========================================================================

  /// Get current settings
  ///
  /// Returns a MediaTrackSettings object containing the current values
  /// of each constrainable property.
  MediaTrackSettings getSettings() => _settings;

  /// Get capabilities
  ///
  /// Returns a MediaTrackCapabilities object describing the range of
  /// values supported by the track. For server-side Dart, this returns
  /// default capabilities since we don't control physical devices.
  MediaTrackCapabilities getCapabilities() {
    if (kind == MediaStreamTrackKind.audio) {
      return const MediaTrackCapabilities(
        sampleRate: ULongRange(min: 8000, max: 48000),
        sampleSize: ULongRange(min: 8, max: 32),
        channelCount: ULongRange(min: 1, max: 2),
        echoCancellation: [true, false],
        autoGainControl: [true, false],
        noiseSuppression: [true, false],
        latency: DoubleRange(min: 0.0, max: 1.0),
      );
    } else {
      return const MediaTrackCapabilities(
        width: ULongRange(min: 1, max: 4096),
        height: ULongRange(min: 1, max: 2160),
        aspectRatio: DoubleRange(min: 0.5, max: 3.0),
        frameRate: DoubleRange(min: 1.0, max: 60.0),
        resizeMode: ['none', 'crop-and-scale'],
      );
    }
  }

  /// Get constraints
  ///
  /// Returns the constraints that were most recently applied to the track
  /// via applyConstraints().
  MediaTrackConstraints getConstraints() => _constraints;

  /// Apply constraints
  ///
  /// Applies a set of constraints to the track. For server-side Dart,
  /// this stores the constraints and updates settings where applicable.
  /// Returns a Future that resolves when constraints are applied.
  ///
  /// Throws [OverconstrainedError] if the constraints cannot be satisfied.
  Future<void> applyConstraints([MediaTrackConstraints? constraints]) async {
    _constraints = constraints ?? const MediaTrackConstraints();

    // For server-side implementation, we just store the constraints
    // and update settings to reflect what was requested.
    // A real device implementation would validate and apply these.
    _updateSettingsFromConstraints(_constraints);
  }

  /// Update settings based on applied constraints
  void _updateSettingsFromConstraints(MediaTrackConstraints constraints) {
    // Extract values from constraints (handling both direct values and ConstraintValue)
    int? extractInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is ConstraintValue<int>) return value.exact ?? value.ideal;
      return null;
    }

    double? extractDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is ConstraintValue<double>) return value.exact ?? value.ideal;
      if (value is ConstraintValue<int>) {
        return (value.exact ?? value.ideal)?.toDouble();
      }
      return null;
    }

    bool? extractBool(dynamic value) {
      if (value == null) return null;
      if (value is bool) return value;
      if (value is ConstraintValue<bool>) return value.exact ?? value.ideal;
      return null;
    }

    String? extractString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is ConstraintValue<String>) return value.exact ?? value.ideal;
      return null;
    }

    if (kind == MediaStreamTrackKind.audio) {
      _settings = MediaTrackSettings(
        sampleRate: extractInt(constraints.sampleRate) ?? _settings.sampleRate,
        sampleSize: extractInt(constraints.sampleSize) ?? _settings.sampleSize,
        channelCount:
            extractInt(constraints.channelCount) ?? _settings.channelCount,
        echoCancellation: extractBool(constraints.echoCancellation) ??
            _settings.echoCancellation,
        autoGainControl: extractBool(constraints.autoGainControl) ??
            _settings.autoGainControl,
        noiseSuppression: extractBool(constraints.noiseSuppression) ??
            _settings.noiseSuppression,
        latency: extractDouble(constraints.latency) ?? _settings.latency,
        deviceId: extractString(constraints.deviceId) ?? _settings.deviceId,
        groupId: extractString(constraints.groupId) ?? _settings.groupId,
      );
    } else {
      final width = extractInt(constraints.width);
      final height = extractInt(constraints.height);
      double? aspectRatio = extractDouble(constraints.aspectRatio);
      if (aspectRatio == null &&
          width != null &&
          height != null &&
          height > 0) {
        aspectRatio = width / height;
      }

      _settings = MediaTrackSettings(
        width: width ?? _settings.width,
        height: height ?? _settings.height,
        aspectRatio: aspectRatio ?? _settings.aspectRatio,
        frameRate: extractDouble(constraints.frameRate) ?? _settings.frameRate,
        facingMode:
            extractString(constraints.facingMode) ?? _settings.facingMode,
        resizeMode:
            extractString(constraints.resizeMode) ?? _settings.resizeMode,
        deviceId: extractString(constraints.deviceId) ?? _settings.deviceId,
        groupId: extractString(constraints.groupId) ?? _settings.groupId,
      );
    }
  }

  /// Update settings directly (for use by subclasses or receivers)
  void updateSettings(MediaTrackSettings settings) {
    _settings = settings;
  }

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

  /// Called when RTP packet is received (internal use)
  /// This emits the raw RTP packet before any depacketization
  void receiveRtp(RtpPacket packet) {
    if (_state == MediaStreamTrackState.live) {
      _rtpController.add(packet);
    }
  }

  /// Called when RTCP packet is received (internal use)
  void receiveRtcp(RtcpPacket packet) {
    if (_state == MediaStreamTrackState.live) {
      _rtcpController.add(packet);
    }
  }

  /// Dispose resources
  void dispose() {
    stop();
    _stateController.close();
    _muteController.close();
    _endedController.close();
    _rtpController.close();
    _rtcpController.close();
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
