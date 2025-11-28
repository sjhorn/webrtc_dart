import '../srtp/rtp_packet.dart';

/// Retransmission Buffer
/// Circular buffer for storing sent RTP packets to enable retransmission
/// upon receiving NACK feedback.
///
/// Uses a circular buffer indexed by sequence number modulo buffer size.
/// When buffer wraps around, oldest packets are automatically overwritten.
class RetransmissionBuffer {
  /// Buffer size (number of packets to keep)
  /// 128 packets provides good coverage for typical network conditions
  static const int defaultBufferSize = 128;

  final int bufferSize;
  final List<RtpPacket?> _buffer;

  RetransmissionBuffer({this.bufferSize = defaultBufferSize})
      : _buffer = List.filled(bufferSize, null);

  /// Store an RTP packet in the buffer
  /// Packet is indexed by sequence number modulo buffer size
  void store(RtpPacket packet) {
    final index = packet.sequenceNumber % bufferSize;
    _buffer[index] = packet;
  }

  /// Retrieve an RTP packet by sequence number
  /// Returns null if packet not found or has been overwritten
  RtpPacket? retrieve(int sequenceNumber) {
    final index = sequenceNumber % bufferSize;
    final packet = _buffer[index];

    // Verify sequence number matches (detect overwrites)
    if (packet != null && packet.sequenceNumber == sequenceNumber) {
      return packet;
    }

    return null;
  }

  /// Clear all packets from buffer
  void clear() {
    for (var i = 0; i < _buffer.length; i++) {
      _buffer[i] = null;
    }
  }

  /// Get number of packets currently stored
  int get packetCount {
    return _buffer.where((p) => p != null).length;
  }
}
