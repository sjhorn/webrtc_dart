/// UserMedia - Media player abstraction
///
/// Provides media players for MP4 and WebM files using external
/// tools like FFmpeg or GStreamer to convert media to RTP.
///
/// Ported from werift-webrtc userMedia.ts
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../srtp/rtp_packet.dart';
import 'track.dart';

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

/// Get user media from a file
///
/// Creates a media player that reads from a file and produces RTP.
/// Supports MP4 and WebM files via FFmpeg.
Future<MediaPlayer> getUserMedia({
  required String path,
  bool loop = false,
  int? width,
  int? height,
}) async {
  final audioPort = await _getRandomPort();
  final videoPort = await _getRandomPort();

  if (path.endsWith('.mp4')) {
    return MediaPlayerMp4(
      path: path,
      audioPort: audioPort,
      videoPort: videoPort,
      loop: loop,
      width: width,
      height: height,
    );
  } else {
    return MediaPlayerWebm(
      path: path,
      audioPort: audioPort,
      videoPort: videoPort,
      loop: loop,
      width: width,
      height: height,
    );
  }
}

Future<int> _getRandomPort() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final port = socket.port;
  socket.close();
  return port;
}

/// Abstract base class for media players
abstract class MediaPlayer {
  /// Stream ID for tracks
  final String streamId = _generateUuid();

  /// Audio track
  late MediaStreamTrack audio;

  /// Video track
  late MediaStreamTrack video;

  /// Whether player is stopped
  bool stopped = false;

  /// FFmpeg/GStreamer process
  Process? _process;

  /// Audio UDP socket
  RawDatagramSocket? _audioSocket;

  /// Video UDP socket
  RawDatagramSocket? _videoSocket;

  /// File path
  final String path;

  /// Audio port
  final int audioPort;

  /// Video port
  final int videoPort;

  /// Loop playback
  final bool loop;

  /// Video width (optional)
  final int? width;

  /// Video height (optional)
  final int? height;

  MediaPlayer({
    required this.path,
    required this.audioPort,
    required this.videoPort,
    this.loop = false,
    this.width,
    this.height,
  }) {
    audio = MediaStreamTrack(kind: MediaKind.audio, streamId: streamId);
    video = MediaStreamTrack(kind: MediaKind.video, streamId: streamId);
  }

  /// Setup UDP listeners for tracks
  Future<void> _setupSockets() async {
    int? audioPayloadType;
    int? videoPayloadType;

    _audioSocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, audioPort);
    _audioSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _audioSocket!.receive();
        if (datagram != null) {
          final rtp = RtpPacket.parse(datagram.data);

          // Detect source restart (payload type change)
          if (audioPayloadType == null) {
            audioPayloadType = rtp.payloadType;
          } else if (audioPayloadType != rtp.payloadType) {
            audioPayloadType = rtp.payloadType;
            audio.notifySourceChanged(RtpHeaderInfo.fromPacket(rtp));
          }

          audio.writeRtp(datagram.data);
        }
      }
    });

    _videoSocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, videoPort);
    _videoSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _videoSocket!.receive();
        if (datagram != null) {
          final rtp = RtpPacket.parse(datagram.data);

          // Detect source restart (payload type change)
          if (videoPayloadType == null) {
            videoPayloadType = rtp.payloadType;
          } else if (videoPayloadType != rtp.payloadType) {
            videoPayloadType = rtp.payloadType;
            video.notifySourceChanged(RtpHeaderInfo.fromPacket(rtp));
          }

          video.writeRtp(datagram.data);
        }
      }
    });
  }

  /// Start the media player
  Future<void> start();

  /// Stop the media player
  void stop() {
    stopped = true;
    _process?.kill(ProcessSignal.sigint);
    _audioSocket?.close();
    _videoSocket?.close();
    audio.stop();
    video.stop();
  }

  /// Get media stream with both tracks
  MediaStream getStream() {
    return MediaStream([video, audio]);
  }
}

