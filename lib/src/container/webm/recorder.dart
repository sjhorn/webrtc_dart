import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'container.dart';
import 'processor.dart';

/// Media frame for recording
class MediaFrame {
  final Uint8List data;
  final bool isKeyframe;
  final int timestampMs;
  final MediaFrameKind kind;

  MediaFrame({
    required this.data,
    required this.isKeyframe,
    required this.timestampMs,
    required this.kind,
  });
}

/// Kind of media frame
enum MediaFrameKind {
  video,
  audio,
}

/// Recording state
enum RecorderState {
  inactive,
  recording,
  paused,
  stopped,
}

/// WebM recorder options
class WebmRecorderOptions {
  /// Video width (default: 640)
  final int width;

  /// Video height (default: 480)
  final int height;

  /// Video codec (default: VP8)
  final WebmCodec videoCodec;

  /// Audio codec (default: Opus)
  final WebmCodec audioCodec;

  /// Expected duration in milliseconds (optional)
  final int? durationMs;

  /// Video roll angle for projection (optional)
  final double? roll;

  WebmRecorderOptions({
    this.width = 640,
    this.height = 480,
    this.videoCodec = WebmCodec.vp8,
    this.audioCodec = WebmCodec.opus,
    this.durationMs,
    this.roll,
  });
}

/// WebM media recorder
///
/// Records audio and/or video frames to WebM format.
/// Can output to a file or a stream.
///
/// Usage:
/// ```dart
/// final recorder = WebmRecorder(
///   hasVideo: true,
///   hasAudio: true,
///   options: WebmRecorderOptions(width: 1280, height: 720),
/// );
///
/// // Start recording to file
/// await recorder.startFile('/path/to/output.webm');
///
/// // Or start with stream callback
/// recorder.startStream((data) => socket.add(data));
///
/// // Add frames as they arrive
/// recorder.addVideoFrame(frameData, isKeyframe: true, timestampMs: 0);
/// recorder.addAudioFrame(audioData, timestampMs: 10);
///
/// // Stop recording
/// final result = await recorder.stop();
/// ```
class WebmRecorder {
  final bool hasVideo;
  final bool hasAudio;
  final WebmRecorderOptions options;

  RecorderState _state = RecorderState.inactive;
  WebmProcessor? _processor;
  IOSink? _fileSink;
  void Function(Uint8List)? _streamCallback;
  final List<Uint8List> _buffer = [];
  int _totalBytes = 0;
  DateTime? _startTime;

  /// Stream controller for data events
  final _dataController = StreamController<Uint8List>.broadcast();

  /// Stream controller for error events
  final _errorController = StreamController<Object>.broadcast();

  WebmRecorder({
    this.hasVideo = true,
    this.hasAudio = false,
    WebmRecorderOptions? options,
  }) : options = options ?? WebmRecorderOptions();

  /// Current recorder state
  RecorderState get state => _state;

  /// Total bytes written
  int get totalBytes => _totalBytes;

  /// Recording duration
  Duration? get duration {
    if (_startTime == null) return null;
    return DateTime.now().difference(_startTime!);
  }

  /// Stream of output data chunks
  Stream<Uint8List> get onData => _dataController.stream;

  /// Stream of errors
  Stream<Object> get onError => _errorController.stream;

  /// Start recording to a file
  Future<void> startFile(String path) async {
    if (_state != RecorderState.inactive) {
      throw StateError('Recorder is not inactive');
    }

    final file = File(path);
    _fileSink = file.openWrite();
    _start();
  }

  /// Start recording with a stream callback
  void startStream(void Function(Uint8List data) callback) {
    if (_state != RecorderState.inactive) {
      throw StateError('Recorder is not inactive');
    }

    _streamCallback = callback;
    _start();
  }

  /// Start recording to memory buffer
  void startBuffer() {
    if (_state != RecorderState.inactive) {
      throw StateError('Recorder is not inactive');
    }

    _buffer.clear();
    _start();
  }

