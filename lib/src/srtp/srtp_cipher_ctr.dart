import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';
import 'package:webrtc_dart/src/srtp/const.dart';

/// SRTP/SRTCP Cipher for AES-128-CM-HMAC-SHA1-80
/// RFC 3711 - AES Counter Mode encryption with HMAC-SHA1 authentication
///
/// This is the standard SRTP profile used by browsers and most WebRTC implementations.
/// Unlike AES-GCM, this uses separate encryption (AES-CTR) and authentication (HMAC-SHA1).
class SrtpCipherCtr {
  /// Authentication tag length (10 bytes for HMAC-SHA1-80)
  static const int authTagLength = SrtpAuthTagSize.tag80;

  /// SRTCP index length (4 bytes)
  static const int srtcpIndexLength = 4;

  /// SRTP session encryption key
  final Uint8List srtpSessionKey;

  /// SRTP session salt
  final Uint8List srtpSessionSalt;

  /// SRTP session authentication key
  final Uint8List srtpSessionAuthKey;

  /// SRTCP session encryption key
  final Uint8List srtcpSessionKey;

  /// SRTCP session salt
  final Uint8List srtcpSessionSalt;

  /// SRTCP session authentication key
  final Uint8List srtcpSessionAuthKey;

  /// Rollover counter for SRTP (tracks full 48-bit index)
  int _rolloverCounter = 0;

  /// Highest sequence number seen
  int _highestSeq = 0;

  /// Whether we've seen the first packet
  bool _firstPacket = true;

  /// SRTCP index counter
  int _srtcpIndex = 0;

  /// Cached stream cipher for AES-CTR (reused across packets)
  late final SICStreamCipher _cipher;

  /// Cached HMAC for SRTP auth tags (reused across packets)
  late final HMac _srtpHmac;

  /// Cached HMAC for SRTCP auth tags (reused across packets)
  late final HMac _srtcpHmac;

  /// Pre-allocated counter buffer (reused across packets)
  final Uint8List _counterBuffer = Uint8List(16);

  /// Pre-allocated ROC buffer for auth tag (reused across packets)
  final Uint8List _rocBuffer = Uint8List(4);

  SrtpCipherCtr({
    required this.srtpSessionKey,
    required this.srtpSessionSalt,
    required this.srtpSessionAuthKey,
    required this.srtcpSessionKey,
    required this.srtcpSessionSalt,
    required this.srtcpSessionAuthKey,
  }) {
    // Initialize cached cipher and HMAC instances
    _cipher = SICStreamCipher(AESEngine());
    _srtpHmac = HMac(SHA1Digest(), 64);
    _srtcpHmac = HMac(SHA1Digest(), 64);
  }

  /// Create from master key and salt
  factory SrtpCipherCtr.fromMasterKey({
    required Uint8List masterKey,
    required Uint8List masterSalt,
  }) {
    // Derive SRTP session keys
    final srtpKeys = SrtpKeyDerivation.deriveSrtpKeys(
      masterKey: masterKey,
      masterSalt: masterSalt,
      ssrc: 0,
      index: 0,
    );

    // Derive SRTCP session keys
    final srtcpKeys = SrtpKeyDerivation.deriveSrtcpKeys(
      masterKey: masterKey,
      masterSalt: masterSalt,
      ssrc: 0,
      index: 0,
    );

    return SrtpCipherCtr(
      srtpSessionKey: srtpKeys.encryptionKey,
      srtpSessionSalt: srtpKeys.saltingKey,
      srtpSessionAuthKey: srtpKeys.authenticationKey,
      srtcpSessionKey: srtcpKeys.encryptionKey,
      srtcpSessionSalt: srtcpKeys.saltingKey,
      srtcpSessionAuthKey: srtcpKeys.authenticationKey,
    );
  }

