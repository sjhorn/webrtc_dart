import 'dart:io';
import 'dart:typed_data';

import 'const.dart';

/// Address tuple (host, port)
typedef Address = (String, int);

/// Pack an IP address and port
Uint8List packAddress(Address value) {
  final (address, port) = value;

  final addr = InternetAddress(address);
  final protocol =
      addr.type == InternetAddressType.IPv4 ? ipv4Protocol : ipv6Protocol;

  final buffer = ByteData(4);
  buffer.setUint8(0, 0);
  buffer.setUint8(1, protocol);
  buffer.setUint16(2, port);

  final addressBytes = addr.rawAddress;
  final result = Uint8List(4 + addressBytes.length);
  result.setAll(0, buffer.buffer.asUint8List());
  result.setAll(4, addressBytes);

  return result;
}

/// Unpack an IP address and port
Address unpackAddress(Uint8List data) {
  if (data.length < 4) {
    throw ArgumentError('STUN address length is less than 4 bytes');
  }

  final buffer = ByteData.view(data.buffer, data.offsetInBytes);
  final protocol = buffer.getUint8(1);
  final port = buffer.getUint16(2);
  final addressBytes = data.sublist(4);

  switch (protocol) {
    case ipv4Protocol:
      if (addressBytes.length != 4) {
        throw ArgumentError('STUN address has invalid length for IPv4');
      }
      final addr = InternetAddress.fromRawAddress(addressBytes);
      return (addr.address, port);

    case ipv6Protocol:
      if (addressBytes.length != 16) {
        throw ArgumentError('STUN address has invalid length for IPv6');
      }
      final addr = InternetAddress.fromRawAddress(addressBytes,
          type: InternetAddressType.IPv6);
      return (addr.address, port);

    default:
      throw ArgumentError('STUN address has unknown protocol: $protocol');
  }
}

/// XOR an address with the magic cookie and transaction ID
Uint8List xorAddress(Uint8List data, Uint8List transactionId) {
  // Create XOR pad: magic cookie (4 bytes) + transaction ID (12 bytes)
  final xPad = Uint8List(16);
  final cookieData = ByteData(4);
  cookieData.setUint32(0, stunCookie);
  xPad.setAll(0, cookieData.buffer.asUint8List());
  xPad.setAll(4, transactionId);

  // XOR everything except the first 2 bytes
  final result = Uint8List(data.length);
  result.setAll(0, data.sublist(0, 2)); // Copy first 2 bytes unchanged

  for (var i = 2; i < data.length; i++) {
    result[i] = data[i] ^ xPad[i - 2];
  }

  return result;
}

/// Pack XOR-mapped address
Uint8List packXorAddress(Address value, Uint8List transactionId) {
  return xorAddress(packAddress(value), transactionId);
}

/// Unpack XOR-mapped address
Address unpackXorAddress(Uint8List data, Uint8List transactionId) {
  return unpackAddress(xorAddress(data, transactionId));
}

/// Pack error code
Uint8List packErrorCode((int, String) value) {
  final (code, reason) = value;

  final buffer = ByteData(4);
  buffer.setUint16(0, 0);
  buffer.setUint8(2, code ~/ 100); // Class
  buffer.setUint8(3, code % 100); // Number

  final reasonBytes = Uint8List.fromList(reason.codeUnits);
  final result = Uint8List(4 + reasonBytes.length);
  result.setAll(0, buffer.buffer.asUint8List());
  result.setAll(4, reasonBytes);

  return result;
}

/// Unpack error code
(int, String) unpackErrorCode(Uint8List data) {
  if (data.length < 4) {
    throw ArgumentError('STUN error code is less than 4 bytes');
  }

  final buffer = ByteData.view(data.buffer, data.offsetInBytes);
  final codeHigh = buffer.getUint8(2);
  final codeLow = buffer.getUint8(3);
  final code = codeHigh * 100 + codeLow;

  final reasonBytes = data.sublist(4);
  final reason = String.fromCharCodes(reasonBytes);

  return (code, reason);
}

