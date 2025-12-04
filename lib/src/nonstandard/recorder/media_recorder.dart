/// MediaRecorder - High-level recording API
///
/// Records audio and/or video from MediaStreamTracks to WebM format.
/// Integrates the full processing pipeline:
/// RTP -> JitterBuffer -> NtpTime -> Depacketizer -> LipSync -> WebM
///
/// Ported from werift-webrtc MediaRecorder
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../audio/lipsync.dart' as lipsync;
import '../../container/webm/container.dart';
import '../../container/webm/processor.dart';
import '../../rtp/jitter_buffer.dart';
import '../../rtp/rtcp_reports.dart';
import '../../srtp/rtp_packet.dart';
import '../../srtp/rtcp_packet.dart';
import 'pipeline.dart';


/// Track info for recording
class RecordingTrack {
  /// Track kind ('audio' or 'video')
  final String kind;

  /// Codec name (e.g., 'VP8', 'VP9', 'H264', 'AV1', 'opus')
  final String codecName;

  /// Payload type from SDP
  final int payloadType;

  /// Clock rate (e.g., 90000 for video, 48000 for audio)
  final int clockRate;

  /// Callback to receive RTP packets
  final void Function(void Function(RtpPacket rtp) handler)? onRtp;

  /// Callback to receive RTCP packets
  final void Function(void Function(RtcpPacket rtcp) handler)? onRtcp;

  /// Callback to signal track ended
  final void Function(void Function() handler)? onEnded;

  RecordingTrack({
    required this.kind,
    required this.codecName,
    required this.payloadType,
    required this.clockRate,
    this.onRtp,
    this.onRtcp,
    this.onEnded,
  });

  bool get isVideo => kind == 'video';
  bool get isAudio => kind == 'audio';
}

/// MediaRecorder options
class MediaRecorderOptions {
  /// Video width (default: 640)
  final int width;

  /// Video height (default: 360)
  final int height;

  /// Video roll angle for projection (optional)
  final double? roll;

  /// Disable lip sync (A/V synchronization)
  final bool disableLipSync;

  /// Disable NTP-based timing (use RTP timestamps instead)
  final bool disableNtp;

  /// Default duration in ms if track doesn't signal end
  final int defaultDuration;

  /// Lip sync options
  final lipsync.LipSyncOptions lipsyncOptions;

  /// Jitter buffer options
  final JitterBufferOptions jitterBufferOptions;

  const MediaRecorderOptions({
    this.width = 640,
    this.height = 360,
    this.roll,
    this.disableLipSync = false,
    this.disableNtp = false,
    this.defaultDuration = 1000 * 60 * 60 * 24, // 24 hours
    this.lipsyncOptions = const lipsync.LipSyncOptions(),
    this.jitterBufferOptions = const JitterBufferOptions(),
  });
}

/// MediaRecorder for recording WebRTC streams
///
/// Usage:
/// ```dart
/// final recorder = MediaRecorder(
///   tracks: [videoTrack, audioTrack],
///   path: '/path/to/output.webm',
///   options: MediaRecorderOptions(width: 1280, height: 720),
/// );
///
/// // Wait for tracks to be added
/// await recorder.start();
///
/// // ... recording happens automatically via RTP callbacks ...
///
/// // Stop and finalize
/// await recorder.stop();
/// ```
class MediaRecorder {
  /// Recording tracks
  final List<RecordingTrack> tracks;

  /// Output file path (optional - can use stream callback instead)
  final String? path;

  /// Stream callback for data chunks
  final void Function(WebmOutput output)? onOutput;

  /// Recorder options
  final MediaRecorderOptions options;

  /// Error callback
  void Function(Object error)? onError;

  /// Track pipelines
  final Map<int, TrackPipeline> _pipelines = {};

  /// Lip sync processor
  lipsync.LipSyncProcessor? _lipsync;

  /// WebM processor
  WebmProcessor? _webmProcessor;

  /// File sink for writing
  IOSink? _fileSink;

  /// Track subscriptions
  final List<StreamSubscription> _subscriptions = [];

  /// Whether recording has started
  bool _started = false;

  /// Whether recording has stopped
  bool _stopped = false;

  /// Statistics
  final Map<String, dynamic> _stats = {};

  MediaRecorder({
    required this.tracks,
    this.path,
    this.onOutput,
    this.options = const MediaRecorderOptions(),
    this.onError,
  }) {
    if (tracks.isEmpty) {
      throw ArgumentError('At least one track is required');
    }
    if (path == null && onOutput == null) {
      throw ArgumentError('Either path or onOutput must be provided');
    }
  }

  /// Start recording
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Delete existing file if any
    if (path != null) {
      try {
        await File(path!).delete();
      } catch (_) {}
      _fileSink = File(path!).openWrite();
    }

    // Build track info for WebM container
    final webmTracks = <WebmTrack>[];
    var trackNumber = 1;

