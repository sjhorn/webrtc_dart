/// Nonstandard WebRTC types for RTP forwarding
///
/// This library provides MediaStreamTrack and MediaStream implementations
/// that support direct RTP packet forwarding, matching TypeScript werift behavior.
///
/// Use these types when you need to forward pre-encoded RTP packets
/// (e.g., from Ring cameras, FFmpeg, or other sources).
///
/// Example usage:
/// ```dart
/// import 'package:webrtc_dart/nonstandard.dart' as nonstandard;
///
/// final track = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.audio);
/// sender.registerNonstandardTrack(track);
/// // Later: track.writeRtp(rtpPacket);
/// ```
library;

export 'src/nonstandard/media/track.dart';