  /// Encrypt RTP packet
  Uint8List encryptRtp(RtpPacket packet) {
    // Update rollover counter
    _updateRolloverCounter(packet.sequenceNumber);

    // Serialize header
    final headerBytes = packet.serializeHeader();

    // Generate counter for AES-CTR (in-place)
    _generateCounterInPlace(
      packet.sequenceNumber,
      _rolloverCounter,
      packet.ssrc,
      srtpSessionSalt,
    );

    // Encrypt payload with AES-CTR
    final encryptedPayload = _aesCtrEncrypt(
      srtpSessionKey,
      packet.payload,
    );

    // Generate authentication tag
    final authTag = _generateSrtpAuthTag(
      _rolloverCounter,
      headerBytes,
      encryptedPayload,
    );

    // Combine: header + encrypted payload + auth tag
    final result =
        Uint8List(headerBytes.length + encryptedPayload.length + authTagLength);
    var offset = 0;
    result.setRange(offset, offset + headerBytes.length, headerBytes);
    offset += headerBytes.length;
    result.setRange(offset, offset + encryptedPayload.length, encryptedPayload);
    offset += encryptedPayload.length;
    result.setRange(offset, offset + authTagLength, authTag);

    return result;
  }

  /// Decrypt SRTP packet
  RtpPacket decryptSrtp(Uint8List srtpPacket) {
    // Minimum size: 12 (RTP header) + 10 (auth tag)
    if (srtpPacket.length < RtpPacket.fixedHeaderSize + authTagLength) {
      throw FormatException(
          'SRTP packet too short: ${srtpPacket.length} bytes');
    }

    // Parse header to get sequence number, SSRC, etc.
    final header = RtpPacket.parse(
        srtpPacket.sublist(0, srtpPacket.length - authTagLength));

    // Strip auth tag for decryption
    final cipherText = srtpPacket.sublist(0, srtpPacket.length - authTagLength);

    // Update rollover counter
    _updateRolloverCounter(header.sequenceNumber);

    // Generate counter (in-place)
    _generateCounterInPlace(
      header.sequenceNumber,
      _rolloverCounter,
      header.ssrc,
      srtpSessionSalt,
    );

    // Get encrypted payload (after header)
    final encryptedPayload = cipherText.sublist(header.headerSize);

    // Decrypt payload (AES-CTR decryption is same as encryption)
    final decryptedPayload = _aesCtrEncrypt(
      srtpSessionKey,
      encryptedPayload,
    );

    // Return decrypted packet
    return RtpPacket(
      version: header.version,
      padding: header.padding,
      extension: header.extension,
      marker: header.marker,
      payloadType: header.payloadType,
      sequenceNumber: header.sequenceNumber,
      timestamp: header.timestamp,
      ssrc: header.ssrc,
      csrcs: header.csrcs,
      extensionHeader: header.extensionHeader,
      payload: decryptedPayload,
    );
  }

  /// Encrypt RTCP packet
  Uint8List encryptRtcp(RtcpPacket packet) {
    return encryptRtcpBytes(packet.serialize());
  }

  /// Encrypt compound RTCP packet (pre-serialized bytes)
  /// Used for RTCP compound packets (SR/RR + SDES) per RFC 3550
  Uint8List encryptRtcpBytes(Uint8List plainRtcp) {
    // Extract SSRC from header (bytes 4-7)
    final ssrc = ByteData.sublistView(plainRtcp, 4, 8).getUint32(0);

    // Increment SRTCP index first (werift compatibility: first packet uses index 1)
    _srtcpIndex++;
    final srtcpIndex = _srtcpIndex;

    // Generate counter (in-place)
    _generateCounterInPlace(
      srtcpIndex & 0xffff,
      srtcpIndex >> 16,
      ssrc,
      srtcpSessionSalt,
    );

    // Encrypt payload (everything after 8-byte header)
    final header = plainRtcp.sublist(0, RtcpPacket.headerSize);
    final payload = plainRtcp.sublist(RtcpPacket.headerSize);
    final encryptedPayload = _aesCtrEncrypt(
      srtcpSessionKey,
      payload,
    );

    // Build SRTCP packet: header + encrypted_payload + E|index + auth_tag
    // E-flag is set (MSB of index)
    final indexWithE = srtcpIndex | 0x80000000;

    // Combine header + encrypted payload + index (before computing auth tag)
    final preAuth =
        Uint8List(header.length + encryptedPayload.length + srtcpIndexLength);
    var offset = 0;
    preAuth.setRange(offset, offset + header.length, header);
    offset += header.length;
    preAuth.setRange(
        offset, offset + encryptedPayload.length, encryptedPayload);
    offset += encryptedPayload.length;

    // Write index with E-flag
    final indexBytes = ByteData(4);
    indexBytes.setUint32(0, indexWithE);
    preAuth.setRange(offset, offset + 4, indexBytes.buffer.asUint8List());

    // Generate authentication tag over everything
    final authTag = _generateSrtcpAuthTag(preAuth);

    // Final packet: preAuth + authTag
    final result = Uint8List(preAuth.length + authTagLength);
    result.setRange(0, preAuth.length, preAuth);
    result.setRange(preAuth.length, result.length, authTag);

    return result;
  }

