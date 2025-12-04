/// MediaStreamTrack - WebRTC media track abstraction
///
/// Provides MediaStreamTrack and MediaStream classes matching
/// the W3C WebRTC API for media handling.
///
/// Ported from werift-webrtc track.ts
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../srtp/rtp_packet.dart';
import '../../srtp/rtcp_packet.dart';

/// Generate a UUID v4 string
String _generateUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // Version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // Variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Media track kind
enum MediaKind {
  audio,
  video,
}

/// RTP codec parameters for track configuration
class RtpCodecParameters {
  /// MIME type (e.g., 'video/VP8', 'audio/opus')
  final String mimeType;

  /// Payload type
  final int payloadType;

  /// Clock rate
  final int clockRate;

  /// Number of channels (for audio)
  final int? channels;

  /// SDP fmtp parameters
  final Map<String, String> parameters;

  RtpCodecParameters({
    required this.mimeType,
    required this.payloadType,
    required this.clockRate,
    this.channels,
    this.parameters = const {},
  });
}

/// RTP header extensions info
typedef RtpExtensions = Map<int, Uint8List>;

/// RTP header info (subset of RtpPacket for tracking)
class RtpHeaderInfo {
  final int sequenceNumber;
  final int timestamp;
  final int ssrc;
  final int payloadType;
  final bool marker;

  RtpHeaderInfo({
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
    required this.payloadType,
    required this.marker,
  });

  factory RtpHeaderInfo.fromPacket(RtpPacket rtp) => RtpHeaderInfo(
        sequenceNumber: rtp.sequenceNumber,
        timestamp: rtp.timestamp,
        ssrc: rtp.ssrc,
        payloadType: rtp.payloadType,
        marker: rtp.marker,
      );
}

/// Media stream track
///
/// Represents a single media track (audio or video) that can be
/// added to an RTCPeerConnection.
class MediaStreamTrack {
  /// Unique track ID
  final String uuid = _generateUuid();

  /// Stream ID this track belongs to
  String? streamId;

  /// Whether this is a remote track
  final bool remote;

  /// Track label
  late String label;

  /// Track kind (audio/video)
  final MediaKind kind;

  /// Track ID (for SDP)
  String? id;

  /// Media SSRC
  int? ssrc;

  /// RID for simulcast
  String? rid;

  /// Last received RTP header info
  RtpHeaderInfo? headerInfo;

  /// Codec parameters
  RtpCodecParameters? codec;

  /// Whether track is enabled
  bool enabled = true;

  /// Whether track is stopped
  bool stopped = false;

  /// Whether track is muted (no data received yet)
  bool muted = true;

  /// RTP receive stream controller
  final StreamController<(RtpPacket, RtpExtensions?)> _rtpController =
      StreamController.broadcast();

  /// RTCP receive stream controller
  final StreamController<RtcpPacket> _rtcpController =
      StreamController.broadcast();

  /// Source changed stream controller
  final StreamController<RtpHeaderInfo> _sourceChangedController =
      StreamController.broadcast();

  /// Track ended stream controller
  final StreamController<void> _endedController = StreamController.broadcast();

  /// Stream of received RTP packets
  Stream<(RtpPacket, RtpExtensions?)> get onReceiveRtp => _rtpController.stream;

  /// Stream of received RTCP packets
  Stream<RtcpPacket> get onReceiveRtcp => _rtcpController.stream;

  /// Stream for source change notifications
  Stream<RtpHeaderInfo> get onSourceChanged => _sourceChangedController.stream;

  /// Stream for track ended notifications
  Stream<void> get onEnded => _endedController.stream;

  MediaStreamTrack({
    required this.kind,
    this.remote = false,
    this.streamId,
    this.id,
    this.ssrc,
    this.rid,
    this.codec,
  }) {
    label = '${remote ? "remote" : "local"} ${kind.name}';

    // Update muted state on first RTP
    onReceiveRtp.listen((event) {
      final (rtp, _) = event;
      muted = false;
      headerInfo = RtpHeaderInfo.fromPacket(rtp);
    });
  }

