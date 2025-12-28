import 'dart:async';

import 'package:webrtc_dart/src/media/rtp_transceiver.dart';

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

  /// Close the manager and release resources
  void close() {
    _trackController.close();
    for (final transceiver in _transceivers) {
      transceiver.stop();
    }
  }
}
