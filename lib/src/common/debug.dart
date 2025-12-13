/// Debug logging utilities for webrtc_dart
///
/// **DEPRECATED**: Use [WebRtcLogging] from `logging.dart` instead.
///
/// This file provides backward compatibility. Setting [webrtcDebug] to true
/// will enable all webrtc_dart logging via [WebRtcLogging.enable()].
///
/// New code should use:
/// ```dart
/// import 'package:webrtc_dart/webrtc_dart.dart';
///
/// void main() {
///   WebRtcLogging.enable();  // Enable all logging
///   // ... rest of code
/// }
/// ```
library;

import 'logging.dart';

bool _webrtcDebug = false;

/// Global debug flag for webrtc_dart library (DEPRECATED)
///
/// **Migration**: Use [WebRtcLogging.enable()] instead.
///
/// When true, enables verbose logging for ICE, DTLS, SRTP, etc.
/// Defaults to false for clean output.
@Deprecated('Use WebRtcLogging.enable() instead')
bool get webrtcDebug => _webrtcDebug;

@Deprecated('Use WebRtcLogging.enable() instead')
set webrtcDebug(bool value) {
  _webrtcDebug = value;
  if (value) {
    WebRtcLogging.enable();
  } else {
    WebRtcLogging.disable();
  }
}

/// Debug logging helper (DEPRECATED)
///
/// **Migration**: Use the appropriate component logger instead:
/// ```dart
/// WebRtcLogging.ice.fine('message');  // For ICE messages
/// WebRtcLogging.dtls.fine('message'); // For DTLS messages
/// ```
@Deprecated('Use WebRtcLogging component loggers instead')
void debugLog(String message) {
  if (_webrtcDebug) {
    print(message);
  }
}