/// Pack unsigned 32-bit integer
Uint8List packUnsigned(int value) {
  final buffer = ByteData(4);
  buffer.setUint32(0, value);
  return buffer.buffer.asUint8List();
}

/// Unpack unsigned 32-bit integer
int unpackUnsigned(Uint8List data) {
  final buffer = ByteData.view(data.buffer, data.offsetInBytes);
  return buffer.getUint32(0);
}

/// Pack unsigned 16-bit integer (with padding to 4 bytes)
Uint8List packUnsignedShort(int value) {
  final buffer = ByteData(4);
  buffer.setUint16(0, value);
  buffer.setUint16(2, 0); // Padding
  return buffer.buffer.asUint8List();
}

/// Unpack unsigned 16-bit integer
int unpackUnsignedShort(Uint8List data) {
  final buffer = ByteData.view(data.buffer, data.offsetInBytes);
  return buffer.getUint16(0);
}

/// Pack unsigned 64-bit integer
Uint8List packUnsigned64(int value) {
  final buffer = ByteData(8);
  buffer.setUint64(0, value);
  return buffer.buffer.asUint8List();
}

/// Unpack unsigned 64-bit integer
int unpackUnsigned64(Uint8List data) {
  final buffer = ByteData.view(data.buffer, data.offsetInBytes);
  return buffer.getUint64(0);
}

/// Pack unsigned 64-bit BigInt
Uint8List packUnsigned64BigInt(BigInt value) {
  final result = Uint8List(8);
  var v = value;
  for (var i = 7; i >= 0; i--) {
    result[i] = (v & BigInt.from(0xFF)).toInt();
    v = v >> 8;
  }
  return result;
}

/// Unpack unsigned 64-bit BigInt
BigInt unpackUnsigned64BigInt(Uint8List data) {
  var result = BigInt.zero;
  for (var i = 0; i < 8; i++) {
    result = (result << 8) | BigInt.from(data[i]);
  }
  return result;
}

/// Pack string
Uint8List packString(String value) {
  return Uint8List.fromList(value.codeUnits);
}

/// Unpack string
String unpackString(Uint8List data) {
  return String.fromCharCodes(data);
}

/// Pack bytes (identity function)
Uint8List packBytes(dynamic value) {
  return value as Uint8List;
}

/// Unpack bytes (identity function)
Uint8List unpackBytes(Uint8List data) {
  return data;
}

/// Pack none (for flag attributes)
Uint8List packNone(dynamic value) {
  return Uint8List(0);
}

/// Unpack none (for flag attributes)
dynamic unpackNone(Uint8List data) {
  return null;
}

/// Attribute definition
class AttributeDefinition {
  final StunAttributeType type;
  final Uint8List Function(dynamic) pack;
  final dynamic Function(Uint8List, [Uint8List?]) unpack;

  const AttributeDefinition(this.type, this.pack, this.unpack);
}

