import 'dart:async';

import 'package:webrtc_dart/src/codec/codec_parameters.dart'
    show RtpCodecParameters;
import 'package:webrtc_dart/src/media/rtp_router.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_transceiver.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart' show SdpMedia;
import 'package:webrtc_dart/src/media/parameters.dart' show SimulcastDirection;

/// TransceiverManager handles RTP transceiver lifecycle management.
///
/// This class matches the architecture of werift-webrtc's TransceiverManager,
/// providing separation of concerns from the main PeerConnection class.
///
/// Responsibilities:
/// - Managing the list of transceivers
/// - Providing accessors for transceivers, senders, receivers
/// - Transceiver lookup by MID or index
/// - Firing onTrack events
///
/// Reference: werift-webrtc/packages/webrtc/src/transceiverManager.ts
class TransceiverManager {
  /// List of all transceivers
  final List<RtpTransceiver> _transceivers = [];

  /// Stream controller for track events
  final StreamController<RtpTransceiver> _trackController =
      StreamController<RtpTransceiver>.broadcast();

  /// Stream of track events (when remote track is received)
  Stream<RtpTransceiver> get onTrack => _trackController.stream;

  /// Get all transceivers (unmodifiable list)
  List<RtpTransceiver> getTransceivers() {
    return List.unmodifiable(_transceivers);
  }

  /// Get all transceivers as property
  List<RtpTransceiver> get transceivers => List.unmodifiable(_transceivers);

  /// Get all senders
  List<RtpSender> getSenders() {
    return _transceivers.map((t) => t.sender).toList();
  }

  /// Get all receivers
  List<RtpReceiver> getReceivers() {
    return _transceivers.map((t) => t.receiver).toList();
  }

  /// Get transceiver by MID
  RtpTransceiver? getTransceiverByMid(String mid) {
    return _transceivers.where((t) => t.mid == mid).firstOrNull;
  }

  /// Get transceiver by m-line index
  RtpTransceiver? getTransceiverByMLineIndex(int index) {
    if (index < 0 || index >= _transceivers.length) return null;
    return _transceivers[index];
  }

  /// Add a transceiver to the list
  void addTransceiver(RtpTransceiver transceiver) {
    _transceivers.add(transceiver);
  }

  /// Fire onTrack event for a transceiver
  void fireOnTrack(RtpTransceiver transceiver) {
    _trackController.add(transceiver);
  }

  /// Find transceiver matching criteria
  RtpTransceiver? findTransceiver(bool Function(RtpTransceiver) predicate) {
    return _transceivers.where(predicate).firstOrNull;
  }

  /// Find all transceivers matching criteria
  Iterable<RtpTransceiver> findAllTransceivers(
      bool Function(RtpTransceiver) predicate) {
    return _transceivers.where(predicate);
  }

  /// Remove track from sender
  /// Note: Transceiver is not removed, just marked inactive
  void removeTrack(RtpSender sender) {
    final transceiver = _transceivers.firstWhere(
      (t) => t.sender == sender,
      orElse: () => throw ArgumentError('Sender not found'),
    );

    transceiver.stop();
    transceiver.direction = RtpTransceiverDirection.inactive;
  }

  /// Get number of transceivers
  int get length => _transceivers.length;

  /// Check if there are any transceivers
  bool get isEmpty => _transceivers.isEmpty;

  /// Check if there are transceivers
  bool get isNotEmpty => _transceivers.isNotEmpty;

  /// Configure transceiver from remote SDP media description.
  /// Matches werift's TransceiverManager.setRemoteRTP()
  ///
  /// [transceiver] - The transceiver to configure
  /// [media] - Remote SDP media description
  /// [router] - RTP router for header extension and simulcast registration
  void setRemoteRTP(
    RtpTransceiver transceiver,
    SdpMedia media,
    RtpRouter router,
  ) {
    // Extract header extension IDs from remote SDP and set on sender
    final headerExtensions = media.getHeaderExtensions();
    for (final ext in headerExtensions) {
      if (ext.uri == 'urn:ietf:params:rtp-hdrext:sdes:mid') {
        transceiver.sender.midExtensionId = ext.id;
      } else if (ext.uri ==
          'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time') {
        transceiver.sender.absSendTimeExtensionId = ext.id;
      } else if (ext.uri ==
          'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01') {
        transceiver.sender.transportWideCCExtensionId = ext.id;
      }
    }

    // Extract codec from remote SDP and update sender's codec
    // This is critical for return audio to use the correct payload type
    final rtpmap = media.getAttributeValue('rtpmap');
    if (rtpmap != null) {
      // Format: <pt> <codec>/<clock-rate>[/<channels>]
      final parts = rtpmap.split(' ');
      if (parts.length >= 2) {
        final payloadType = int.tryParse(parts[0]);
        if (payloadType != null) {
          final codecInfo = parts[1].split('/');
          final codecName = codecInfo.isNotEmpty ? codecInfo[0] : '';
          final clockRate =
              codecInfo.length > 1 ? int.tryParse(codecInfo[1]) : null;
          final channels =
              codecInfo.length > 2 ? int.tryParse(codecInfo[2]) : null;

          // Update sender's codec with negotiated payload type
          final mediaType = media.type == 'audio' ? 'audio' : 'video';
          transceiver.sender.codec = RtpCodecParameters(
            mimeType: '$mediaType/$codecName',
            clockRate: clockRate ?? (mediaType == 'audio' ? 48000 : 90000),
            payloadType: payloadType,
            channels: channels,
          );
        }
      }
    }

    // Register header extensions with RTP router for RID parsing
    router.registerHeaderExtensions(headerExtensions);

    // Register simulcast RID handlers if present
    final simulcastParams = media.getSimulcastParameters();
    final receiverForClosure = transceiver.receiver;
    for (final param in simulcastParams) {
      if (param.direction == SimulcastDirection.send) {
        // Remote is sending - we need to receive these RIDs
        router.registerByRid(param.rid, (packet, rid, extensions) {
          if (rid != null) {
            receiverForClosure.handleRtpByRid(packet, rid, extensions);
          } else {
            // Fallback: RID negotiated but not in packet, use SSRC routing
            receiverForClosure.handleRtpBySsrc(packet, extensions);
          }
        });
      }
    }
  }

  /// Close the manager and release resources
  void close() {
    _trackController.close();
    for (final transceiver in _transceivers) {
      transceiver.stop();
    }
  }
}