    for (final track in tracks) {
      final codec = _getWebmCodec(track.codecName, track.isVideo);
      final clockRate = track.clockRate;

      webmTracks.add(WebmTrack(
        trackNumber: trackNumber,
        kind: track.isVideo ? TrackKind.video : TrackKind.audio,
        codec: codec,
        width: track.isVideo ? options.width : null,
        height: track.isVideo ? options.height : null,
        roll: track.isVideo ? options.roll : null,
      ));

      // Create processing pipeline for this track
      final pipeline = TrackPipeline(
        trackNumber: trackNumber,
        codec: _getDepacketizerCodec(track.codecName),
        clockRate: clockRate,
        isVideo: track.isVideo,
        disableNtp: options.disableNtp,
        jitterBufferOptions: options.jitterBufferOptions,
      );

      _pipelines[trackNumber] = pipeline;
      trackNumber++;
    }

    // Create WebM processor
    _webmProcessor = WebmProcessor(
      tracks: webmTracks,
      onOutput: _handleWebmOutput,
      options: WebmProcessorOptions(durationMs: options.defaultDuration),
    );

    // Create lip sync if enabled and we have both audio and video
    final hasVideo = tracks.any((t) => t.isVideo);
    final hasAudio = tracks.any((t) => t.isAudio);

    if (!options.disableLipSync && hasVideo && hasAudio) {
      _lipsync = lipsync.LipSyncProcessor(
        options: options.lipsyncOptions,
        onAudioFrame: (frame) {
          _webmProcessor?.processAudioFrame(WebmFrame(
            data: frame.data,
            isKeyframe: frame.isKeyframe,
            timeMs: frame.timestamp,
            trackNumber: _getAudioTrackNumber(),
          ));
        },
        onVideoFrame: (frame) {
          _webmProcessor?.processVideoFrame(WebmFrame(
            data: frame.data,
            isKeyframe: frame.isKeyframe,
            timeMs: frame.timestamp,
            trackNumber: _getVideoTrackNumber(),
          ));
        },
      );

      // Wire pipelines to lip sync
      for (final entry in _pipelines.entries) {
        final pipeline = entry.value;
        final isVideo = pipeline.isVideo;

        pipeline.onFrame = (frame) {
          final mediaFrame = lipsync.MediaFrame(
            timestamp: frame.timeMs,
            data: frame.data,
            isKeyframe: frame.isKeyframe,
            kind: isVideo ? lipsync.MediaKind.video : lipsync.MediaKind.audio,
          );

          if (isVideo) {
            _lipsync!.processVideoFrame(mediaFrame);
          } else {
            _lipsync!.processAudioFrame(mediaFrame);
          }
        };
      }
    } else {
      // No lip sync - wire pipelines directly to WebM
      for (final entry in _pipelines.entries) {
        final trackNum = entry.key;
        final pipeline = entry.value;
        final isVideo = pipeline.isVideo;

        pipeline.onFrame = (frame) {
          if (isVideo) {
            _webmProcessor?.processVideoFrame(WebmFrame(
              data: frame.data,
              isKeyframe: frame.isKeyframe,
              timeMs: frame.timeMs,
              trackNumber: trackNum,
            ));
          } else {
            _webmProcessor?.processAudioFrame(WebmFrame(
              data: frame.data,
              isKeyframe: frame.isKeyframe,
              timeMs: frame.timeMs,
              trackNumber: trackNum,
            ));
          }
        };
      }
    }

    // Start WebM processor (writes header)
    _webmProcessor!.start();