  /// Stop the track
  void stop() {
    stopped = true;
    muted = true;
    _endedController.add(null);
    _rtpController.close();
    _rtcpController.close();
    _sourceChangedController.close();
    _endedController.close();
  }

  /// Write RTP data to the track (for local tracks)
  ///
  /// Can accept either raw bytes or an [RtpPacket].
  void writeRtp(dynamic rtp, [RtpExtensions? extensions]) {
    if (remote) {
      throw StateError('Cannot write to remote track');
    }
    if (stopped) {
      return;
    }

    final RtpPacket packet;
    if (rtp is Uint8List) {
      packet = RtpPacket.parse(rtp);
    } else if (rtp is RtpPacket) {
      packet = rtp;
    } else {
      throw ArgumentError('Expected Uint8List or RtpPacket');
    }

    // Create new packet with overridden payload type if codec is set
    final outputPacket = codec != null
        ? RtpPacket(
            version: packet.version,
            padding: packet.padding,
            extension: packet.extension,
            marker: packet.marker,
            payloadType: codec!.payloadType,
            sequenceNumber: packet.sequenceNumber,
            timestamp: packet.timestamp,
            ssrc: packet.ssrc,
            csrcs: packet.csrcs,
            extensionHeader: packet.extensionHeader,
            payload: packet.payload,
          )
        : packet;

    _rtpController.add((outputPacket, extensions));
  }

  /// Called internally when RTP is received (for remote tracks)
  void receiveRtp(RtpPacket rtp, [RtpExtensions? extensions]) {
    if (stopped) return;
    _rtpController.add((rtp, extensions));
  }

  /// Called internally when RTCP is received
  void receiveRtcp(RtcpPacket rtcp) {
    if (stopped) return;
    _rtcpController.add(rtcp);
  }

  /// Notify that the source has changed (e.g., SSRC change)
  void notifySourceChanged(RtpHeaderInfo header) {
    _sourceChangedController.add(header);
  }

  /// Clone this track
  MediaStreamTrack clone() {
    return MediaStreamTrack(
      kind: kind,
      remote: remote,
      streamId: streamId,
      id: _generateUuid(),
      ssrc: null, // New SSRC will be assigned
      rid: rid,
      codec: codec,
    );
  }

  @override
  String toString() => 'MediaStreamTrack($label, id: $id, ssrc: $ssrc)';
}

/// Media stream containing multiple tracks
class MediaStream {
  /// Stream ID
  late String id;

  /// Tracks in this stream
  final List<MediaStreamTrack> _tracks = [];

  /// Create a new media stream
  MediaStream([List<MediaStreamTrack>? tracks]) {
    id = _generateUuid();
    if (tracks != null) {
      for (final track in tracks) {
        addTrack(track);
      }
    }
  }

  /// Create from existing stream with ID
  MediaStream.withId(this.id, [List<MediaStreamTrack>? tracks]) {
    if (tracks != null) {
      for (final track in tracks) {
        addTrack(track);
      }
    }
  }

  /// Add a track to the stream
  void addTrack(MediaStreamTrack track) {
    track.streamId = id;
    _tracks.add(track);
  }

  /// Remove a track from the stream
  bool removeTrack(MediaStreamTrack track) {
    return _tracks.remove(track);
  }

  /// Get all tracks
  List<MediaStreamTrack> getTracks() => List.unmodifiable(_tracks);

  /// Get audio tracks only
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((t) => t.kind == MediaKind.audio).toList();

  /// Get video tracks only
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((t) => t.kind == MediaKind.video).toList();

  /// Get track by ID
  MediaStreamTrack? getTrackById(String id) {
    try {
      return _tracks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Clone this stream
  MediaStream clone() {
    final cloned = MediaStream();
    for (final track in _tracks) {
      cloned.addTrack(track.clone());
    }
    return cloned;
  }

  /// Whether this stream is active (has at least one non-stopped track)
  bool get active => _tracks.any((t) => !t.stopped);

  @override
  String toString() => 'MediaStream(id: $id, tracks: ${_tracks.length})';
}
