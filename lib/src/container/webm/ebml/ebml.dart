import 'dart:typed_data';

/// EBML (Extensible Binary Meta Language) encoding/decoding
/// Used as the binary format for WebM/Matroska containers
/// See: https://www.matroska.org/technical/specs/index.html

/// Interface for EBML data that can be written to a buffer
abstract class EbmlData {
  /// Write this data to the buffer at the given position
  /// Returns the new position after writing
  int write(Uint8List buf, int pos);

  /// Calculate the total size of this data in bytes
  int countSize();
}

/// A raw byte value
class EbmlValue implements EbmlData {
  final Uint8List bytes;

  EbmlValue(this.bytes);

  @override
  int write(Uint8List buf, int pos) {
    buf.setAll(pos, bytes);
    return pos + bytes.length;
  }

  @override
  int countSize() => bytes.length;
}

/// An EBML element with ID, size, and children
class EbmlElement implements EbmlData {
  final Uint8List id;
  final List<EbmlData> children;
  final int _size;
  final Uint8List _sizeMetaData;

  EbmlElement._(this.id, this.children, this._size, this._sizeMetaData);

  factory EbmlElement(Uint8List id, List<EbmlData> children,
      {bool isSizeUnknown = false}) {
    final bodySize = children.fold<int>(0, (p, c) => p + c.countSize());
    final sizeMetaData = isSizeUnknown
        ? unknownSize
        : vintEncode(numberToByteArray(bodySize, getEbmlByteLength(bodySize)));
    final size = id.length + sizeMetaData.length + bodySize;
    return EbmlElement._(id, children, size, sizeMetaData);
  }

  @override
  int write(Uint8List buf, int pos) {
    buf.setAll(pos, id);
    buf.setAll(pos + id.length, _sizeMetaData);
    var offset = pos + id.length + _sizeMetaData.length;
    for (final child in children) {
      offset = child.write(buf, offset);
    }
    return offset;
  }

  @override
  int countSize() => _size;
}

// EBML helper functions

/// Create an EBML value from raw bytes
EbmlValue ebmlBytes(Uint8List data) => EbmlValue(data);

/// Create an EBML value from a number
EbmlValue ebmlNumber(int num) => ebmlBytes(numberToByteArray(num));

/// Create an EBML value from a float
EbmlValue ebmlFloat(double num) => ebmlBytes(float32bit(num));

/// Create an EBML value from a vint-encoded number
EbmlValue ebmlVintEncodedNumber(int num) =>
    ebmlBytes(vintEncode(numberToByteArray(num, getEbmlByteLength(num))));

/// Create an EBML value from a string
EbmlValue ebmlString(String str) => ebmlBytes(stringToByteArray(str));

/// Create an EBML element with known size
EbmlData ebmlElement(Uint8List id, dynamic child) {
  final children =
      child is List<EbmlData> ? child : <EbmlData>[child as EbmlData];
  return EbmlElement(id, children);
}

/// Create an EBML element with unknown size
EbmlData ebmlUnknownSizeElement(Uint8List id, dynamic child) {
  final children =
      child is List<EbmlData> ? child : <EbmlData>[child as EbmlData];
  return EbmlElement(id, children, isSizeUnknown: true);
}

/// Build an EBML data structure into a byte array
Uint8List ebmlBuild(EbmlData v) {
  final b = Uint8List(v.countSize());
  v.write(b, 0);
  return b;
}

// VINT (Variable-length Integer) encoding/decoding

