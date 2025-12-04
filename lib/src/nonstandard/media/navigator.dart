/// Navigator/MediaDevices - getUserMedia abstraction
///
/// Provides Navigator and MediaDevices classes for media access,
/// following the W3C WebRTC API pattern.
///
/// Ported from werift-webrtc navigator.ts
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../srtp/rtp_packet.dart';
import 'track.dart';

/// Media stream constraints
class MediaStreamConstraints {
  /// Audio constraints (true for default, false for none)
  final dynamic audio;

  /// Video constraints (true for default, false for none)
  final dynamic video;

  /// Peer identity (optional)
  final String? peerIdentity;

  /// Prefer current tab (optional)
  final bool? preferCurrentTab;

  const MediaStreamConstraints({
    this.audio,
    this.video,
    this.peerIdentity,
    this.preferCurrentTab,
  });

  /// Check if audio is requested
  bool get hasAudio => audio == true || audio is MediaTrackConstraints;

  /// Check if video is requested
  bool get hasVideo => video == true || video is MediaTrackConstraints;
}

/// Media track constraints
class MediaTrackConstraints {
  /// Device ID
  final String? deviceId;

  /// Facing mode (for camera)
  final String? facingMode;

  /// Width
  final int? width;

  /// Height
  final int? height;

  /// Frame rate
  final double? frameRate;

  /// Aspect ratio
  final double? aspectRatio;

  /// Sample rate (for audio)
  final int? sampleRate;

  /// Sample size (for audio)
  final int? sampleSize;

  /// Echo cancellation (for audio)
  final bool? echoCancellation;

  /// Auto gain control (for audio)
  final bool? autoGainControl;

  /// Noise suppression (for audio)
  final bool? noiseSuppression;

  /// Channel count (for audio)
  final int? channelCount;

  const MediaTrackConstraints({
    this.deviceId,
    this.facingMode,
    this.width,
    this.height,
    this.frameRate,
    this.aspectRatio,
    this.sampleRate,
    this.sampleSize,
    this.echoCancellation,
    this.autoGainControl,
    this.noiseSuppression,
    this.channelCount,
  });
}

/// Media devices API
class MediaDevices {
  /// Pre-configured video track (for testing/mocking)
  MediaStreamTrack? video;

  /// Pre-configured audio track (for testing/mocking)
  MediaStreamTrack? audio;

  MediaDevices({this.video, this.audio});

  /// Get user media (camera/microphone)
  ///
  /// In server-side Dart, this returns mock tracks that can receive
  /// RTP data via writeRtp(). Connect to actual media sources externally.
  Future<MediaStream> getUserMedia(MediaStreamConstraints constraints) async {
    final tracks = <MediaStreamTrack>[];

    if (constraints.hasVideo) {
      final videoTrack = MediaStreamTrack(kind: MediaKind.video);

      // If we have a pre-configured video source, forward its RTP
      if (video != null) {
        video!.onReceiveRtp.listen((event) {
          final (rtp, extensions) = event;
          final cloned = _clonePacket(rtp);
          videoTrack.writeRtp(cloned, extensions);
        });
      }

      tracks.add(videoTrack);
    }

    if (constraints.hasAudio) {
      final audioTrack = MediaStreamTrack(kind: MediaKind.audio);

      // If we have a pre-configured audio source, forward its RTP
      if (audio != null) {
        audio!.onReceiveRtp.listen((event) {
          final (rtp, extensions) = event;
          final cloned = _clonePacket(rtp);
          audioTrack.writeRtp(cloned, extensions);
        });
      }

      tracks.add(audioTrack);
    }

    if (tracks.isEmpty) {
      throw StateError('At least audio or video must be requested');
    }

    return MediaStream(tracks);
  }

  /// Get display media (screen sharing)
  ///
  /// Same as getUserMedia for server-side implementation.
  Future<MediaStream> getDisplayMedia(MediaStreamConstraints constraints) {
    return getUserMedia(constraints);
  }

  /// Get UDP media source
  ///
  /// Creates a track that receives RTP from a UDP port.
  /// Useful for receiving media from external sources like GStreamer.
  Future<UdpMediaSource> getUdpMedia({
    required int port,
    required RtpCodecParameters codec,
  }) async {
    final kind = codec.mimeType.toLowerCase().contains('video')
        ? MediaKind.video
        : MediaKind.audio;

    final track = MediaStreamTrack(kind: kind, codec: codec);

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          track.writeRtp(datagram.data);
        }
      }
    });

    return UdpMediaSource(
      track: track,
      dispose: () {
        socket.close();
        track.stop();
      },
    );
  }

  RtpPacket _clonePacket(RtpPacket rtp) {
    // Clone with new random SSRC
    final random = Random();
    final newSsrc = random.nextInt(0xFFFFFFFF);

    return RtpPacket(
      version: rtp.version,
      padding: rtp.padding,
      extension: rtp.extension,
      marker: rtp.marker,
      payloadType: rtp.payloadType,
      sequenceNumber: rtp.sequenceNumber,
      timestamp: rtp.timestamp,
      ssrc: newSsrc,
      csrcs: rtp.csrcs,
      extensionHeader: rtp.extensionHeader,
      payload: Uint8List.fromList(rtp.payload),
    );
  }
}

/// UDP media source result
class UdpMediaSource {
  /// The media track
  final MediaStreamTrack track;

  /// Dispose function to close the socket
  final void Function() dispose;

  UdpMediaSource({required this.track, required this.dispose});
}

/// Navigator API (W3C-style)
class Navigator {
  /// Media devices interface
  final MediaDevices mediaDevices;

  Navigator({MediaDevices? mediaDevices})
      : mediaDevices = mediaDevices ?? MediaDevices();
}

/// Default navigator instance
final navigator = Navigator();