/// Map of attribute types to their definitions
final Map<StunAttributeType, AttributeDefinition> attributeDefinitions = {
  StunAttributeType.mappedAddress: AttributeDefinition(
    StunAttributeType.mappedAddress,
    (v) => packAddress(v as Address),
    (d, [tid]) => unpackAddress(d),
  ),
  StunAttributeType.changeRequest: AttributeDefinition(
    StunAttributeType.changeRequest,
    (v) => packUnsigned(v as int),
    (d, [tid]) => unpackUnsigned(d),
  ),
  StunAttributeType.sourceAddress: AttributeDefinition(
    StunAttributeType.sourceAddress,
    (v) => packAddress(v as Address),
    (d, [tid]) => unpackAddress(d),
  ),
  StunAttributeType.changedAddress: AttributeDefinition(
    StunAttributeType.changedAddress,
    (v) => packAddress(v as Address),
    (d, [tid]) => unpackAddress(d),
  ),
  StunAttributeType.username: AttributeDefinition(
    StunAttributeType.username,
    (v) => packString(v as String),
    (d, [tid]) => unpackString(d),
  ),
  StunAttributeType.messageIntegrity: AttributeDefinition(
    StunAttributeType.messageIntegrity,
    packBytes,
    (d, [tid]) => unpackBytes(d),
  ),
  StunAttributeType.errorCode: AttributeDefinition(
    StunAttributeType.errorCode,
    (v) => packErrorCode(v as (int, String)),
    (d, [tid]) => unpackErrorCode(d),
  ),
  StunAttributeType.channelNumber: AttributeDefinition(
    StunAttributeType.channelNumber,
    (v) => packUnsignedShort(v as int),
    (d, [tid]) => unpackUnsignedShort(d),
  ),
  StunAttributeType.lifetime: AttributeDefinition(
    StunAttributeType.lifetime,
    (v) => packUnsigned(v as int),
    (d, [tid]) => unpackUnsigned(d),
  ),
  StunAttributeType.xorPeerAddress: AttributeDefinition(
    StunAttributeType.xorPeerAddress,
    (v) => throw UnimplementedError('Use packXorAddress with transaction ID'),
    (d, [tid]) => unpackXorAddress(d, tid!),
  ),
  StunAttributeType.data: AttributeDefinition(
    StunAttributeType.data,
    packBytes,
    (d, [tid]) => unpackBytes(d),
  ),
  StunAttributeType.realm: AttributeDefinition(
    StunAttributeType.realm,
    (v) => packString(v as String),
    (d, [tid]) => unpackString(d),
  ),
  StunAttributeType.nonce: AttributeDefinition(
    StunAttributeType.nonce,
    packBytes,
    (d, [tid]) => unpackBytes(d),
  ),
  StunAttributeType.xorRelayedAddress: AttributeDefinition(
    StunAttributeType.xorRelayedAddress,
    (v) => throw UnimplementedError('Use packXorAddress with transaction ID'),
    (d, [tid]) => unpackXorAddress(d, tid!),
  ),
  StunAttributeType.requestedTransport: AttributeDefinition(
    StunAttributeType.requestedTransport,
    (v) => packUnsigned(v as int),
    (d, [tid]) => unpackUnsigned(d),
  ),
  StunAttributeType.xorMappedAddress: AttributeDefinition(
    StunAttributeType.xorMappedAddress,
    (v) => throw UnimplementedError('Use packXorAddress with transaction ID'),
    (d, [tid]) => unpackXorAddress(d, tid!),
  ),
  StunAttributeType.priority: AttributeDefinition(
    StunAttributeType.priority,
    (v) => packUnsigned(v as int),
    (d, [tid]) => unpackUnsigned(d),
  ),
  StunAttributeType.useCandidate: AttributeDefinition(
    StunAttributeType.useCandidate,
    packNone,
    (d, [tid]) => unpackNone(d),
  ),
  StunAttributeType.software: AttributeDefinition(
    StunAttributeType.software,
    (v) => packString(v as String),
    (d, [tid]) => unpackString(d),
  ),
  StunAttributeType.fingerprint: AttributeDefinition(
    StunAttributeType.fingerprint,
    (v) => packUnsigned(v as int),
    (d, [tid]) => unpackUnsigned(d),
  ),
  StunAttributeType.iceControlled: AttributeDefinition(
    StunAttributeType.iceControlled,
    (v) => packUnsigned64BigInt(v is BigInt ? v : BigInt.from(v as int)),
    (d, [tid]) => unpackUnsigned64BigInt(d),
  ),
  StunAttributeType.iceControlling: AttributeDefinition(
    StunAttributeType.iceControlling,
    (v) => packUnsigned64BigInt(v is BigInt ? v : BigInt.from(v as int)),
    (d, [tid]) => unpackUnsigned64BigInt(d),
  ),
  StunAttributeType.responseOrigin: AttributeDefinition(
    StunAttributeType.responseOrigin,
    (v) => packAddress(v as Address),
    (d, [tid]) => unpackAddress(d),
  ),
  StunAttributeType.otherAddress: AttributeDefinition(
    StunAttributeType.otherAddress,
    (v) => packAddress(v as Address),
    (d, [tid]) => unpackAddress(d),
  ),
};

/// Calculate padding length for STUN attributes (must be 4-byte aligned)
int paddingLength(int length) {
  final rest = length % 4;
  return rest == 0 ? 0 : 4 - rest;
}
