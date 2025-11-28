import 'package:webrtc_dart/src/srtp/const.dart';

/// Replay Protection using Sliding Window
/// RFC 3711 Section 3.3.2
///
/// Maintains a sliding window of received packet indices to detect replays.
/// The window slides forward as newer packets arrive.
class ReplayProtection {
  /// The highest sequence number received
  int _highestSequence = 0;

  /// Sliding window bitmap
  /// Bit i is set if packet (highestSequence - i) has been received
  int _window = 0;

  /// Window size (number of packets to track)
  final int windowSize;

  /// Whether replay protection is initialized
  bool _initialized = false;

  ReplayProtection({this.windowSize = 64}) {
    if (windowSize > 64) {
      throw ArgumentError('Window size cannot exceed 64 (using int bitmap)');
    }
  }

  /// Check if a sequence number should be accepted
  /// Returns true if the packet is valid and not a replay
  bool check(int sequence) {
    // Handle 16-bit wraparound
    sequence = sequence & 0xFFFF;

    if (!_initialized) {
      // First packet, accept and initialize
      _highestSequence = sequence;
      _window = 1; // Mark this sequence as received
      _initialized = true;
      return true;
    }

    // Calculate delta considering wraparound
    final delta = _sequenceDelta(sequence, _highestSequence);

    if (delta > 0) {
      // Packet is newer than anything we've seen
      // Shift window and accept
      if (delta < windowSize) {
        // Shift window by delta positions
        _window = (_window << delta) | 1;
      } else {
        // Delta is larger than window, reset window
        _window = 1;
      }
      _highestSequence = sequence;
      return true;
    } else if (delta == 0) {
      // Duplicate of highest sequence
      return false;
    } else {
      // Packet is older than highest
      final index = -delta;
      if (index >= windowSize) {
        // Too old, outside window
        return false;
      }

      // Check if this sequence was already received
      final mask = 1 << index;
      if ((_window & mask) != 0) {
        // Already received
        return false;
      }

      // Mark as received
      _window |= mask;
      return true;
    }
  }

  /// Update replay state after successful decryption
  /// This should be called only after authentication succeeds
  void update(int sequence) {
    // The check() method already updates the state,
    // but this provides explicit confirmation
  }

  /// Calculate signed delta between two 16-bit sequence numbers
  /// Handles wraparound correctly
  int _sequenceDelta(int s1, int s2) {
    // Convert to signed 16-bit difference
    var delta = (s1 - s2) & 0xFFFF;
    // If delta > 32768, it's actually a negative number due to wraparound
    if (delta > 0x7FFF) {
      delta -= 0x10000;
    }
    return delta;
  }

  /// Reset replay protection state
  void reset() {
    _highestSequence = 0;
    _window = 0;
    _initialized = false;
  }

  /// Get current highest sequence number
  int get highestSequence => _highestSequence;

  /// Check if replay protection is initialized
  bool get isInitialized => _initialized;

  @override
  String toString() {
    return 'ReplayProtection(highest=$_highestSequence, window=0x${_window.toRadixString(16)}, init=$_initialized)';
  }
}