  /// Decrypt SRTCP packet
  RtcpPacket decryptSrtcp(Uint8List srtcpPacket) {
    // Minimum size: 8 (RTCP header) + 4 (index) + 10 (auth tag) = 22 bytes
    if (srtcpPacket.length <
        RtcpPacket.headerSize + srtcpIndexLength + authTagLength) {
      throw FormatException(
          'SRTCP packet too short: ${srtcpPacket.length} bytes');
    }

    // Calculate offsets
    final tailOffset = srtcpPacket.length - (authTagLength + srtcpIndexLength);

    // Extract the plain RTCP portion (header + potentially encrypted payload)
    final rtcpPortion = Uint8List.fromList(srtcpPacket.sublist(0, tailOffset));

    // Extract index with E-flag
    final indexBuffer = ByteData.sublistView(
        srtcpPacket, tailOffset, tailOffset + srtcpIndexLength);
    final indexWithE = indexBuffer.getUint32(0);

    // Check E-flag (encryption flag)
    final isEncrypted = (indexWithE & 0x80000000) != 0;

    // If not encrypted, just parse the RTCP
    if (!isEncrypted) {
      return RtcpPacket.parse(rtcpPortion);
    }

    // Extract index (clear E-flag)
    final srtcpIndex = indexWithE & 0x7FFFFFFF;

    // Extract SSRC from header (bytes 4-7)
    final ssrc = ByteData.sublistView(rtcpPortion, 4, 8).getUint32(0);

    // Generate counter (in-place)
    _generateCounterInPlace(
      srtcpIndex & 0xffff,
      srtcpIndex >> 16,
      ssrc,
      srtcpSessionSalt,
    );

    // Decrypt payload (everything after 8-byte header)
    final encryptedPayload = rtcpPortion.sublist(RtcpPacket.headerSize);
    final decryptedPayload = _aesCtrEncrypt(
      srtcpSessionKey,
      encryptedPayload,
    );

    // Reconstruct decrypted RTCP packet
    final decrypted =
        Uint8List(RtcpPacket.headerSize + decryptedPayload.length);
    decrypted.setRange(0, RtcpPacket.headerSize, rtcpPortion);
    decrypted.setRange(
        RtcpPacket.headerSize, decrypted.length, decryptedPayload);

    return RtcpPacket.parse(decrypted);
  }

  /// Generate counter for AES-CTR in-place
  /// RFC 3711 Section 4.1.1
  /// Modifies _counterBuffer in-place to avoid allocations.
  void _generateCounterInPlace(
    int sequenceNumber,
    int rolloverCounter,
    int ssrc,
    Uint8List sessionSalt,
  ) {
    // Clear first 4 bytes (will be XORed with salt)
    _counterBuffer[0] = sessionSalt[0];
    _counterBuffer[1] = sessionSalt[1];
    _counterBuffer[2] = sessionSalt[2];
    _counterBuffer[3] = sessionSalt[3];

    // SSRC at bytes 4-7 (big-endian), XORed with salt
    _counterBuffer[4] = ((ssrc >> 24) & 0xFF) ^ sessionSalt[4];
    _counterBuffer[5] = ((ssrc >> 16) & 0xFF) ^ sessionSalt[5];
    _counterBuffer[6] = ((ssrc >> 8) & 0xFF) ^ sessionSalt[6];
    _counterBuffer[7] = (ssrc & 0xFF) ^ sessionSalt[7];

    // ROC at bytes 8-11 (big-endian), XORed with salt
    _counterBuffer[8] = ((rolloverCounter >> 24) & 0xFF) ^ sessionSalt[8];
    _counterBuffer[9] = ((rolloverCounter >> 16) & 0xFF) ^ sessionSalt[9];
    _counterBuffer[10] = ((rolloverCounter >> 8) & 0xFF) ^ sessionSalt[10];
    _counterBuffer[11] = (rolloverCounter & 0xFF) ^ sessionSalt[11];

    // Sequence number << 16 at bytes 12-15 (big-endian), XORed with salt
    final seqShifted = sequenceNumber << 16;
    _counterBuffer[12] = ((seqShifted >> 24) & 0xFF) ^ sessionSalt[12];
    _counterBuffer[13] = ((seqShifted >> 16) & 0xFF) ^ sessionSalt[13];
    // Salt is only 14 bytes, so bytes 14-15 are just the sequence
    _counterBuffer[14] = (seqShifted >> 8) & 0xFF;
    _counterBuffer[15] = seqShifted & 0xFF;
  }

