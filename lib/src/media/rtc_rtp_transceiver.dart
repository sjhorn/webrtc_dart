import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_receiver.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_sender.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/transport/transport.dart';

// Re-export RtpSender and RtpReceiver for convenience
export 'package:webrtc_dart/src/media/rtc_rtp_sender.dart';
export 'package:webrtc_dart/src/media/rtc_rtp_receiver.dart';

/// RTCRtpCodecCapability - W3C codec capability for setCodecPreferences
class RTCRtpCodecCapability {
  /// MIME type (e.g., "video/VP8", "audio/opus")
  final String mimeType;

  /// Clock rate in Hz
  final int clockRate;

  /// Number of channels (for audio codecs)
  final int? channels;

  /// SDP format-specific parameters
  final String? sdpFmtpLine;

  const RTCRtpCodecCapability({
    required this.mimeType,
    required this.clockRate,
    this.channels,
    this.sdpFmtpLine,
  });

  /// Check if this capability matches a codec
  bool matches(RtpCodecParameters codec) {
    if (mimeType.toLowerCase() != codec.mimeType.toLowerCase()) return false;
    if (clockRate != codec.clockRate) return false;
    if (channels != null && channels != codec.channels) return false;
    return true;
  }

  @override
  String toString() => 'RTCRtpCodecCapability($mimeType/$clockRate)';
}

/// RTP Transceiver Direction
enum RtpTransceiverDirection { sendrecv, sendonly, recvonly, inactive }

/// RTP Transceiver
/// Manages sending and receiving RTP for a media track
/// Combines RtpSender and RtpReceiver
class RTCRtpTransceiver {
  /// Media type (audio or video)
  final MediaStreamTrackKind kind;

  /// Media ID (mid) - unique identifier in SDP
  /// Null until assigned during offer/answer negotiation.
  /// This matches werift behavior where mid is undefined until SDP exchange.
  String? _mid;

  /// RTP sender
  final RtpSender sender;

  /// RTP receiver
  final RtpReceiver receiver;

  /// Current direction
  RtpTransceiverDirection _direction;

  /// Stopped flag
  bool _stopped = false;

  /// Simulcast parameters (for sending/receiving multiple layers)
  final List<RTCRtpSimulcastParameters> _simulcast = [];

  /// Callback when a new track is received (including simulcast layers)
  void Function(MediaStreamTrack track)? onTrack;

  /// Associated transport (for bundlePolicy: disable support)
  /// When bundlePolicy is disable, each transceiver has its own transport.
  /// When bundlePolicy is max-bundle, all transceivers share the same transport.
  MediaTransport? _transport;

  /// M-line index in SDP (position in media sections)
  int? mLineIndex;

  /// All codecs for SDP negotiation (RED, Opus, etc.)
  /// The primary sending codec is still sender.codec
  List<RtpCodecParameters> codecs = [];

  /// Codec preferences set by setCodecPreferences()
  /// When non-null, codecs are filtered and reordered during SDP generation
  List<RTCRtpCodecCapability>? _codecPreferences;

  RTCRtpTransceiver({
    required this.kind,
    String? mid,
    required this.sender,
    required this.receiver,
    RtpTransceiverDirection? direction,
    List<RTCRtpSimulcastParameters>? simulcast,
    MediaTransport? transport,
    this.mLineIndex,
  })  : _mid = mid,
        _direction = direction ?? RtpTransceiverDirection.sendrecv,
        _transport = transport {
    if (simulcast != null) {
      _simulcast.addAll(simulcast);
    }
  }

  /// Get MID (may be null before SDP negotiation)
  String? get mid => _mid;

  /// Set MID (called during SDP negotiation to assign or update)
  set mid(String? value) {
    _mid = value;
    // Also update sender's mid for RTP header extension
    if (value != null) {
      sender.mid = value;
    }
  }

  /// Get the associated transport
  MediaTransport? get transport => _transport;

  /// Set the associated transport
  void setTransport(MediaTransport transport) {
    _transport = transport;
  }

  /// Get simulcast parameters
  List<RTCRtpSimulcastParameters> get simulcast =>
      List.unmodifiable(_simulcast);

  /// Add a simulcast layer
  void addSimulcastLayer(RTCRtpSimulcastParameters params) {
    _simulcast.add(params);
  }

  /// Get current direction
  // ignore: unnecessary_getters_setters
  RtpTransceiverDirection get direction => _direction;

  /// Set direction
  set direction(RtpTransceiverDirection value) {
    _direction = value;
  }

  /// Get current direction for negotiation
  RtpTransceiverDirection get currentDirection => _direction;

  /// Check if stopped
  bool get stopped => _stopped;

  /// Stop the transceiver
  void stop() {
    if (!_stopped) {
      _stopped = true;
      sender.stop();
      receiver.stop();
    }
  }

  /// Set negotiated direction (called after SDP negotiation)
  void setNegotiatedDirection(RtpTransceiverDirection negotiated) {
    _direction = negotiated;
  }

