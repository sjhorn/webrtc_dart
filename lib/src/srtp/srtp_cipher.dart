import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:webrtc_dart/src/srtp/const.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/replay_protection.dart';

/// SRTP Cipher for AES-GCM encryption/decryption
/// RFC 7714 - AES-GCM Authenticated Encryption in SRTP
///
/// Optimized implementation using package:cryptography for native AES-GCM.
/// Key derivation should be done by SrtpSession before passing to this cipher.
class SrtpCipher {
  /// Session encryption key (derived from master key)
  final Uint8List masterKey;

  /// Session salt (derived from master salt, 14 bytes truncated to 12 for GCM)
  final Uint8List masterSalt;

  /// Replay protection
  final ReplayProtection replayProtection;

  /// ROC (Rollover Counter) for each SSRC
  /// Tracks how many times the 16-bit sequence number has wrapped around
  final Map<int, int> _rocMap = {};

  /// Cached AES-GCM cipher instance (reused across packets)
  late final AesGcm _cipher;

  /// Cached secret key (reused across packets)
  SecretKey? _cachedSecretKey;

  /// Pre-allocated nonce buffer (reused across packets)
  final Uint8List _nonceBuffer = Uint8List(12);

  SrtpCipher({
    required this.masterKey,
    required this.masterSalt,
    ReplayProtection? replayProtection,
  }) : replayProtection = replayProtection ?? ReplayProtection() {
    // Initialize cipher once - will be reused for all packets
    _cipher = AesGcm.with128bits();
  }

  /// Get or create cached secret key
  Future<SecretKey> _getSecretKey() async {
    _cachedSecretKey ??= SecretKey(masterKey);
    return _cachedSecretKey!;
  }

  /// Encrypt RTP packet
  /// Returns encrypted packet bytes
  Future<Uint8List> encrypt(RtpPacket packet) async {
    // Get ROC for this SSRC
    final roc = _getROC(packet.ssrc, packet.sequenceNumber);

    // Build nonce (IV) - create copy to avoid race conditions in async
    final nonce = _buildNonce(packet.ssrc, packet.sequenceNumber, roc);

    // Serialize RTP header (authenticated data)
    final header = _serializeHeader(packet);

    // Get cached secret key
    final secretKey = await _getSecretKey();

    // Encrypt payload using AES-GCM
    final secretBox = await _cipher.encrypt(
      packet.payload,
      secretKey: secretKey,
      nonce: nonce,
      aad: header,
    );

    // Build final SRTP packet: header + encrypted_payload + auth_tag
    final cipherText = secretBox.cipherText;
    final mac = secretBox.mac.bytes;
    final result = Uint8List(header.length + cipherText.length + mac.length);
    result.setRange(0, header.length, header);
    result.setRange(header.length, header.length + cipherText.length, cipherText);
    result.setRange(header.length + cipherText.length, result.length, mac);

    return result;
  }

