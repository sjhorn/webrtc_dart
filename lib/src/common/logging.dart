/// Logging configuration for webrtc_dart library
///
/// Uses Dart's standard `logging` package with hierarchical loggers
/// per component (ICE, DTLS, SCTP, etc.)
///
/// ## Quick Setup
/// ```dart
/// import 'package:webrtc_dart/webrtc_dart.dart';
///
/// void main() {
///   // Enable all debug logging with default handler
///   WebRtcLogging.enable();
///
///   // Your WebRTC code here
/// }
/// ```
///
/// ## Advanced Configuration
/// ```dart
/// import 'package:logging/logging.dart';
/// import 'package:webrtc_dart/webrtc_dart.dart';
///
/// void main() {
///   hierarchicalLoggingEnabled = true;
///
///   // Enable only ICE and DTLS logging
///   WebRtcLogging.ice.level = Level.FINE;
///   WebRtcLogging.dtls.level = Level.INFO;
///
///   // Add custom handler
///   Logger.root.onRecord.listen((record) {
///     print('${record.level.name}: ${record.loggerName}: ${record.message}');
///   });
/// }
/// ```
library;

import 'package:logging/logging.dart';

/// Centralized logging configuration for webrtc_dart
class WebRtcLogging {
  WebRtcLogging._();

  // ==================== Loggers ====================

  /// Root logger for all webrtc_dart logging
  static final Logger root = Logger('webrtc');

  /// ICE component logger
  static final Logger ice = Logger('webrtc.ice');

  /// DTLS component logger (parent for server/client)
  static final Logger dtls = Logger('webrtc.dtls');

  /// DTLS server handshake logger
  static final Logger dtlsServer = Logger('webrtc.dtls.server');

  /// DTLS client handshake logger
  static final Logger dtlsClient = Logger('webrtc.dtls.client');

  /// DTLS key derivation logger
  static final Logger dtlsKeys = Logger('webrtc.dtls.keys');

  /// DTLS ECDH logger
  static final Logger dtlsEcdh = Logger('webrtc.dtls.ecdh');

  /// DTLS cipher logger
  static final Logger dtlsCipher = Logger('webrtc.dtls.cipher');

  /// DTLS flight logger
  static final Logger dtlsFlight = Logger('webrtc.dtls.flight');

  /// DTLS record layer logger
  static final Logger dtlsRecord = Logger('webrtc.dtls.record');

  /// SCTP component logger
  static final Logger sctp = Logger('webrtc.sctp');

  /// RTP component logger
  static final Logger rtp = Logger('webrtc.rtp');

  /// SRTP component logger
  static final Logger srtp = Logger('webrtc.srtp');

  /// PeerConnection logger
  static final Logger pc = Logger('webrtc.pc');

  /// DataChannel logger
  static final Logger datachannel = Logger('webrtc.datachannel');

  /// Transport logger
  static final Logger transport = Logger('webrtc.transport');

  /// Media transport logger
  static final Logger transportMedia = Logger('webrtc.transport.media');

  /// Demux logger
  static final Logger transportDemux = Logger('webrtc.transport.demux');

  // ==================== Configuration ====================

  static bool _listenerAttached = false;

  /// Enable all debug logging with a simple print handler
  ///
  /// This is a convenience method for quick debugging. For production,
  /// configure logging handlers externally.
  ///
  /// [level] defaults to Level.FINE for verbose output.
  /// [printHandler] if true, adds a default print handler.
  static void enable({
    Level level = Level.FINE,
    bool printHandler = true,
  }) {
    hierarchicalLoggingEnabled = true;
    root.level = level;

    if (printHandler && !_listenerAttached) {
      _listenerAttached = true;
      Logger.root.onRecord.listen((record) {
        if (record.loggerName.startsWith('webrtc')) {
          print(
              '${record.level.name} [${record.loggerName}] ${record.message}');
        }
      });
    }
  }

  /// Disable all webrtc_dart logging
  static void disable() {
    root.level = Level.OFF;
  }
}