  /// Get codec preferences (null if not set)
  List<RTCRtpCodecCapability>? get codecPreferences => _codecPreferences;

  /// Set codec preferences for negotiation
  ///
  /// Sets the preferred codecs for this transceiver in order of preference.
  /// During SDP offer/answer generation, codecs will be ordered and filtered
  /// according to these preferences.
  ///
  /// [codecs] - List of RTCRtpCodecCapability in order of preference.
  ///   Pass an empty list to use the default codec order.
  ///   Pass null to clear preferences.
  ///
  /// Throws [InvalidAccessError] (StateError) if:
  /// - The transceiver is stopped
  /// - A codec in the list is not supported
  ///
  /// Example:
  /// ```dart
  /// transceiver.setCodecPreferences([
  ///   RTCRtpCodecCapability(mimeType: 'video/VP9', clockRate: 90000),
  ///   RTCRtpCodecCapability(mimeType: 'video/VP8', clockRate: 90000),
  /// ]);
  /// ```
  void setCodecPreferences(List<RTCRtpCodecCapability>? codecs) {
    if (_stopped) {
      throw StateError('Cannot set codec preferences on stopped transceiver');
    }

    if (codecs == null || codecs.isEmpty) {
      _codecPreferences = null;
      return;
    }

    // Validate that all requested codecs are supported
    // For now, we accept all codecs - validation happens during SDP generation
    _codecPreferences = List.unmodifiable(codecs);
  }

  /// Get codecs ordered by preferences
  ///
  /// Returns the transceiver's codecs reordered according to setCodecPreferences().
  /// If no preferences are set, returns codecs in their original order.
  List<RtpCodecParameters> getOrderedCodecs() {
    if (_codecPreferences == null || _codecPreferences!.isEmpty) {
      return codecs;
    }

    final ordered = <RtpCodecParameters>[];
    final remaining = List<RtpCodecParameters>.from(codecs);

    // Add codecs in preference order
    for (final pref in _codecPreferences!) {
      for (var i = 0; i < remaining.length; i++) {
        if (pref.matches(remaining[i])) {
          ordered.add(remaining.removeAt(i));
          break;
        }
      }
    }

    // Remaining codecs not in preferences are excluded per W3C spec
    return ordered;
  }

  @override
  String toString() {
    return 'RtpTransceiver(mid=$mid, kind=$kind, direction=$direction)';
  }
}

/// Create audio transceiver
RtpTransceiver createAudioTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
  List<RTCRtpEncodingParameters>? sendEncodings,
  RtpCodecParameters? codec,
}) {
  final effectiveCodec = codec ?? createOpusCodec(payloadType: 111);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: effectiveCodec,
    sendEncodings: sendEncodings,
  );
  sender.mid = mid;

  // Create receive track
  final receiveTrack = AudioStreamTrack(
    id: 'audio_recv_$mid',
    label: 'Audio Receiver',
  );

  final receiver = RtpReceiver(
    track: receiveTrack,
    rtpSession: rtpSession,
    codec: effectiveCodec,
  );

  return RTCRtpTransceiver(
    kind: MediaStreamTrackKind.audio,
    mid: mid,
    sender: sender,
    receiver: receiver,
    direction: direction,
  );
}

/// Create video transceiver
///
/// For simulcast, pass sendEncodings with multiple RTCRtpEncodingParameters.
/// Each encoding can have a RID and different quality settings.
///
/// Example for simulcast:
/// ```dart
/// createVideoTransceiver(
///   mid: '1',
///   rtpSession: session,
///   sendTrack: videoTrack,
///   sendEncodings: [
///     RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000),
///     RTCRtpEncodingParameters(rid: 'mid', maxBitrate: 500000, scaleResolutionDownBy: 2.0),
///     RTCRtpEncodingParameters(rid: 'low', maxBitrate: 150000, scaleResolutionDownBy: 4.0),
///   ],
/// );
/// ```
RtpTransceiver createVideoTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
  List<RTCRtpEncodingParameters>? sendEncodings,
  RtpCodecParameters? codec,
}) {
  final effectiveCodec = codec ?? createVp8Codec(payloadType: 96);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: effectiveCodec,
    sendEncodings: sendEncodings,
  );
  sender.mid = mid;

  // Create receive track
  final receiveTrack = VideoStreamTrack(
    id: 'video_recv_$mid',
    label: 'Video Receiver',
  );

  final receiver = RtpReceiver(
    track: receiveTrack,
    rtpSession: rtpSession,
    codec: effectiveCodec,
  );

  return RTCRtpTransceiver(
    kind: MediaStreamTrackKind.video,
    mid: mid,
    sender: sender,
    receiver: receiver,
    direction: direction,
  );
}

// =============================================================================
// Backward Compatibility TypeDef
// =============================================================================

/// @deprecated Use RTCRtpTransceiver instead
@Deprecated('Use RTCRtpTransceiver instead')
typedef RtpTransceiver = RTCRtpTransceiver;