  /// AES-CTR encryption/decryption (symmetric)
  /// Uses cached cipher instance and pre-allocated counter buffer.
  Uint8List _aesCtrEncrypt(
    Uint8List key,
    Uint8List data,
  ) {
    if (data.isEmpty) {
      return Uint8List(0);
    }

    // Reinitialize cipher with current key and counter buffer
    _cipher.init(
      true,
      ParametersWithIV(
        KeyParameter(key),
        _counterBuffer,
      ),
    );

    final output = Uint8List(data.length);
    _cipher.processBytes(data, 0, data.length, output, 0);
    return output;
  }

  /// Generate SRTP authentication tag (HMAC-SHA1, truncated to 80 bits)
  /// Uses cached HMAC instance and pre-allocated ROC buffer.
  Uint8List _generateSrtpAuthTag(
    int rolloverCounter,
    Uint8List header,
    Uint8List encryptedPayload,
  ) {
    // Reset and init cached HMAC
    _srtpHmac.reset();
    _srtpHmac.init(KeyParameter(srtpSessionAuthKey));

    // Update with header
    _srtpHmac.update(header, 0, header.length);

    // Update with encrypted payload
    _srtpHmac.update(encryptedPayload, 0, encryptedPayload.length);

    // Update with ROC (4 bytes, big-endian) using pre-allocated buffer
    _rocBuffer[0] = (rolloverCounter >> 24) & 0xFF;
    _rocBuffer[1] = (rolloverCounter >> 16) & 0xFF;
    _rocBuffer[2] = (rolloverCounter >> 8) & 0xFF;
    _rocBuffer[3] = rolloverCounter & 0xFF;
    _srtpHmac.update(_rocBuffer, 0, 4);

    // Get full digest and truncate to 80 bits (10 bytes)
    final digest = Uint8List(20);
    _srtpHmac.doFinal(digest, 0);

    return digest.sublist(0, authTagLength);
  }

  /// Generate SRTCP authentication tag
  /// Uses cached HMAC instance.
  Uint8List _generateSrtcpAuthTag(Uint8List data) {
    // Reset and init cached HMAC
    _srtcpHmac.reset();
    _srtcpHmac.init(KeyParameter(srtcpSessionAuthKey));

    _srtcpHmac.update(data, 0, data.length);

    final digest = Uint8List(20);
    _srtcpHmac.doFinal(digest, 0);

    return digest.sublist(0, authTagLength);
  }

  /// Update rollover counter based on sequence number
  void _updateRolloverCounter(int seq) {
    if (_firstPacket) {
      _highestSeq = seq;
      _firstPacket = false;
      return;
    }

    // Check for wrap-around
    final delta = seq - _highestSeq;
    if (delta > 0) {
      _highestSeq = seq;
    } else if (delta < -0x8000) {
      // Sequence wrapped around
      _rolloverCounter++;
      _highestSeq = seq;
    }
    // If delta is negative but > -0x8000, it's a late/reordered packet
  }

  /// Reset cipher state
  void reset() {
    _rolloverCounter = 0;
    _highestSeq = 0;
    _firstPacket = true;
    _srtcpIndex = 0;
  }
}
