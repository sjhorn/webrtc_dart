import 'dart:typed_data';

import 'package:webrtc_dart/src/common/crypto.dart';

import 'attributes.dart';
import 'const.dart';

/// Generate random transaction ID (96 bits / 12 bytes)
Uint8List randomTransactionId() {
  return randomBytes(12);
}

/// STUN Message
class StunMessage {
  final StunMethod method;
  final StunClass messageClass;
  final Uint8List transactionId;
  final Map<StunAttributeType, dynamic> attributes;

  StunMessage({
    required this.method,
    required this.messageClass,
    Uint8List? transactionId,
    Map<StunAttributeType, dynamic>? attributes,
  })  : transactionId = transactionId ?? randomTransactionId(),
        attributes = attributes ?? {};

  /// Get transaction ID as hex string
  String get transactionIdHex {
    return transactionId
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  /// Get message type (combination of method and class)
  int get messageType => method.value | messageClass.value;

  /// Set an attribute
  void setAttribute(StunAttributeType type, dynamic value) {
    attributes[type] = value;
  }

  /// Get an attribute value
  dynamic getAttribute(StunAttributeType type) {
    return attributes[type];
  }

  /// Check if attribute exists
  bool hasAttribute(StunAttributeType type) {
    return attributes.containsKey(type);
  }

  /// Remove an attribute
  void removeAttribute(StunAttributeType type) {
    attributes.remove(type);
  }

  /// Serialize message to bytes
  Uint8List toBytes() {
    // Build attributes
    final attributesData = <Uint8List>[];

    for (final entry in attributes.entries) {
      final attrType = entry.key;
      final attrValue = entry.value;

      final def = attributeDefinitions[attrType];
      if (def == null) {
        continue;
      }

      // Pack the attribute value
      Uint8List attrData;
      if (attrType == StunAttributeType.xorMappedAddress ||
          attrType == StunAttributeType.xorPeerAddress ||
          attrType == StunAttributeType.xorRelayedAddress) {
        // XOR attributes need transaction ID
        attrData = packXorAddress(attrValue as Address, transactionId);
      } else {
        attrData = def.pack(attrValue);
      }

      final attrLen = attrData.length;
      final padLen = paddingLength(attrLen);

      // Build attribute: type (2) + length (2) + value + padding
      final attrHeader = ByteData(4);
      attrHeader.setUint16(0, attrType.value);
      attrHeader.setUint16(2, attrLen);

      final fullAttr = Uint8List(4 + attrLen + padLen);
      fullAttr.setAll(0, attrHeader.buffer.asUint8List());
      fullAttr.setAll(4, attrData);
      // Padding is already zeros

      attributesData.add(fullAttr);
    }

    // Concatenate all attributes
    final attributesBytes = Uint8List.fromList(
      attributesData.expand((x) => x).toList(),
    );

    // Build header
    final header = ByteData(stunHeaderLength);
    header.setUint16(0, messageType);
    header.setUint16(2, attributesBytes.length);
    header.setUint32(4, stunCookie);

    // Transaction ID at bytes 8-19
    final headerBytes = Uint8List(stunHeaderLength);
    headerBytes.setAll(0, header.buffer.asUint8List(0, 8));
    headerBytes.setAll(8, transactionId);

    // Concatenate header + attributes
    final result = Uint8List(stunHeaderLength + attributesBytes.length);
    result.setAll(0, headerBytes);
    result.setAll(stunHeaderLength, attributesBytes);

    return result;
  }

  /// Add MESSAGE-INTEGRITY attribute
  void addMessageIntegrity(Uint8List key) {
    final integrity = computeMessageIntegrity(key);
    setAttribute(StunAttributeType.messageIntegrity, integrity);
  }

  /// Compute MESSAGE-INTEGRITY value
  Uint8List computeMessageIntegrity(Uint8List key) {
    // Remove MESSAGE-INTEGRITY and FINGERPRINT if present
    final tempIntegrity = attributes[StunAttributeType.messageIntegrity];
    final tempFingerprint = attributes[StunAttributeType.fingerprint];
    attributes.remove(StunAttributeType.messageIntegrity);
    attributes.remove(StunAttributeType.fingerprint);

    // Get current bytes
    final data = toBytes();

    // Restore attributes
    if (tempIntegrity != null) {
      attributes[StunAttributeType.messageIntegrity] = tempIntegrity;
    }
    if (tempFingerprint != null) {
      attributes[StunAttributeType.fingerprint] = tempFingerprint;
    }

    // Update length to include MESSAGE-INTEGRITY
    final checkData =
        setBodyLength(data, data.length - stunHeaderLength + integrityLength);

    // Compute HMAC-SHA1
    return hmac('sha1', key, checkData);
  }

  /// Add FINGERPRINT attribute
  void addFingerprint() {
    final fingerprint = computeFingerprint();
    setAttribute(StunAttributeType.fingerprint, fingerprint);
  }

  /// Compute FINGERPRINT value
  int computeFingerprint() {
    // Remove FINGERPRINT if present
    final tempFingerprint = attributes[StunAttributeType.fingerprint];
    attributes.remove(StunAttributeType.fingerprint);

    // Get current bytes
    final data = toBytes();

    // Restore attribute
    if (tempFingerprint != null) {
      attributes[StunAttributeType.fingerprint] = tempFingerprint;
    }

    // Update length to include FINGERPRINT
    final checkData =
        setBodyLength(data, data.length - stunHeaderLength + fingerprintLength);

    // Compute CRC32 and XOR with STUN magic
    final crc = computeCrc32(checkData);
    return crc ^ fingerprintXor;
  }

  @override
  String toString() {
    return 'StunMessage(method: ${method.name}, class: ${messageClass.name}, '
        'transactionId: $transactionIdHex, attributes: ${attributes.length})';
  }
}

/// Parse STUN message from bytes
StunMessage? parseStunMessage(Uint8List data, {Uint8List? integrityKey}) {
  if (data.length < stunHeaderLength) {
    return null;
  }

  final buffer = ByteData.view(data.buffer, data.offsetInBytes);

  // Read header
  final messageType = buffer.getUint16(0);
  final length = buffer.getUint16(2);
  final cookie = buffer.getUint32(4);

  // Verify length
  if (data.length != stunHeaderLength + length) {
    return null;
  }

  // Verify magic cookie
  if (cookie != stunCookie) {
    return null;
  }

  // Extract transaction ID
  final transactionId = data.sublist(8, stunHeaderLength);

  // Extract method and class
  final method = StunMethod.values.firstWhere(
    (m) => m.value == (messageType & 0x3EEF),
    orElse: () => StunMethod.binding,
  );
  final messageClass = StunClass.values.firstWhere(
    (c) => c.value == (messageType & 0x0110),
    orElse: () => StunClass.request,
  );

  // Parse attributes
  final attributes = <StunAttributeType, dynamic>{};
  var pos = stunHeaderLength;

  while (pos <= data.length - 4) {
    final attrType = buffer.getUint16(pos);
    final attrLen = buffer.getUint16(pos + 2);
    final attrData = data.sublist(pos + 4, pos + 4 + attrLen);
    final padLen = paddingLength(attrLen);

    final attrTypeEnum = StunAttributeType.fromValue(attrType);
    if (attrTypeEnum != null) {
      final def = attributeDefinitions[attrTypeEnum];
      if (def != null) {
        try {
          // Unpack attribute
          final value = def.unpack(attrData, transactionId);
          attributes[attrTypeEnum] = value;

          // Verify FINGERPRINT
          if (attrTypeEnum == StunAttributeType.fingerprint) {
            final computedFingerprint =
                _computeFingerprint(data.sublist(0, pos));
            if (value != computedFingerprint) {
              return null; // Fingerprint mismatch
            }
          }

          // Verify MESSAGE-INTEGRITY
          if (attrTypeEnum == StunAttributeType.messageIntegrity &&
              integrityKey != null) {
            final computedIntegrity = _computeMessageIntegrity(
              data.sublist(0, pos),
              integrityKey,
            );
            final expectedIntegrity = value as Uint8List;
            if (!_bytesEqual(computedIntegrity, expectedIntegrity)) {
              return null; // Integrity check failed
            }
          }
        } catch (e) {
          // Skip malformed attributes
        }
      }
    }

    pos += 4 + attrLen + padLen;
  }

  return StunMessage(
    method: method,
    messageClass: messageClass,
    transactionId: transactionId,
    attributes: attributes,
  );
}

/// Update message body length in header
Uint8List setBodyLength(Uint8List data, int length) {
  final result = Uint8List.fromList(data);
  final buffer = ByteData.view(result.buffer);
  buffer.setUint16(2, length);
  return result;
}

/// Compute message integrity
Uint8List _computeMessageIntegrity(Uint8List data, Uint8List key) {
  final checkData =
      setBodyLength(data, data.length - stunHeaderLength + integrityLength);
  return hmac('sha1', key, checkData);
}

/// Compute fingerprint
int _computeFingerprint(Uint8List data) {
  final checkData =
      setBodyLength(data, data.length - stunHeaderLength + fingerprintLength);
  final crc = computeCrc32(checkData);
  return crc ^ fingerprintXor;
}

/// Simple CRC32 implementation
int computeCrc32(Uint8List data) {
  const polynomial = 0xEDB88320;
  var crc = 0xFFFFFFFF;

  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ polynomial;
      } else {
        crc >>= 1;
      }
    }
  }

  return ~crc & 0xFFFFFFFF;
}

/// Compare two byte arrays
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