  /// Decrypt SRTP packet
  /// Returns decrypted RTP packet
  Future<RtpPacket> decrypt(Uint8List srtpPacket) async {
    if (srtpPacket.length <
        RtpPacket.fixedHeaderSize + SrtpAuthTagSize.tag128) {
      throw FormatException(
          'SRTP packet too short: ${srtpPacket.length} bytes');
    }

    // Parse RTP header (not encrypted)
    final headerEnd = _findHeaderEnd(srtpPacket);
    final header = Uint8List.sublistView(srtpPacket, 0, headerEnd);

    // Parse header fields we need
    final buffer = ByteData.sublistView(srtpPacket);
    final ssrc = buffer.getUint32(8);
    final sequenceNumber = buffer.getUint16(2);

    // Check replay protection
    if (!replayProtection.check(sequenceNumber)) {
      throw StateError('Replay detected for sequence $sequenceNumber');
    }

    // Get ROC for this SSRC
    final roc = _getROC(ssrc, sequenceNumber);

    // Build nonce (IV) - reuses pre-allocated buffer
    _buildNonceInPlace(ssrc, sequenceNumber, roc);

    // Extract encrypted payload and MAC
    final macStart = srtpPacket.length - SrtpAuthTagSize.tag128;
    final cipherText = Uint8List.sublistView(srtpPacket, headerEnd, macStart);
    final mac = Mac(Uint8List.sublistView(srtpPacket, macStart));

    // Get cached secret key
    final secretKey = await _getSecretKey();

    // Decrypt payload using AES-GCM
    try {
      final secretBox = SecretBox(
        cipherText,
        nonce: _nonceBuffer,
        mac: mac,
      );

      final decrypted = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: header,
      );

      // Reconstruct full RTP packet with decrypted payload
      final fullPacket = Uint8List(header.length + decrypted.length);
      fullPacket.setRange(0, header.length, header);
      fullPacket.setRange(header.length, fullPacket.length, decrypted);

      return RtpPacket.parse(fullPacket);
    } catch (e) {
      throw StateError('SRTP decryption failed: $e');
    }
  }

  /// Get or initialize ROC (Rollover Counter) for an SSRC
  int _getROC(int ssrc, int sequenceNumber) {
    if (!_rocMap.containsKey(ssrc)) {
      _rocMap[ssrc] = 0;
      return 0;
    }

    final currentRoc = _rocMap[ssrc]!;
    // In a full implementation, we'd detect sequence number wraparound
    // and increment ROC. For now, keep it simple.
    return currentRoc;
  }

  /// Build nonce (IV) for AES-GCM - creates new buffer
  /// RFC 7714 Section 8.1
  ///
  /// IV format: 00 || SSRC || ROC || SEQ, XOR with salt
  /// Bytes: [0, 0, SSRC(4 bytes), ROC(4 bytes), SEQ(2 bytes)]
  Uint8List _buildNonce(int ssrc, int seq, int roc) {
    final nonce = Uint8List(12);

    // First 2 bytes are zero, XOR with salt
    nonce[0] = masterSalt[0];
    nonce[1] = masterSalt[1];

    // SSRC (32-bit) at bytes 2-5, XOR with salt
    nonce[2] = ((ssrc >> 24) & 0xFF) ^ masterSalt[2];
    nonce[3] = ((ssrc >> 16) & 0xFF) ^ masterSalt[3];
    nonce[4] = ((ssrc >> 8) & 0xFF) ^ masterSalt[4];
    nonce[5] = (ssrc & 0xFF) ^ masterSalt[5];

    // ROC (32-bit) at bytes 6-9, XOR with salt
    nonce[6] = ((roc >> 24) & 0xFF) ^ masterSalt[6];
    nonce[7] = ((roc >> 16) & 0xFF) ^ masterSalt[7];
    nonce[8] = ((roc >> 8) & 0xFF) ^ masterSalt[8];
    nonce[9] = (roc & 0xFF) ^ masterSalt[9];

    // SEQ (16-bit) at bytes 10-11, XOR with salt
    nonce[10] = ((seq >> 8) & 0xFF) ^ masterSalt[10];
    nonce[11] = (seq & 0xFF) ^ masterSalt[11];

    return nonce;
  }

  /// Build nonce (IV) for AES-GCM in-place (for decrypt, which is sync)
  /// RFC 7714 Section 8.1
  ///
  /// IV format: 00 || SSRC || ROC || SEQ, XOR with salt
  /// Bytes: [0, 0, SSRC(4 bytes), ROC(4 bytes), SEQ(2 bytes)]
  ///
  /// This method modifies _nonceBuffer in-place to avoid allocations.
  void _buildNonceInPlace(int ssrc, int seq, int roc) {
    // First 2 bytes are zero, XOR with salt
    _nonceBuffer[0] = masterSalt[0];
    _nonceBuffer[1] = masterSalt[1];

    // SSRC (32-bit) at bytes 2-5, XOR with salt
    _nonceBuffer[2] = ((ssrc >> 24) & 0xFF) ^ masterSalt[2];
    _nonceBuffer[3] = ((ssrc >> 16) & 0xFF) ^ masterSalt[3];
    _nonceBuffer[4] = ((ssrc >> 8) & 0xFF) ^ masterSalt[4];
    _nonceBuffer[5] = (ssrc & 0xFF) ^ masterSalt[5];

    // ROC (32-bit) at bytes 6-9, XOR with salt
    _nonceBuffer[6] = ((roc >> 24) & 0xFF) ^ masterSalt[6];
    _nonceBuffer[7] = ((roc >> 16) & 0xFF) ^ masterSalt[7];
    _nonceBuffer[8] = ((roc >> 8) & 0xFF) ^ masterSalt[8];
    _nonceBuffer[9] = (roc & 0xFF) ^ masterSalt[9];

    // SEQ (16-bit) at bytes 10-11, XOR with salt
    _nonceBuffer[10] = ((seq >> 8) & 0xFF) ^ masterSalt[10];
    _nonceBuffer[11] = (seq & 0xFF) ^ masterSalt[11];
  }

  /// Serialize RTP header for AAD (Additional Authenticated Data)
  /// RFC 7714 Section 5: AAD includes the entire RTP header including extension
  Uint8List _serializeHeader(RtpPacket packet) {
    // Use the packet's own serializeHeader method which handles extensions correctly
    return packet.serializeHeader();
  }

  /// Find where RTP header ends in packet
  int _findHeaderEnd(Uint8List packet) {
    if (packet.length < RtpPacket.fixedHeaderSize) {
      throw FormatException('Packet too short');
    }

    final buffer = ByteData.sublistView(packet);
    var offset = RtpPacket.fixedHeaderSize;

    // Parse first byte to get CSRC count and extension flag
    final byte0 = buffer.getUint8(0);
    final csrcCount = byte0 & 0x0F;
    final extension = (byte0 & 0x10) != 0;

    // Skip CSRCs
    offset += csrcCount * 4;

    // Skip extension if present
    if (extension) {
      if (offset + 4 > packet.length) {
        throw FormatException('Truncated extension header');
      }
      final extLength = buffer.getUint16(offset + 2) * 4;
      offset += 4 + extLength;
    }

    return offset;
  }

  /// Reset cipher state
  void reset() {
    _rocMap.clear();
    replayProtection.reset();
    _cachedSecretKey = null;
  }
}