    // Subscribe to track RTP/RTCP events
    trackNumber = 1;
    for (final track in tracks) {
      final pipeline = _pipelines[trackNumber]!;

      track.onRtp?.call((rtp) {
        if (!_stopped) {
          pipeline.processRtp(rtp);
        }
      });

      track.onRtcp?.call((rtcp) {
        if (!_stopped && rtcp.packetType == RtcpPacketType.senderReport) {
          final sr = RtcpSenderReport.fromPacket(rtcp);
          pipeline.processRtcp(sr);
        }
      });

      track.onEnded?.call(() {
        if (pipeline.isVideo) {
          _webmProcessor?.endVideo();
        } else {
          _webmProcessor?.endAudio();
        }
      });

      trackNumber++;
    }
  }

  /// Manually feed RTP packet to recorder
  ///
  /// Use this when not using track callbacks
  void feedRtp(RtpPacket rtp, {required int trackNumber}) {
    if (_stopped || !_started) return;
    _pipelines[trackNumber]?.processRtp(rtp);
  }

  /// Manually feed RTCP packet to recorder
  ///
  /// Use this when not using track callbacks
  void feedRtcp(RtcpSenderReport sr, {required int trackNumber}) {
    if (_stopped || !_started) return;
    _pipelines[trackNumber]?.processRtcp(sr);
  }

  void _handleWebmOutput(WebmOutput output) {
    if (output.data != null) {
      _fileSink?.add(output.data!);
      onOutput?.call(output);
      _stats['bytesWritten'] =
          (_stats['bytesWritten'] ?? 0) + output.data!.length;
    }

    if (output.kind == WebmOutputKind.endOfStream) {
      _stats['stopped'] = DateTime.now().toIso8601String();
    }
  }

  /// Stop recording and finalize the file
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;

    // Flush lip sync
    _lipsync?.flush();
    _lipsync?.stop();

    // End all track pipelines
    for (final pipeline in _pipelines.values) {
      pipeline.endOfStream();
    }

    // Stop WebM processor
    _webmProcessor?.stop();

    // Close file
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;

    // Update file header with final duration (if path provided)
    if (path != null) {
      await _updateFileHeader();
    }

    // Cleanup subscriptions
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> _updateFileHeader() async {
    if (path == null) return;

    final file = File(path!);
    if (!await file.exists()) return;

    // The WebM processor outputs the final header in endOfStream
    // For seekable files, we could update the segment size and duration
    // This is optional - the file is still valid without it
  }

  int _getVideoTrackNumber() {
    for (final entry in _pipelines.entries) {
      if (entry.value.isVideo) return entry.key;
    }
    return 1;
  }

  int _getAudioTrackNumber() {
    for (final entry in _pipelines.entries) {
      if (!entry.value.isVideo) return entry.key;
    }
    return 2;
  }

  WebmCodec _getWebmCodec(String codecName, bool isVideo) {
    if (!isVideo) {
      return WebmCodec.opus;
    }

    switch (codecName.toLowerCase()) {
      case 'vp8':
        return WebmCodec.vp8;
      case 'vp9':
        return WebmCodec.vp9;
      case 'h264':
        return WebmCodec.h264;
      case 'av1':
      case 'av1x':
        return WebmCodec.av1;
      default:
        throw ArgumentError('Unsupported video codec: $codecName');
    }
  }

  DepacketizerCodec _getDepacketizerCodec(String codecName) {
    switch (codecName.toLowerCase()) {
      case 'vp8':
        return DepacketizerCodec.vp8;
      case 'vp9':
        return DepacketizerCodec.vp9;
      case 'h264':
        return DepacketizerCodec.h264;
      case 'av1':
      case 'av1x':
        return DepacketizerCodec.av1;
      case 'opus':
        return DepacketizerCodec.opus;
      default:
        throw ArgumentError('Unsupported codec: $codecName');
    }
  }

  /// Get recording statistics
  Map<String, dynamic> toJson() => {
        ..._stats,
        'started': _started,
        'stopped': _stopped,
        'trackCount': tracks.length,
        'pipelines': _pipelines.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'lipsync': _lipsync?.toJson(),
      };
}

/// Simple WebM recorder for direct frame input
///
/// Use this when you have decoded frames ready to record,
/// without needing the full RTP processing pipeline.
///
/// For RTP-based recording, use [MediaRecorder] instead.
class SimpleWebmRecorder {
  /// Output file path (optional)
  final String? path;

  /// Stream callback for data chunks
  final void Function(Uint8List data)? onData;

  /// Video width
  final int width;

  /// Video height
  final int height;

  /// Video codec
  final WebmCodec videoCodec;

  /// Include audio
  final bool hasAudio;

  /// Include video
  final bool hasVideo;

  WebmProcessor? _processor;
  IOSink? _fileSink;
  bool _started = false;
  bool _stopped = false;
  int _totalBytes = 0;

  SimpleWebmRecorder({
    this.path,
    this.onData,
    this.width = 640,
    this.height = 480,
    this.videoCodec = WebmCodec.vp8,
    this.hasVideo = true,
    this.hasAudio = false,
  });

  /// Start recording
  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (path != null) {
      try {
        await File(path!).delete();
      } catch (_) {}
      _fileSink = File(path!).openWrite();
    }

    final tracks = <WebmTrack>[];
    var trackNum = 1;

    if (hasVideo) {
      tracks.add(WebmTrack(
        trackNumber: trackNum++,
        kind: TrackKind.video,
        codec: videoCodec,
        width: width,
        height: height,
      ));
    }

    if (hasAudio) {
      tracks.add(WebmTrack(
        trackNumber: trackNum++,
        kind: TrackKind.audio,
        codec: WebmCodec.opus,
      ));
    }

    _processor = WebmProcessor(
      tracks: tracks,
      onOutput: (output) {
        if (output.data != null) {
          _totalBytes += output.data!.length;
          _fileSink?.add(output.data!);
          onData?.call(output.data!);
        }
      },
    );

    _processor!.start();
  }

  /// Add a video frame
  void addVideoFrame(Uint8List data, {required bool isKeyframe, required int timestampMs}) {
    if (!_started || _stopped || !hasVideo) return;

    _processor?.processVideoFrame(WebmFrame(
      data: data,
      isKeyframe: isKeyframe,
      timeMs: timestampMs,
      trackNumber: 1,
    ));
  }

  /// Add an audio frame
  void addAudioFrame(Uint8List data, {required int timestampMs}) {
    if (!_started || _stopped || !hasAudio) return;

    final trackNumber = hasVideo ? 2 : 1;
    _processor?.processAudioFrame(WebmFrame(
      data: data,
      isKeyframe: true,
      timeMs: timestampMs,
      trackNumber: trackNumber,
    ));
  }

  /// Stop recording
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;

    _processor?.stop();

    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
  }

  /// Total bytes written
  int get totalBytes => _totalBytes;

  /// Whether recording is active
  bool get isRecording => _started && !_stopped;
}
