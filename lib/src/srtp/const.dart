/// SRTP Constants
/// RFC 3711 - The Secure Real-time Transport Protocol (SRTP)

/// SRTP authentication tag sizes
class SrtpAuthTagSize {
  /// 80-bit (10 bytes) authentication tag
  static const int tag80 = 10;

  /// 32-bit (4 bytes) authentication tag
  static const int tag32 = 4;

  /// 128-bit (16 bytes) authentication tag for AEAD
  static const int tag128 = 16;
}

/// SRTCP index length
const int srtcpIndexLength = 4;

/// SRTCP E-flag bit position
const int srtcpEFlagBit = 0x80000000;

/// Maximum SRTP sequence number (16-bit)
const int maxSequenceNumber = 0xFFFF;

/// Maximum SRTP SSRC (32-bit)
const int maxSsrc = 0xFFFFFFFF;

/// Replay protection window size (RFC 3711 recommends at least 64)
const int replayWindowSize = 128;
