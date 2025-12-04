import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/srtp/const.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/replay_protection.dart';

/// SRTP Cipher for AES-GCM encryption/decryption
/// RFC 7714 - AES-GCM Authenticated Encryption in SRTP
class SrtpCipher {
  /// Master key
  final Uint8List masterKey;

  /// Master salt
  final Uint8List masterSalt;

  /// Replay protection
  final ReplayProtection replayProtection;

  /// ROC (Rollover Counter) for each SSRC
  /// Tracks how many times the 16-bit sequence number has wrapped around
  final Map<int, int> _rocMap = {};

  SrtpCipher({
    required this.masterKey,
    required this.masterSalt,
    ReplayProtection? replayProtection,
  }) : replayProtection = replayProtection ?? ReplayProtection();

  /// Encrypt RTP packet
  /// Returns encrypted packet bytes
  Future<Uint8List> encrypt(RtpPacket packet) async {
    // Get ROC for this SSRC
    final roc = _getROC(packet.ssrc, packet.sequenceNumber);

    // Derive session keys
    final sessionKey = _deriveSessionKey(packet.ssrc, roc);
    final sessionSalt = _deriveSessionSalt(packet.ssrc, roc);

    // Build nonce (IV)
    final nonce = _buildNonce(sessionSalt, packet.ssrc, packet.sequenceNumber, roc);

    // Serialize RTP header (authenticated data)
    final header = _serializeHeader(packet);

    // Encrypt payload using AES-GCM
    final gcm = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128, // 128-bit auth tag
      nonce,
      header, // Additional authenticated data
    );

    gcm.init(true, params);

    // Allocate output buffer (payload + auth tag)
    final outputLength = packet.payload.length + SrtpAuthTagSize.tag128;
    final output = Uint8List(outputLength);

    // Encrypt
    var outOff = gcm.processBytes(packet.payload, 0, packet.payload.length, output, 0);
    outOff += gcm.doFinal(output, outOff);

    // Build final SRTP packet: header + encrypted_payload + auth_tag
    final result = Uint8List(header.length + output.length);
    result.setRange(0, header.length, header);
    result.setRange(header.length, result.length, output);

    return result;
  }

  /// Decrypt SRTP packet
  /// Returns decrypted RTP packet
  Future<RtpPacket> decrypt(Uint8List srtpPacket) async {
    if (srtpPacket.length < RtpPacket.fixedHeaderSize + SrtpAuthTagSize.tag128) {
      throw FormatException('SRTP packet too short: ${srtpPacket.length} bytes');
    }

    // Parse RTP header (not encrypted)
    final headerEnd = _findHeaderEnd(srtpPacket);
    final header = srtpPacket.sublist(0, headerEnd);

    // Extract encrypted payload
    final encrypted = srtpPacket.sublist(headerEnd, srtpPacket.length);

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

    // Derive session keys
    final sessionKey = _deriveSessionKey(ssrc, roc);
    final sessionSalt = _deriveSessionSalt(ssrc, roc);

    // Build nonce (IV)
    final nonce = _buildNonce(sessionSalt, ssrc, sequenceNumber, roc);

    // Decrypt payload using AES-GCM
    final gcm = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128, // 128-bit auth tag
      nonce,
      header, // Additional authenticated data
    );

    gcm.init(false, params);

    // Allocate output buffer
    final outputLength = encrypted.length - SrtpAuthTagSize.tag128;
    final output = Uint8List(outputLength);

    // Decrypt
    try {
      var outOff = gcm.processBytes(encrypted, 0, encrypted.length, output, 0);
      outOff += gcm.doFinal(output, outOff);

      // Parse decrypted RTP packet
      // Reconstruct full RTP packet with decrypted payload
      final fullPacket = Uint8List(header.length + output.length);
      fullPacket.setRange(0, header.length, header);
      fullPacket.setRange(header.length, fullPacket.length, output);

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

  /// Derive session key from master key
  /// RFC 3711 Section 4.3
  Uint8List _deriveSessionKey(int ssrc, int roc) {
    // Use master key directly (key derivation is done at session level)
    // In practice, we'd derive per-packet or per-ROC keys
    return masterKey;
  }

  /// Derive session salt from master salt
  /// RFC 3711 Section 4.3
  Uint8List _deriveSessionSalt(int ssrc, int roc) {
    // Use master salt directly (salt derivation is done at session level)
    return masterSalt;
  }

  /// Build nonce (IV) for AES-GCM
  /// RFC 7714 Section 8.1
  ///
  /// Nonce = (SSRC || ROC || SEQ) XOR salt
  Uint8List _buildNonce(Uint8List salt, int ssrc, int seq, int roc) {
    final nonce = Uint8List(12);

    // Construct packet index: 48-bit (ROC || SEQ)
    // SSRC (32-bit) at bytes 0-3
    nonce[0] = (ssrc >> 24) & 0xFF;
    nonce[1] = (ssrc >> 16) & 0xFF;
    nonce[2] = (ssrc >> 8) & 0xFF;
    nonce[3] = ssrc & 0xFF;

    // ROC (32-bit) at bytes 4-7
    nonce[4] = (roc >> 24) & 0xFF;
    nonce[5] = (roc >> 16) & 0xFF;
    nonce[6] = (roc >> 8) & 0xFF;
    nonce[7] = roc & 0xFF;

    // SEQ (16-bit) at bytes 8-9, pad with zeros at bytes 10-11
    nonce[8] = (seq >> 8) & 0xFF;
    nonce[9] = seq & 0xFF;
    nonce[10] = 0;
    nonce[11] = 0;

    // XOR with salt
    for (var i = 0; i < 12; i++) {
      nonce[i] ^= salt[i];
    }

    return nonce;
  }

  /// Serialize RTP header for AAD (Additional Authenticated Data)
  Uint8List _serializeHeader(RtpPacket packet) {
    // For simplicity, serialize a basic header
    // In practice, we'd serialize the exact header from the packet
    final header = Uint8List(12 + packet.csrcs.length * 4);
    final buffer = ByteData.sublistView(header);

    var offset = 0;
    // Byte 0
    int byte0 = (packet.version << 6) |
        (packet.padding ? 1 << 5 : 0) |
        (packet.extension ? 1 << 4 : 0) |
        (packet.csrcCount & 0x0F);
    buffer.setUint8(offset++, byte0);

    // Byte 1
    int byte1 = (packet.marker ? 1 << 7 : 0) | (packet.payloadType & 0x7F);
    buffer.setUint8(offset++, byte1);

    // Sequence number
    buffer.setUint16(offset, packet.sequenceNumber);
    offset += 2;

    // Timestamp
    buffer.setUint32(offset, packet.timestamp);
    offset += 4;

    // SSRC
    buffer.setUint32(offset, packet.ssrc);
    offset += 4;

    // CSRCs
    for (final csrc in packet.csrcs) {
      buffer.setUint32(offset, csrc);
      offset += 4;
    }

    return header;
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
  }
}