/// Media player for MP4 files
///
/// Uses FFmpeg to demux and transcode MP4 to RTP.
class MediaPlayerMp4 extends MediaPlayer {
  MediaPlayerMp4({
    required super.path,
    required super.audioPort,
    required super.videoPort,
    super.loop,
    super.width,
    super.height,
  });

  @override
  Future<void> start() async {
    await _setupSockets();
    await _run();
  }

  Future<void> _run() async {
    var payloadType = 96;

    // Build FFmpeg command
    final args = <String>[
      '-re', // Real-time playback
      if (loop) ...['-stream_loop', '-1'],
      '-i', path,
    ];

    if (width != null && height != null) {
      // Transcode video with scaling
      args.addAll([
        '-vf',
        'scale=$width:$height',
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-tune',
        'zerolatency',
        '-f',
        'rtp',
        '-payload_type',
        '${payloadType++}',
        'rtp://127.0.0.1:$videoPort',
      ]);
    } else {
      // Pass-through video
      args.addAll([
        '-c:v',
        'copy',
        '-f',
        'rtp',
        '-payload_type',
        '${payloadType++}',
        'rtp://127.0.0.1:$videoPort',
      ]);

      // Add audio stream
      args.addAll([
        '-c:a',
        'libopus',
        '-ar',
        '48000',
        '-ac',
        '2',
        '-f',
        'rtp',
        '-payload_type',
        '${payloadType++}',
        'rtp://127.0.0.1:$audioPort',
      ]);
    }

    _process = await Process.start('ffmpeg', args);

    // Handle process completion for looping
    if (loop) {
      _process!.exitCode.then((_) {
        if (!stopped) {
          _run();
        }
      });
    }
  }
}

/// Media player for WebM files
///
/// Uses FFmpeg to demux WebM (VP8/VP9 + Opus) to RTP.
class MediaPlayerWebm extends MediaPlayer {
  MediaPlayerWebm({
    required super.path,
    required super.audioPort,
    required super.videoPort,
    super.loop,
    super.width,
    super.height,
  });

  @override
  Future<void> start() async {
    await _setupSockets();
    await _run();
  }

  Future<void> _run() async {
    var payloadType = 96;

    // Build FFmpeg command for WebM
    final args = <String>[
      '-re', // Real-time playback
      if (loop) ...['-stream_loop', '-1'],
      '-i', path,
      // Video stream (VP8/VP9)
      '-c:v', 'copy',
      '-f', 'rtp',
      '-payload_type', '${payloadType++}',
      'rtp://127.0.0.1:$videoPort',
      // Audio stream (Opus)
      '-c:a', 'copy',
      '-f', 'rtp',
      '-payload_type', '${payloadType++}',
      'rtp://127.0.0.1:$audioPort',
    ];

    _process = await Process.start('ffmpeg', args);

    // Handle process completion for looping
    if (loop) {
      _process!.exitCode.then((_) {
        if (!stopped) {
          _run();
        }
      });
    }
  }
}

/// GStreamer-based media player for advanced use cases
///
/// Provides finer control over pipeline for complex scenarios.
class GStreamerPlayer extends MediaPlayer {
  /// GStreamer pipeline command
  final String Function(int videoPort, int audioPort, int payloadType)
      pipelineBuilder;

  GStreamerPlayer({
    required super.path,
    required super.audioPort,
    required super.videoPort,
    required this.pipelineBuilder,
    super.loop,
    super.width,
    super.height,
  });

  @override
  Future<void> start() async {
    await _setupSockets();
    await _run();
  }

  Future<void> _run() async {
    final pipeline = pipelineBuilder(videoPort, audioPort, 96);

    _process = await Process.start('gst-launch-1.0', pipeline.split(' '));

    if (loop) {
      _process!.exitCode.then((_) {
        if (!stopped) {
          _run();
        }
      });
    }
  }
}
