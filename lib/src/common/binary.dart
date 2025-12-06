import 'dart:math' as math;
import 'dart:typed_data';

/// Generate random 16-bit unsigned integer
int random16() {
  final bytes = Uint8List(2);
  final random = math.Random.secure();
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return ByteData.view(bytes.buffer).getUint16(0);
}

/// Generate random 32-bit unsigned integer
int random32() {
  final bytes = Uint8List(4);
  final random = math.Random.secure();
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return ByteData.view(bytes.buffer).getUint32(0);
}

/// XOR two byte buffers together
Uint8List bufferXor(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    throw ArgumentError(
      'Cannot XOR buffers with different lengths: ${a.length} != ${b.length}',
    );
  }

  final result = Uint8List(a.length);
  for (var i = 0; i < a.length; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

/// XOR multiple byte buffers together
Uint8List bufferArrayXor(List<Uint8List> buffers) {
  if (buffers.isEmpty) {
    return Uint8List(0);
  }

  final maxLength = buffers.map((b) => b.length).reduce(math.max);
  final result = Uint8List(maxLength);

  for (var i = 0; i < maxLength; i++) {
    var xored = 0;
    for (final buffer in buffers) {
      if (i < buffer.length) {
        xored ^= buffer[i];
      }
    }
    result[i] = xored;
  }

  return result;
}

/// Bit writer for packing bit fields into bytes
class BitWriter {
  int value = 0;
  final int bitLength;

  BitWriter(this.bitLength);

  /// Set bits at position
  BitWriter set(int size, int startIndex, int value) {
    value &= (1 << size) - 1;
    this.value |= value << (bitLength - size - startIndex);
    return this;
  }

  /// Get buffer representation
  Uint8List get buffer {
    final length = (bitLength / 8).ceil();
    final buf = ByteData(length);

    // Write the value as big-endian
    if (length == 1) {
      buf.setUint8(0, value);
    } else if (length == 2) {
      buf.setUint16(0, value);
    } else if (length <= 4) {
      buf.setUint32(0, value);
    } else {
      // For larger sizes, write byte by byte
      for (var i = 0; i < length; i++) {
        buf.setUint8(i, (value >> ((length - 1 - i) * 8)) & 0xff);
      }
    }

    return buf.buffer.asUint8List(0, length);
  }
}

/// Alternative bit writer with sequential writing
class BitWriter2 {
  int _value = 0;
  int offset = 0;
  final int bitLength;

  /// Create bit writer (max 32 bits)
  BitWriter2(this.bitLength) {
    if (bitLength > 32) {
      throw ArgumentError('BitWriter2 supports maximum 32 bits');
    }
  }

  /// Set value with size
  BitWriter2 set(int value, [int size = 1]) {
    value &= (1 << size) - 1;
    _value |= value << (bitLength - size - offset);
    offset += size;
    return this;
  }

  /// Get current value
  int get value => _value;

  /// Get buffer representation
  Uint8List get buffer {
    final length = (bitLength / 8).ceil();
    final buf = ByteData(length);

    if (length == 1) {
      buf.setUint8(0, _value);
    } else if (length == 2) {
      buf.setUint16(0, _value);
    } else if (length <= 4) {
      buf.setUint32(0, _value);
    } else {
      for (var i = 0; i < length; i++) {
        buf.setUint8(i, (_value >> ((length - 1 - i) * 8)) & 0xff);
      }
    }

    return buf.buffer.asUint8List(0, length);
  }
}

/// Get bit value from byte
int getBit(int bits, int startIndex, [int length = 1]) {
  var bin = bits.toRadixString(2).split('');
  bin = [...List.filled(8 - bin.length, '0'), ...bin];
  final s = bin.sublist(startIndex, startIndex + length).join('');
  return int.parse(s, radix: 2);
}

/// Pad byte to 8-bit binary string
String paddingByte(int bits) {
  final dec = bits.toRadixString(2).split('');
  return [...List.filled(8 - dec.length, '0'), ...dec].join('');
}

/// Pad bits to expected length binary string
String paddingBits(int bits, int expectLength) {
  final dec = bits.toRadixString(2);
  return List.filled(expectLength - dec.length, '0').join('') + dec;
}

/// Write multiple values with specified byte sizes
Uint8List bufferWriter(List<int> bytes, List<int> values) {
  final length = bytes.fold<int>(0, (acc, cur) => acc + cur);
  final buf = ByteData(length);
  var offset = 0;

  for (var i = 0; i < values.length; i++) {
    final size = bytes[i];
    final value = values[i];

    if (size == 1) {
      buf.setUint8(offset, value);
    } else if (size == 2) {
      buf.setUint16(offset, value);
    } else if (size == 4) {
      buf.setUint32(offset, value);
    } else if (size == 8) {
      buf.setUint64(offset, value);
    } else {
      // Write multi-byte value
      for (var j = 0; j < size; j++) {
        buf.setUint8(offset + j, (value >> ((size - 1 - j) * 8)) & 0xff);
      }
    }

    offset += size;
  }

  return buf.buffer.asUint8List(0, length);
}

/// Write multiple values with specified byte sizes (little-endian)
Uint8List bufferWriterLE(List<int> bytes, List<int> values) {
  final length = bytes.fold<int>(0, (acc, cur) => acc + cur);
  final buf = ByteData(length);
  var offset = 0;

  for (var i = 0; i < values.length; i++) {
    final size = bytes[i];
    final value = values[i];

    if (size == 1) {
      buf.setUint8(offset, value);
    } else if (size == 2) {
      buf.setUint16(offset, value, Endian.little);
    } else if (size == 4) {
      buf.setUint32(offset, value, Endian.little);
    } else if (size == 8) {
      buf.setUint64(offset, value, Endian.little);
    } else {
      // Write multi-byte value in little-endian
      for (var j = 0; j < size; j++) {
        buf.setUint8(offset + j, (value >> (j * 8)) & 0xff);
      }
    }

    offset += size;
  }

  return buf.buffer.asUint8List(0, length);
}

/// Read multiple values with specified byte sizes
List<int> bufferReader(Uint8List buffer, List<int> bytes) {
  final buf = ByteData.view(buffer.buffer, buffer.offsetInBytes);
  var offset = 0;
  final result = <int>[];

  for (final size in bytes) {
    int value;

    if (size == 1) {
      value = buf.getUint8(offset);
    } else if (size == 2) {
      value = buf.getUint16(offset);
    } else if (size == 4) {
      value = buf.getUint32(offset);
    } else if (size == 8) {
      value = buf.getUint64(offset);
    } else {
      // Read multi-byte value
      value = 0;
      for (var j = 0; j < size; j++) {
        value = (value << 8) | buf.getUint8(offset + j);
      }
    }

    result.add(value);
    offset += size;
  }

  return result;
}

/// Chainable buffer writer
class BufferChain {
  final ByteData _data;

  BufferChain(int size) : _data = ByteData(size);

  /// Write 16-bit signed integer (big-endian)
  BufferChain writeInt16BE(int value, int offset) {
    _data.setInt16(offset, value);
    return this;
  }

  /// Write 8-bit unsigned integer
  BufferChain writeUInt8(int value, int offset) {
    _data.setUint8(offset, value);
    return this;
  }

  /// Get the buffer
  Uint8List get buffer => _data.buffer.asUint8List();
}

/// Dump buffer as hex string
String dumpBuffer(Uint8List data) {
  return data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(',');
}

/// Bit stream for reading/writing bits
class BitStream {
  final Uint8List uint8Array;
  int _position = 0;
  int _bitsPending = 0;

  BitStream(this.uint8Array);

  /// Write bits to stream
  BitStream writeBits(int bits, int value) {
    if (bits == 0) {
      return this;
    }

    value &= 0xffffffff >> (32 - bits);
    int bitsConsumed;

    if (_bitsPending > 0) {
      if (_bitsPending > bits) {
        uint8Array[_position - 1] |= value << (_bitsPending - bits);
        bitsConsumed = bits;
        _bitsPending -= bits;
      } else if (_bitsPending == bits) {
        uint8Array[_position - 1] |= value;
        bitsConsumed = bits;
        _bitsPending = 0;
      } else {
        uint8Array[_position - 1] |= value >> (bits - _bitsPending);
        bitsConsumed = _bitsPending;
        _bitsPending = 0;
      }
    } else {
      bitsConsumed = math.min(8, bits);
      _bitsPending = 8 - bitsConsumed;
      uint8Array[_position++] =
          (value >> (bits - bitsConsumed)) << _bitsPending;
    }

    bits -= bitsConsumed;
    if (bits > 0) {
      writeBits(bits, value);
    }

    return this;
  }

  /// Read bits from stream
  int readBits(int bits) {
    return _readBits(bits, 0);
  }

  int _readBits(int bits, int bitBuffer) {
    if (bits == 0) {
      return bitBuffer;
    }

    int partial;
    int bitsConsumed;

    if (_bitsPending > 0) {
      final byte = uint8Array[_position - 1] & (0xff >> (8 - _bitsPending));
      bitsConsumed = math.min(_bitsPending, bits);
      _bitsPending -= bitsConsumed;
      partial = byte >> _bitsPending;
    } else {
      bitsConsumed = math.min(8, bits);
      _bitsPending = 8 - bitsConsumed;
      partial = uint8Array[_position++] >> _bitsPending;
    }

    bits -= bitsConsumed;
    bitBuffer = (bitBuffer << bitsConsumed) | partial;
    return bits > 0 ? _readBits(bits, bitBuffer) : bitBuffer;
  }

  /// Seek to bit position
  void seekTo(int bitPos) {
    _position = bitPos ~/ 8;
    _bitsPending = bitPos % 8;
    if (_bitsPending > 0) {
      _bitsPending = 8 - _bitsPending;
      _position++;
    }
  }
}
