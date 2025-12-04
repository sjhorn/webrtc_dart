/// RTP Statistics
/// Tracks statistics for an RTP stream
/// RFC 3550 Section 6.4 - Calculating RTCP fields
class RtpStatistics {
  /// SSRC identifier
  final int ssrc;

  /// Total packets received
  int packetsReceived = 0;

  /// Total bytes received (payload only)
  int bytesReceived = 0;

  /// Highest sequence number received
  int highestSequence = 0;

  /// Base sequence number (first packet)
  int? baseSequence;

  /// Cycles (number of sequence number wraps)
  int cycles = 0;

  /// Expected packets (calculated)
  int get expectedPackets {
    if (baseSequence == null) return 0;
    final extended = (cycles << 16) | highestSequence;
    final base = baseSequence!;
    return extended - base + 1;
  }

  /// Lost packets (calculated)
  int get lostPackets {
    final expected = expectedPackets;
    final lost = expected - packetsReceived;
    return lost > 0 ? lost : 0;
  }

  /// Packet loss fraction (0-255, where 255 = 100%)
  int get lossFraction {
    final expected = expectedPackets;
    if (expected == 0) return 0;
    final lost = lostPackets;
    return ((lost * 256) / expected).floor().clamp(0, 255);
  }

  /// Last SR timestamp received (for DLSR calculation)
  int? lastSrTimestamp;

  /// Last SR receive time (in NTP format)
  int? lastSrReceiveTime;

  /// Jitter calculation fields
  double jitter = 0.0;
  int? _lastTransitTime;

  RtpStatistics({required this.ssrc});

  /// Update statistics with a received packet
  void updateReceived({
    required int sequenceNumber,
    required int timestamp,
    required int payloadSize,
    required int arrivalTime, // In RTP timestamp units
  }) {
    packetsReceived++;
    bytesReceived += payloadSize;

    // Initialize base sequence on first packet
    if (baseSequence == null) {
      baseSequence = sequenceNumber;
      highestSequence = sequenceNumber;
    } else {
      // Handle sequence number updates
      _updateSequence(sequenceNumber);
    }

    // Calculate jitter
    _updateJitter(timestamp, arrivalTime);
  }

  /// Update sequence number tracking
  void _updateSequence(int sequenceNumber) {
    // Calculate delta
    final delta = sequenceNumber - highestSequence;

    if (delta > 0) {
      // In-order packet
      if (delta < 0x8000) {
        // Normal advance
        highestSequence = sequenceNumber;
      } else {
        // Reordered old packet, ignore
      }
    } else if (delta < -0x8000) {
      // Sequence number wrapped around
      cycles++;
      highestSequence = sequenceNumber;
    }
    // else: duplicate or reordered packet
  }

  /// Update jitter calculation
  /// RFC 3550 Section 6.4.1
  void _updateJitter(int timestamp, int arrivalTime) {
    if (_lastTransitTime == null) {
      _lastTransitTime = arrivalTime - timestamp;
      return;
    }

    final transit = arrivalTime - timestamp;
    final d = (transit - _lastTransitTime!).abs();

    // J(i) = J(i-1) + (|D(i-1,i)| - J(i-1))/16
    jitter += (d - jitter) / 16.0;

    _lastTransitTime = transit;
  }

  /// Update with received Sender Report
  void updateWithSenderReport({
    required int ntpTimestamp,
    required int rtpTimestamp,
    required int packetCount,
    required int octetCount,
    required int receiveTime,
  }) {
    lastSrTimestamp = ntpTimestamp;
    lastSrReceiveTime = receiveTime;
  }

  /// Calculate delay since last SR (DLSR)
  /// Returns value in units of 1/65536 seconds
  int calculateDlsr(int currentTime) {
    if (lastSrReceiveTime == null) return 0;

    final delay = currentTime - lastSrReceiveTime!;
    // Convert to 1/65536 second units
    return (delay * 65536 / 1000).floor();
  }

  /// Reset statistics
  void reset() {
    packetsReceived = 0;
    bytesReceived = 0;
    highestSequence = 0;
    baseSequence = null;
    cycles = 0;
    jitter = 0.0;
    _lastTransitTime = null;
    lastSrTimestamp = null;
    lastSrReceiveTime = null;
  }

  @override
  String toString() {
    return 'RtpStatistics(ssrc=0x${ssrc.toRadixString(16)}, packets=$packetsReceived, bytes=$bytesReceived, lost=$lostPackets, jitter=${jitter.toStringAsFixed(2)})';
  }
}

/// RTP Sender Statistics
/// Tracks statistics for sending RTP packets
class RtpSenderStatistics {
  /// SSRC identifier
  final int ssrc;

  /// Total packets sent
  int packetsSent = 0;

  /// Total bytes sent (payload only)
  int bytesSent = 0;

  /// Sequence number for next packet
  int sequenceNumber = 0;

  /// Timestamp for next packet
  int timestamp = 0;

  /// Last SR send time (NTP format)
  int? lastSrSendTime;

  RtpSenderStatistics({required this.ssrc, int? initialSequence, int? initialTimestamp}) {
    sequenceNumber = initialSequence ?? _generateRandomSequence();
    timestamp = initialTimestamp ?? _generateRandomTimestamp();
  }

  /// Get next sequence number
  int getNextSequence() {
    final current = sequenceNumber;
    sequenceNumber = (sequenceNumber + 1) & 0xFFFF;
    return current;
  }

  /// Get current timestamp and advance
  int getNextTimestamp(int increment) {
    final current = timestamp;
    timestamp = (timestamp + increment) & 0xFFFFFFFF;
    return current;
  }

  /// Update with sent packet
  void updateSent({required int payloadSize}) {
    packetsSent++;
    bytesSent += payloadSize;
  }

  /// Update with sent SR
  void updateWithSentSr({required int ntpTimestamp}) {
    lastSrSendTime = ntpTimestamp;
  }

  /// Generate random initial sequence number
  int _generateRandomSequence() {
    // In production, use cryptographically secure random
    return DateTime.now().microsecondsSinceEpoch & 0xFFFF;
  }

  /// Generate random initial timestamp
  int _generateRandomTimestamp() {
    // In production, use cryptographically secure random
    return DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
  }

  /// Reset statistics
  void reset() {
    packetsSent = 0;
    bytesSent = 0;
    lastSrSendTime = null;
  }

  @override
  String toString() {
    return 'RtpSenderStatistics(ssrc=0x${ssrc.toRadixString(16)}, packets=$packetsSent, bytes=$bytesSent)';
  }
}
