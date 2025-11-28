/// Provides protection against replay attacks by remembering received packets
/// in a sliding window bitmap
///
/// The window bitmap looks as follows:
/// ```
///  v- upper end (ceiling)         lower end --v
/// [111011...window_n]...[11111101...window_0]
/// ```
class AntiReplayWindow {
  static const int width = 64; // Window size in bits
  static const int intSize = 32; // Dart uses 32-bit integers for bitwise ops

  late List<int> _window;
  late int _ceiling; // Upper end of window / highest received seq_num

  AntiReplayWindow() {
    reset();
  }

  /// Initializes the anti-replay window to its default state
  void reset() {
    _window = List.filled(width ~/ intSize, 0);
    _ceiling = width - 1;
  }

  /// Checks if the packet with the given sequence number may be received
  /// or has to be discarded
  ///
  /// Returns true if the packet should be accepted, false otherwise
  bool mayReceive(int seqNum) {
    if (seqNum > _ceiling + width) {
      // Skipped too many packets - reject to prevent DoS
      return false;
    } else if (seqNum > _ceiling) {
      // Always accept new packets beyond the window
      return true;
    } else if (seqNum >= _ceiling - width + 1 && seqNum <= _ceiling) {
      // Packet falls within the window - check if already received
      return !hasReceived(seqNum);
    } else {
      // Too old - reject
      return false;
    }
  }

  /// Checks if the packet with the given sequence number is marked as received
  bool hasReceived(int seqNum) {
    final lowerBound = _ceiling - width + 1;

    // Check if sequence number is within window bounds
    if (seqNum < lowerBound || seqNum > _ceiling) {
      return false;
    }

    final bitIndex = seqNum - lowerBound;
    final windowIndex = bitIndex ~/ intSize;
    final windowBit = bitIndex % intSize;

    // Bounds check for window array
    if (windowIndex < 0 || windowIndex >= _window.length) {
      return false;
    }

    final flag = 1 << windowBit;

    return (_window[windowIndex] & flag) == flag;
  }

  /// Marks the packet with the given sequence number as received
  void markAsReceived(int seqNum) {
    if (seqNum > _ceiling) {
      // Shift the window to accommodate new ceiling
      var amount = seqNum - _ceiling;

      // First shift whole blocks (32-bit chunks)
      while (amount > intSize) {
        for (var i = 1; i < _window.length; i++) {
          _window[i - 1] = _window[i];
        }
        _window[_window.length - 1] = 0;
        amount -= intSize;
      }

      // Now shift bitwise (to the right)
      var overflow = 0;
      for (var i = 0; i < _window.length; i++) {
        // Calculate overflow from current block
        overflow = (_window[i] << (intSize - amount)) & 0xFFFFFFFF;

        // Shift current block right
        _window[i] = (_window[i] >>> amount) & 0xFFFFFFFF;

        // Add overflow from previous block
        if (i > 0) {
          _window[i - 1] = (_window[i - 1] | overflow) & 0xFFFFFFFF;
        }
      }

      // Update ceiling
      _ceiling = seqNum;
    }

    // Mark the bit as received
    final lowerBound = _ceiling - width + 1;
    final bitIndex = seqNum - lowerBound;
    final windowIndex = bitIndex ~/ intSize;
    final windowBit = bitIndex % intSize;
    final flag = 1 << windowBit;

    _window[windowIndex] = (_window[windowIndex] | flag) & 0xFFFFFFFF;
  }

  /// Get current ceiling (highest received sequence number)
  int get ceiling => _ceiling;

  /// Get window state for debugging
  List<int> get window => List.unmodifiable(_window);

  @override
  String toString() {
    return 'AntiReplayWindow(ceiling=$_ceiling, window=$_window)';
  }
}