  void _start() {
    final tracks = <WebmTrack>[];

    if (hasVideo) {
      tracks.add(WebmTrack(
        trackNumber: 1,
        kind: TrackKind.video,
        codec: options.videoCodec,
        width: options.width,
        height: options.height,
        roll: options.roll,
      ));
    }

    if (hasAudio) {
      tracks.add(WebmTrack(
        trackNumber: hasVideo ? 2 : 1,
        kind: TrackKind.audio,
        codec: options.audioCodec,
      ));
    }

    _processor = WebmProcessor(
      tracks: tracks,
      onOutput: _handleOutput,
      options: WebmProcessorOptions(durationMs: options.durationMs),
    );

    _state = RecorderState.recording;
    _startTime = DateTime.now();
    _totalBytes = 0;

    _processor!.start();
  }

  void _handleOutput(WebmOutput output) {
    if (output.data != null) {
      _writeData(output.data!);
    }

    if (output.kind == WebmOutputKind.endOfStream &&
        output.endOfStream != null) {
      // Could update header with final duration here if needed
    }
  }

  void _writeData(Uint8List data) {
    _totalBytes += data.length;

    // Write to file
    _fileSink?.add(data);

    // Call stream callback
    _streamCallback?.call(data);

    // Add to buffer
    if (_fileSink == null && _streamCallback == null) {
      _buffer.add(data);
    }

    // Emit to stream
    if (!_dataController.isClosed) {
      _dataController.add(data);
    }
  }

  /// Add a video frame
  void addVideoFrame(
    Uint8List data, {
    required bool isKeyframe,
    required int timestampMs,
  }) {
    if (_state != RecorderState.recording) return;
    if (!hasVideo) return;

    _processor?.processVideoFrame(WebmFrame(
      data: data,
      isKeyframe: isKeyframe,
      timeMs: timestampMs,
      trackNumber: 1,
    ));
  }

  /// Add an audio frame
  void addAudioFrame(
    Uint8List data, {
    required int timestampMs,
  }) {
    if (_state != RecorderState.recording) return;
    if (!hasAudio) return;

    final trackNumber = hasVideo ? 2 : 1;
    _processor?.processAudioFrame(WebmFrame(
      data: data,
      isKeyframe: true, // Audio frames are always keyframes
      timeMs: timestampMs,
      trackNumber: trackNumber,
    ));
  }

  /// Add a generic media frame
  void addFrame(MediaFrame frame) {
    if (frame.kind == MediaFrameKind.video) {
      addVideoFrame(frame.data,
          isKeyframe: frame.isKeyframe, timestampMs: frame.timestampMs);
    } else {
      addAudioFrame(frame.data, timestampMs: frame.timestampMs);
    }
  }

  /// Pause recording
  void pause() {
    if (_state == RecorderState.recording) {
      _state = RecorderState.paused;
    }
  }

  /// Resume recording
  void resume() {
    if (_state == RecorderState.paused) {
      _state = RecorderState.recording;
    }
  }

  /// Stop recording and return the result
  Future<WebmRecordingResult> stop() async {
    if (_state == RecorderState.inactive || _state == RecorderState.stopped) {
      throw StateError('Recorder is not active');
    }

    _state = RecorderState.stopped;

    // Stop the processor (writes cue points and end of stream)
    _processor?.stop();

    // Close file
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;

    // Get buffer data if recording to memory
    Uint8List? bufferData;
    if (_buffer.isNotEmpty) {
      final totalLength =
          _buffer.fold<int>(0, (sum, chunk) => sum + chunk.length);
      bufferData = Uint8List(totalLength);
      var offset = 0;
      for (final chunk in _buffer) {
        bufferData.setAll(offset, chunk);
        offset += chunk.length;
      }
      _buffer.clear();
    }

    final result = WebmRecordingResult(
      totalBytes: _totalBytes,
      duration: duration ?? Duration.zero,
      data: bufferData,
    );

    // Clean up
    _processor = null;
    _streamCallback = null;
    _startTime = null;

    return result;
  }

  /// Dispose the recorder
  Future<void> dispose() async {
    if (_state == RecorderState.recording || _state == RecorderState.paused) {
      await stop();
    }

    await _dataController.close();
    await _errorController.close();
  }
}

/// Result of a WebM recording
class WebmRecordingResult {
  /// Total bytes written
  final int totalBytes;

  /// Recording duration
  final Duration duration;

  /// Recorded data (only if recorded to buffer)
  final Uint8List? data;

  WebmRecordingResult({
    required this.totalBytes,
    required this.duration,
    this.data,
  });
}
