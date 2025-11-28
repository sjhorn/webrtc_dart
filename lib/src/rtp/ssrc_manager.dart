import 'dart:math';

/// SSRC Manager
/// Handles SSRC allocation and collision detection
/// RFC 3550 Section 8.2
class SsrcManager {
  /// Local SSRC
  int _localSsrc;

  /// Known remote SSRCs
  final Set<int> _remoteSSRCs = {};

  /// SSRC collision count
  int _collisionCount = 0;

  /// Last collision time
  DateTime? _lastCollisionTime;

  /// Random number generator
  final Random _random;

  SsrcManager({int? initialSsrc, Random? random})
      : _localSsrc = initialSsrc ?? _generateRandomSsrc(random),
        _random = random ?? Random.secure();

  /// Get current local SSRC
  int get localSsrc => _localSsrc;

  /// Get collision count
  int get collisionCount => _collisionCount;

  /// Add a remote SSRC
  void addRemoteSsrc(int ssrc) {
    _remoteSSRCs.add(ssrc);
  }

  /// Remove a remote SSRC
  void removeRemoteSsrc(int ssrc) {
    _remoteSSRCs.remove(ssrc);
  }

  /// Check if SSRC is in use by a remote source
  bool isRemoteSsrc(int ssrc) {
    return _remoteSSRCs.contains(ssrc);
  }

  /// Check for SSRC collision
  /// Returns true if a collision is detected
  bool checkCollision({
    required int receivedSsrc,
    required String sourceAddress,
    required int sourcePort,
  }) {
    // Check if received SSRC matches our local SSRC
    if (receivedSsrc != _localSsrc) {
      return false;
    }

    // Collision detected!
    // RFC 3550 Section 8.2: If we receive a packet with our SSRC
    // but from a different source address, it's a collision
    _handleCollision();
    return true;
  }

  /// Handle SSRC collision
  /// Generate a new SSRC and update collision statistics
  void _handleCollision() {
    _collisionCount++;
    _lastCollisionTime = DateTime.now();

    // Generate new SSRC that doesn't conflict
    int newSsrc;
    int attempts = 0;
    const maxAttempts = 100;

    do {
      newSsrc = _generateRandomSsrc(_random);
      attempts++;

      if (attempts >= maxAttempts) {
        // Fallback: use sequential search
        newSsrc = _findUnusedSsrc();
        break;
      }
    } while (_remoteSSRCs.contains(newSsrc));

    _localSsrc = newSsrc;
  }

  /// Find an unused SSRC by sequential search
  int _findUnusedSsrc() {
    // Start from a random point and search sequentially
    var ssrc = _random.nextInt(0xFFFFFFFF);

    for (var i = 0; i < 0xFFFFFFFF; i++) {
      if (!_remoteSSRCs.contains(ssrc)) {
        return ssrc;
      }
      ssrc = (ssrc + 1) & 0xFFFFFFFF;
    }

    // Should never happen unless all 4 billion SSRCs are in use
    throw StateError('No available SSRC found');
  }

  /// Generate a random SSRC
  static int _generateRandomSsrc(Random? random) {
    final rng = random ?? Random.secure();

    // Generate 32-bit random number
    // Avoid zero as SSRC
    int ssrc;
    do {
      ssrc = rng.nextInt(0xFFFFFFFF);
    } while (ssrc == 0);

    return ssrc;
  }

  /// Check if SSRC loop is detected
  /// RFC 3550 Section 8.2: Detect if we're receiving our own packets
  bool checkLoop({
    required int receivedSsrc,
    required String localAddress,
    required int localPort,
    required String sourceAddress,
    required int sourcePort,
  }) {
    // If SSRC matches and source address matches local address,
    // we're receiving our own packets (loop)
    if (receivedSsrc == _localSsrc &&
        sourceAddress == localAddress &&
        sourcePort == localPort) {
      return true;
    }
    return false;
  }

  /// Reset collision statistics
  void resetCollisionStats() {
    _collisionCount = 0;
    _lastCollisionTime = null;
  }

  /// Get time since last collision
  Duration? timeSinceLastCollision() {
    if (_lastCollisionTime == null) return null;
    return DateTime.now().difference(_lastCollisionTime!);
  }

  /// Clear all remote SSRCs
  void clearRemoteSSRCs() {
    _remoteSSRCs.clear();
  }

  /// Get count of known remote SSRCs
  int get remoteSSRCCount => _remoteSSRCs.length;

  /// Get all remote SSRCs
  Set<int> get remoteSSRCs => Set.unmodifiable(_remoteSSRCs);

  @override
  String toString() {
    return 'SsrcManager(local=0x${_localSsrc.toRadixString(16)}, remote=${_remoteSSRCs.length}, collisions=$_collisionCount)';
  }
}