/// Unknown size marker (8 bytes, all value bits = 1)
final Uint8List unknownSize =
    Uint8List.fromList([0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);

/// Get the byte length needed to encode a number in EBML VINT format
int getEbmlByteLength(int num) {
  if (num < 0x7f) {
    return 1;
  } else if (num < 0x3fff) {
    return 2;
  } else if (num < 0x1fffff) {
    return 3;
  } else if (num < 0xfffffff) {
    return 4;
  } else if (num < 0x7ffffffff) {
    return 5;
  } else if (num < 0x3ffffffffff) {
    return 6;
  } else if (num < 0x1ffffffffffff) {
    return 7;
  } else {
    return 8;
  }
}

/// Get the size marker mask for a given byte length
int getSizeMask(int byteLength) => 0x80 >> (byteLength - 1);

/// Encode a byte array as a VINT by adding the size marker
Uint8List vintEncode(Uint8List byteArray) {
  final result = Uint8List.fromList(byteArray);
  result[0] = getSizeMask(byteArray.length) | result[0];
  return result;
}

/// Result of decoding a VINT
class VintDecodeResult {
  /// The decoded value (null if unknown size sentinel)
  final int? value;

  /// Total number of bytes consumed
  final int length;

  /// True if this VINT represents unknown size
  final bool unknown;

  VintDecodeResult({this.value, required this.length, required this.unknown});
}

/// Decode an EBML VINT from a buffer
VintDecodeResult vintDecode(Uint8List buf, [int offset = 0]) {
  if (offset >= buf.length) {
    throw FormatException('vintDecode: offset out of range');
  }
  final first = buf[offset];
  if (first == 0) {
    throw FormatException('vintDecode: invalid first byte 0x00');
  }

  // Determine length by locating first set bit
  int length = 0;
  for (int i = 0; i < 8; i++) {
    final mask = 0x80 >> i;
    if ((first & mask) != 0) {
      length = i + 1;
      break;
    }
  }
  if (length == 0) {
    throw FormatException('vintDecode: could not determine length');
  }
  if (offset + length > buf.length) {
    throw FormatException('vintDecode: insufficient bytes');
  }

  // Mask out the length marker in the first byte
  final lengthMarker = getSizeMask(length);
  int value = first & ~lengthMarker;

  for (int i = 1; i < length; i++) {
    value = (value << 8) | buf[offset + i];
  }

  // Maximum value (all value bits = 1) indicates unknown size
  final allOnes = (1 << (7 * length)) - 1;
  final unknown = value == allOnes;

  return VintDecodeResult(
    value: unknown ? null : value,
    length: length,
    unknown: unknown,
  );
}

/// Decode a vint-encoded number (throws on unknown size)
({int value, int length}) decodeVintEncodedNumber(Uint8List buf,
    [int offset = 0]) {
  final result = vintDecode(buf, offset);
  if (result.unknown || result.value == null) {
    throw FormatException('decodeVintEncodedNumber: unknown size sentinel');
  }
  return (value: result.value!, length: result.length);
}

// Binary utility functions

/// Get the byte length needed to represent a number
int getNumberByteLength(int num) {
  if (num < 0) {
    throw ArgumentError('Negative numbers not supported');
  } else if (num < 0x100) {
    return 1;
  } else if (num < 0x10000) {
    return 2;
  } else if (num < 0x1000000) {
    return 3;
  } else if (num < 0x100000000) {
    return 4;
  } else if (num < 0x10000000000) {
    return 5;
  } else if (num < 0x1000000000000) {
    return 6;
  } else if (num < 0x20000000000000) {
    return 7;
  } else {
    return 8;
  }
}

/// Convert a number to a byte array
Uint8List numberToByteArray(int num, [int? byteLength]) {
  byteLength ??= getNumberByteLength(num);

  final buffer = Uint8List(byteLength);
  final view = ByteData.view(buffer.buffer);

  switch (byteLength) {
    case 1:
      view.setUint8(0, num);
      break;
    case 2:
      view.setUint16(0, num);
      break;
    case 3:
      view.setUint8(0, num >> 16);
      view.setUint16(1, num & 0xffff);
      break;
    case 4:
      view.setUint32(0, num);
      break;
    case 5:
      view.setUint8(0, (num ~/ 0x100000000));
      view.setUint32(1, num % 0x100000000);
      break;
    case 6:
      view.setUint16(0, (num ~/ 0x100000000));
      view.setUint32(2, num % 0x100000000);
      break;
    case 7:
      view.setUint8(0, (num ~/ 0x1000000000000));
      view.setUint16(1, (num ~/ 0x100000000) & 0xffff);
      view.setUint32(3, num % 0x100000000);
      break;
    case 8:
      view.setUint32(0, (num ~/ 0x100000000));
      view.setUint32(4, num % 0x100000000);
      break;
    default:
      throw ArgumentError('Byte length must be 1-8');
  }
  return buffer;
}

/// Convert a string to a byte array (ASCII)
Uint8List stringToByteArray(String str) {
  return Uint8List.fromList(str.codeUnits);
}

/// Convert a 16-bit signed integer to bytes
Uint8List int16bit(int num) {
  final buffer = Uint8List(2);
  ByteData.view(buffer.buffer).setInt16(0, num);
  return buffer;
}

/// Convert a 32-bit float to bytes
Uint8List float32bit(double num) {
  final buffer = Uint8List(4);
  ByteData.view(buffer.buffer).setFloat32(0, num);
  return buffer;
}

/// Convert a 64-bit float to bytes
Uint8List float64bit(double num) {
  final buffer = Uint8List(8);
  ByteData.view(buffer.buffer).setFloat64(0, num);
  return buffer;
}

/// Dump bytes as hex string for debugging
String dumpBytes(Uint8List b) {
  return b.map((v) => '0x${v.toRadixString(16).padLeft(2, '0')}').join(', ');
}
