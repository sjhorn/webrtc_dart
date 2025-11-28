import 'dart:async';
import '../srtp/rtp_packet.dart';
import '../rtcp/nack.dart';
import 'rtx.dart';

/// NACK Handler for receiver-side packet loss detection and NACK generation
///
/// Tracks received RTP packets and detects gaps in sequence numbers.
/// Automatically sends NACK requests for missing packets and manages retries.
class NackHandler {
  /// Expected next sequence number
  int _expectedSeqNum = 0;

  /// Map of lost sequence numbers to retry count
  final Map<int, int> _lostPackets = {};

  /// SSRC of media source being tracked
  int? mediaSourceSsrc;

  /// SSRC to use in NACK sender field
  final int senderSsrc;

  /// Maximum number of retries before giving up on a packet
  final int maxRetries;

  /// Interval between NACK retransmissions (milliseconds)
  final int nackIntervalMs;

  /// Maximum number of lost packets to track
  final int maxLostPackets;

  /// Timer for periodic NACK sending
  Timer? _nackTimer;

  /// Callback for sending NACK packets
  final Future<void> Function(GenericNack nack) onSendNack;

  /// Callback when packet is permanently lost (max retries exceeded)
  final void Function(int sequenceNumber)? onPacketLost;

  /// Whether handler is closed
  bool _closed = false;

  NackHandler({
    required this.senderSsrc,
    required this.onSendNack,
    this.onPacketLost,
    this.maxRetries = 10,
    this.nackIntervalMs = 5,
    this.maxLostPackets = 150,
  });

  /// Process received RTP packet
  /// Detects gaps in sequence numbers and marks missing packets as lost
  void addPacket(RtpPacket packet) {
    if (_closed) return;

    final seqNum = packet.sequenceNumber;
    mediaSourceSsrc ??= packet.ssrc;

    // Initialize expected sequence number on first packet
    if (_expectedSeqNum == 0) {
      _expectedSeqNum = seqNum;
      return;
    }

    // Check if this packet was previously marked as lost (recovery)
    if (_lostPackets.containsKey(seqNum)) {
      _lostPackets.remove(seqNum);

      // Stop timer if no more lost packets
      if (_lostPackets.isEmpty) {
        _stopNackTimer();
      }
      return;
    }

    // Calculate next expected sequence number
    final nextExpected = uint16Add(_expectedSeqNum, 1);

    // Normal sequential packet
    if (seqNum == nextExpected) {
      _expectedSeqNum = seqNum;
      return;
    }

    // Gap detected - mark missing packets as lost
    if (uint16Gt(seqNum, nextExpected)) {
      var missing = nextExpected;
      while (uint16Lt(missing, seqNum)) {
        _setLost(missing, 1);
        missing = uint16Add(missing, 1);
      }
      _expectedSeqNum = seqNum;
      _pruneLost();
    }
  }

  /// Mark a sequence number as lost
  void _setLost(int seqNum, int count) {
    _lostPackets[seqNum] = count;

    // Start NACK timer if not already running
    if (_nackTimer == null && !_closed) {
      _startNackTimer();
    }
  }

  /// Start periodic NACK sending
  void _startNackTimer() {
    _nackTimer = Timer.periodic(
      Duration(milliseconds: nackIntervalMs),
      (_) => _sendNack(),
    );
  }

  /// Stop NACK timer
  void _stopNackTimer() {
    _nackTimer?.cancel();
    _nackTimer = null;
  }

  /// Send NACK for all currently lost packets
  Future<void> _sendNack() async {
    if (_closed || mediaSourceSsrc == null) return;

    final lostSeqNums = _lostPackets.keys.toList();
    if (lostSeqNums.isEmpty) {
      _stopNackTimer();
      return;
    }

    final nack = GenericNack(
      senderSsrc: senderSsrc,
      mediaSourceSsrc: mediaSourceSsrc!,
      lostSeqNumbers: lostSeqNums,
    );

    try {
      await onSendNack(nack);
      _updateRetryCount();
    } catch (e) {
      // Ignore send errors, will retry on next interval
    }
  }

  /// Update retry counts and remove packets that exceeded max retries
  void _updateRetryCount() {
    final toRemove = <int>[];

    for (final entry in _lostPackets.entries) {
      final seqNum = entry.key;
      final count = entry.value;

      _lostPackets[seqNum] = count + 1;

      if (count + 1 > maxRetries) {
        toRemove.add(seqNum);
        onPacketLost?.call(seqNum);
      }
    }

    for (final seqNum in toRemove) {
      _lostPackets.remove(seqNum);
    }

    // Stop timer if no more lost packets
    if (_lostPackets.isEmpty) {
      _stopNackTimer();
    }
  }

  /// Prune lost packets list to prevent unbounded growth
  void _pruneLost() {
    if (_lostPackets.length <= maxLostPackets) return;

    // Keep only the newest maxLostPackets entries
    final sorted = _lostPackets.keys.toList()..sort(_compareSeqNum);
    final toRemove = sorted.take(_lostPackets.length - maxLostPackets);

    for (final seqNum in toRemove) {
      _lostPackets.remove(seqNum);
    }
  }

  /// Compare sequence numbers (handles wraparound)
  int _compareSeqNum(int a, int b) {
    final diff = _seqNumDiff(a, b);
    return diff.sign;
  }

  /// Calculate difference between sequence numbers (handles wraparound)
  int _seqNumDiff(int a, int b) {
    final diff = (b - a) & 0xFFFF;
    return diff < 0x8000 ? diff : diff - 0x10000;
  }

  /// Get list of currently lost sequence numbers
  List<int> get lostSeqNumbers => _lostPackets.keys.toList();

  /// Get number of currently lost packets
  int get lostPacketCount => _lostPackets.length;

  /// Close handler and stop timers
  void close() {
    _closed = true;
    _stopNackTimer();
    _lostPackets.clear();
  }
}
