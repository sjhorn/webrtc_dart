/// WebRTC implementation in pure Dart
///
/// A pure Dart implementation of WebRTC protocols including
/// ICE, DTLS, SRTP, SCTP, and the PeerConnection API.
library;

// Import for typedef declarations
import 'src/rtc_peer_connection.dart' show RTCPeerConnection;
import 'src/datachannel/rtc_data_channel.dart' show RTCDataChannel;
import 'src/media/rtc_rtp_transceiver.dart' show RTCRtpTransceiver;
import 'src/media/rtc_rtp_sender.dart' show RTCRtpSender;
import 'src/media/rtc_rtp_receiver.dart' show RTCRtpReceiver;
import 'src/ice/rtc_ice_candidate.dart' show RTCIceCandidate;
import 'src/sdp/sdp.dart' show RTCSessionDescription;

export 'src/webrtc_dart_base.dart';

// Logging
export 'src/common/logging.dart' show WebRtcLogging;

// Core API
export 'src/rtc_peer_connection.dart'
    show
        RTCPeerConnection,
        PeerConnectionState,
        SignalingState,
        IceConnectionState,
        IceGatheringState,
        RtcConfiguration,
        RtcCodecs,
        IceServer,
        IceTransportPolicy,
        BundlePolicy,
        RtcOfferOptions;
export 'src/sdp/sdp.dart';
export 'src/sdp/rtx_sdp.dart';

// ICE
export 'src/ice/ice_connection.dart';
export 'src/ice/rtc_ice_candidate.dart';
export 'src/ice/tcp_transport.dart';
export 'src/ice/mdns.dart';

// TURN
export 'src/turn/turn_client.dart';
export 'src/turn/channel_data.dart';

// Data Channels
export 'src/datachannel/rtc_data_channel.dart';
export 'src/datachannel/dcep.dart';

// Media Tracks
export 'src/media/media_stream_track.dart';
export 'src/media/media_stream.dart';
export 'src/media/rtc_rtp_transceiver.dart';
export 'src/media/rtc_dtmf_sender.dart';
export 'src/media/svc_manager.dart';
export 'src/media/parameters.dart';

// Codecs
export 'src/codec/codec_parameters.dart';
export 'src/codec/opus.dart';
export 'src/codec/vp8.dart';
export 'src/codec/vp9.dart';
export 'src/codec/h264.dart';
export 'src/codec/av1.dart';

// Audio Processing
export 'src/audio/dtx.dart';
export 'src/audio/lipsync.dart';

// Statistics
export 'src/stats/rtc_stats.dart';
export 'src/stats/rtp_stats.dart';

// RTCP Feedback
export 'src/rtcp/psfb/pli.dart';
export 'src/rtcp/psfb/fir.dart';
export 'src/rtcp/psfb/psfb.dart';
export 'src/rtcp/psfb/remb.dart';
export 'src/rtcp/rtpfb/twcc.dart';
export 'src/rtcp/nack.dart';

// RTCP Extended Reports (XR) - RFC 3611
export 'src/rtcp/xr/xr.dart';

// RTP Extensions
export 'src/rtp/rtx.dart';
export 'src/rtp/nack_handler.dart';
export 'src/rtp/header_extension.dart';

// RTP/SRTP
export 'src/srtp/rtp_packet.dart';
export 'src/srtp/rtcp_packet.dart';

// Transport Layer
export 'src/transport/transport.dart';
export 'src/dtls/dtls_transport.dart';
export 'src/sctp/association.dart';

// Certificate Generation
export 'src/dtls/certificate/certificate_generator.dart'
    show CertificateKeyPair, CertificateInfo, generateSelfSignedCertificate;

// STUN Protocol
export 'src/stun/message.dart';
export 'src/stun/attributes.dart';

// Utilities
export 'src/common/binary.dart'
    show random16, random32, bufferXor, bufferArrayXor;

// =============================================================================
// Backward Compatibility TypeDefs
// =============================================================================
// These provide backward compatibility for code using the old Dart-style names.
// New code should use the W3C standard names (RTCPeerConnection, etc.)

/// @deprecated Use RTCPeerConnection instead
@Deprecated('Use RTCPeerConnection instead')
typedef RtcPeerConnection = RTCPeerConnection;

/// @deprecated Use RTCDataChannel instead
@Deprecated('Use RTCDataChannel instead')
typedef DataChannel = RTCDataChannel;

/// @deprecated Use RTCRtpTransceiver instead
@Deprecated('Use RTCRtpTransceiver instead')
typedef RtpTransceiver = RTCRtpTransceiver;

/// @deprecated Use RTCRtpSender instead
@Deprecated('Use RTCRtpSender instead')
typedef RtpSender = RTCRtpSender;

/// @deprecated Use RTCRtpReceiver instead
@Deprecated('Use RTCRtpReceiver instead')
typedef RtpReceiver = RTCRtpReceiver;

/// @deprecated Use RTCIceCandidate instead
@Deprecated('Use RTCIceCandidate instead')
typedef Candidate = RTCIceCandidate;

/// @deprecated Use RTCSessionDescription instead
@Deprecated('Use RTCSessionDescription instead')
typedef SessionDescription = RTCSessionDescription;
