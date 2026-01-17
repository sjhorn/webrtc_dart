import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'aes_gcm.dart';

// OpenSSL FFI type definitions
typedef EVP_CIPHER_CTX = Void;
typedef EVP_CIPHER = Void;

// OpenSSL function signatures (native)
typedef EVP_CIPHER_CTX_new_native = Pointer<EVP_CIPHER_CTX> Function();
typedef EVP_CIPHER_CTX_free_native = Void Function(Pointer<EVP_CIPHER_CTX>);
typedef EVP_aes_128_gcm_native = Pointer<EVP_CIPHER> Function();
typedef EVP_aes_256_gcm_native = Pointer<EVP_CIPHER> Function();

typedef EVP_EncryptInit_ex_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<EVP_CIPHER> type,
  Pointer<Void> impl,
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
);

typedef EVP_EncryptUpdate_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
  Pointer<Uint8> input,
  Int32 inl,
);

typedef EVP_EncryptFinal_ex_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
);

typedef EVP_DecryptInit_ex_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<EVP_CIPHER> type,
  Pointer<Void> impl,
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
);

typedef EVP_DecryptUpdate_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
  Pointer<Uint8> input,
  Int32 inl,
);

typedef EVP_DecryptFinal_ex_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
);

typedef EVP_CIPHER_CTX_ctrl_native = Int32 Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Int32 type,
  Int32 arg,
  Pointer<Void> ptr,
);

typedef EVP_CIPHER_CTX_reset_native = Int32 Function(Pointer<EVP_CIPHER_CTX>);

// OpenSSL function signatures (dart)
typedef EVP_CIPHER_CTX_new_dart = Pointer<EVP_CIPHER_CTX> Function();
typedef EVP_CIPHER_CTX_free_dart = void Function(Pointer<EVP_CIPHER_CTX>);
typedef EVP_aes_128_gcm_dart = Pointer<EVP_CIPHER> Function();
typedef EVP_aes_256_gcm_dart = Pointer<EVP_CIPHER> Function();

typedef EVP_EncryptInit_ex_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<EVP_CIPHER> type,
  Pointer<Void> impl,
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
);

typedef EVP_EncryptUpdate_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
  Pointer<Uint8> input,
  int inl,
);

typedef EVP_EncryptFinal_ex_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
);

typedef EVP_DecryptInit_ex_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<EVP_CIPHER> type,
  Pointer<Void> impl,
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
);

typedef EVP_DecryptUpdate_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
  Pointer<Uint8> input,
  int inl,
);

typedef EVP_DecryptFinal_ex_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  Pointer<Uint8> out,
  Pointer<Int32> outl,
);

typedef EVP_CIPHER_CTX_ctrl_dart = int Function(
  Pointer<EVP_CIPHER_CTX> ctx,
  int type,
  int arg,
  Pointer<Void> ptr,
);

typedef EVP_CIPHER_CTX_reset_dart = int Function(Pointer<EVP_CIPHER_CTX>);

// OpenSSL constants
const _EVP_CTRL_GCM_SET_IVLEN = 0x9;
const _EVP_CTRL_GCM_GET_TAG = 0x10;
const _EVP_CTRL_GCM_SET_TAG = 0x11;

/// Find OpenSSL/BoringSSL library on the system.
///
/// Prioritizes explicit known paths to avoid conflicts with Dart SDK's
/// internal BoringSSL. Falls back to standard library lookup on Linux.
String? findOpenSSL() {
  if (Platform.isMacOS) {
    // macOS: Use explicit Homebrew paths to avoid Dart SDK conflicts
    final explicitPaths = [
      '/opt/homebrew/opt/openssl/lib/libcrypto.dylib', // Homebrew ARM
      '/usr/local/opt/openssl/lib/libcrypto.dylib', // Homebrew Intel
    ];
    for (final path in explicitPaths) {
      if (File(path).existsSync()) {
        try {
          DynamicLibrary.open(path);
          return path;
        } catch (_) {}
      }
    }
  } else if (Platform.isLinux) {
    // Linux: Standard library lookup is safer (no Dart SDK conflicts)
    for (final name in ['libcrypto.so.3', 'libcrypto.so.1.1', 'libcrypto.so']) {
      try {
        DynamicLibrary.open(name);
        return name;
      } catch (_) {}
    }
  } else if (Platform.isWindows) {
    // Windows: Try common OpenSSL locations
    final paths = [
      'libcrypto-3-x64.dll',
      'libcrypto-1_1-x64.dll',
      'C:\\Program Files\\OpenSSL-Win64\\bin\\libcrypto-3-x64.dll',
    ];
    for (final path in paths) {
      try {
        if (path.contains('\\')) {
          if (File(path).existsSync()) {
            DynamicLibrary.open(path);
            return path;
          }
        } else {
          DynamicLibrary.open(path);
          return path;
        }
      } catch (_) {}
    }
  }

  return null;
}

/// Check if native crypto (OpenSSL FFI) is available.
bool isNativeCryptoAvailable() {
  return findOpenSSL() != null;
}

/// OpenSSL FFI AES-GCM implementation.
///
/// Uses native OpenSSL via dart:ffi for ~16x faster encryption than pure Dart.
/// Call [isNativeCryptoAvailable] to check availability before using.
class FfiAesGcmCipher implements AesGcmCipher {
  late final DynamicLibrary _lib;
  late final EVP_CIPHER_CTX_new_dart _ctxNew;
  late final EVP_CIPHER_CTX_free_dart _ctxFree;
  late final EVP_CIPHER_CTX_reset_dart _ctxReset;
  late final EVP_aes_128_gcm_dart _aes128gcm;
  late final EVP_aes_256_gcm_dart _aes256gcm;
  late final EVP_EncryptInit_ex_dart _encryptInit;
  late final EVP_EncryptUpdate_dart _encryptUpdate;
  late final EVP_EncryptFinal_ex_dart _encryptFinal;
  late final EVP_DecryptInit_ex_dart _decryptInit;
  late final EVP_DecryptUpdate_dart _decryptUpdate;
  late final EVP_DecryptFinal_ex_dart _decryptFinal;
  late final EVP_CIPHER_CTX_ctrl_dart _ctxCtrl;

  // Pre-allocated context (reused across operations)
  late final Pointer<EVP_CIPHER_CTX> _ctx;

  // Pre-allocated buffers (sized for typical SRTP packets)
  // Max RTP packet is ~1500 bytes, we allocate 2000 for safety
  static const _maxBufferSize = 2000;
  late final Pointer<Uint8> _keyPtr;
  late final Pointer<Uint8> _ivPtr;
  late final Pointer<Uint8> _inPtr;
  late final Pointer<Uint8> _outPtr;
  late final Pointer<Uint8> _aadPtr;
  late final Pointer<Int32> _outLen;
  late final Pointer<Uint8> _tagPtr;

  bool _initialized = false;
  bool _disposed = false;

  /// Create a new FFI AES-GCM cipher.
  ///
  /// Throws [StateError] if OpenSSL is not available.
  FfiAesGcmCipher() {
    final libPath = findOpenSSL();
    if (libPath == null) {
      throw StateError('OpenSSL not available');
    }

    _lib = DynamicLibrary.open(libPath);

    // Load all functions
    _ctxNew = _lib.lookupFunction<EVP_CIPHER_CTX_new_native,
        EVP_CIPHER_CTX_new_dart>('EVP_CIPHER_CTX_new');
    _ctxFree = _lib.lookupFunction<EVP_CIPHER_CTX_free_native,
        EVP_CIPHER_CTX_free_dart>('EVP_CIPHER_CTX_free');
    _ctxReset = _lib.lookupFunction<EVP_CIPHER_CTX_reset_native,
        EVP_CIPHER_CTX_reset_dart>('EVP_CIPHER_CTX_reset');
    _aes128gcm =
        _lib.lookupFunction<EVP_aes_128_gcm_native, EVP_aes_128_gcm_dart>(
            'EVP_aes_128_gcm');
    _aes256gcm =
        _lib.lookupFunction<EVP_aes_256_gcm_native, EVP_aes_256_gcm_dart>(
            'EVP_aes_256_gcm');
    _encryptInit =
        _lib.lookupFunction<EVP_EncryptInit_ex_native, EVP_EncryptInit_ex_dart>(
            'EVP_EncryptInit_ex');
    _encryptUpdate =
        _lib.lookupFunction<EVP_EncryptUpdate_native, EVP_EncryptUpdate_dart>(
            'EVP_EncryptUpdate');
    _encryptFinal = _lib
        .lookupFunction<EVP_EncryptFinal_ex_native, EVP_EncryptFinal_ex_dart>(
            'EVP_EncryptFinal_ex');
    _decryptInit =
        _lib.lookupFunction<EVP_DecryptInit_ex_native, EVP_DecryptInit_ex_dart>(
            'EVP_DecryptInit_ex');
    _decryptUpdate =
        _lib.lookupFunction<EVP_DecryptUpdate_native, EVP_DecryptUpdate_dart>(
            'EVP_DecryptUpdate');
    _decryptFinal = _lib
        .lookupFunction<EVP_DecryptFinal_ex_native, EVP_DecryptFinal_ex_dart>(
            'EVP_DecryptFinal_ex');
    _ctxCtrl =
        _lib.lookupFunction<EVP_CIPHER_CTX_ctrl_native, EVP_CIPHER_CTX_ctrl_dart>(
            'EVP_CIPHER_CTX_ctrl');

    // Pre-allocate buffers
    _ctx = _ctxNew();
    _keyPtr = calloc<Uint8>(32); // Max key size (AES-256)
    _ivPtr = calloc<Uint8>(12); // GCM nonce size
    _inPtr = calloc<Uint8>(_maxBufferSize);
    _outPtr = calloc<Uint8>(_maxBufferSize);
    _aadPtr = calloc<Uint8>(_maxBufferSize);
    _outLen = calloc<Int32>();
    _tagPtr = calloc<Uint8>(16); // GCM tag size

    _initialized = true;
  }

  Pointer<EVP_CIPHER> _getCipher(int keyLength) {
    if (keyLength == 16) {
      return _aes128gcm();
    } else if (keyLength == 32) {
      return _aes256gcm();
    } else {
      throw ArgumentError('Invalid AES key length: $keyLength');
    }
  }

  void _copyToNative(Pointer<Uint8> dest, Uint8List src) {
    for (var i = 0; i < src.length; i++) {
      dest[i] = src[i];
    }
  }

  @override
  Future<Uint8List> encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    if (_disposed) throw StateError('Cipher has been disposed');
    if (!_initialized) throw StateError('OpenSSL not initialized');
    if (plaintext.length > _maxBufferSize - 16) {
      throw ArgumentError(
          'Plaintext too large: ${plaintext.length} > ${_maxBufferSize - 16}');
    }
    if (aad.length > _maxBufferSize) {
      throw ArgumentError('AAD too large: ${aad.length} > $_maxBufferSize');
    }

    // Reset context for new operation
    _ctxReset(_ctx);

    final cipher = _getCipher(key.length);

    // Copy inputs to native buffers
    _copyToNative(_keyPtr, key);
    _copyToNative(_ivPtr, nonce);
    _copyToNative(_inPtr, plaintext);

    // Initialize encryption
    if (_encryptInit(_ctx, cipher, nullptr, _keyPtr, _ivPtr) != 1) {
      throw StateError('EVP_EncryptInit_ex failed');
    }

    // Set IV length (12 bytes for GCM)
    if (_ctxCtrl(_ctx, _EVP_CTRL_GCM_SET_IVLEN, nonce.length, nullptr) != 1) {
      throw StateError('Failed to set IV length');
    }

    // Process AAD
    if (aad.isNotEmpty) {
      _copyToNative(_aadPtr, aad);
      if (_encryptUpdate(_ctx, nullptr, _outLen, _aadPtr, aad.length) != 1) {
        throw StateError('Failed to process AAD');
      }
    }

    // Encrypt plaintext
    if (_encryptUpdate(_ctx, _outPtr, _outLen, _inPtr, plaintext.length) != 1) {
      throw StateError('EVP_EncryptUpdate failed');
    }
    final encLen = _outLen.value;

    // Finalize
    if (_encryptFinal(_ctx, _outPtr + encLen, _outLen) != 1) {
      throw StateError('EVP_EncryptFinal_ex failed');
    }

    // Get authentication tag
    if (_ctxCtrl(_ctx, _EVP_CTRL_GCM_GET_TAG, 16, _tagPtr.cast()) != 1) {
      throw StateError('Failed to get auth tag');
    }

    // Build result: ciphertext + tag
    final result = Uint8List(encLen + 16);
    for (var i = 0; i < encLen; i++) {
      result[i] = _outPtr[i];
    }
    for (var i = 0; i < 16; i++) {
      result[encLen + i] = _tagPtr[i];
    }

    return result;
  }

  @override
  Future<Uint8List> decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List aad,
  }) async {
    if (_disposed) throw StateError('Cipher has been disposed');
    if (!_initialized) throw StateError('OpenSSL not initialized');
    if (ciphertext.length < 16) {
      throw ArgumentError('Ciphertext too short');
    }
    if (ciphertext.length - 16 > _maxBufferSize) {
      throw ArgumentError('Ciphertext too large');
    }
    if (aad.length > _maxBufferSize) {
      throw ArgumentError('AAD too large');
    }

    // Reset context for new operation
    _ctxReset(_ctx);

    final cipher = _getCipher(key.length);
    final actualCiphertextLen = ciphertext.length - 16;

    // Copy inputs to native buffers
    _copyToNative(_keyPtr, key);
    _copyToNative(_ivPtr, nonce);

    // Copy ciphertext (without tag)
    for (var i = 0; i < actualCiphertextLen; i++) {
      _inPtr[i] = ciphertext[i];
    }

    // Copy tag
    for (var i = 0; i < 16; i++) {
      _tagPtr[i] = ciphertext[actualCiphertextLen + i];
    }

    // Initialize decryption
    if (_decryptInit(_ctx, cipher, nullptr, _keyPtr, _ivPtr) != 1) {
      throw StateError('EVP_DecryptInit_ex failed');
    }

    // Set IV length
    if (_ctxCtrl(_ctx, _EVP_CTRL_GCM_SET_IVLEN, nonce.length, nullptr) != 1) {
      throw StateError('Failed to set IV length');
    }

    // Process AAD
    if (aad.isNotEmpty) {
      _copyToNative(_aadPtr, aad);
      if (_decryptUpdate(_ctx, nullptr, _outLen, _aadPtr, aad.length) != 1) {
        throw StateError('Failed to process AAD');
      }
    }

    // Decrypt ciphertext
    if (_decryptUpdate(_ctx, _outPtr, _outLen, _inPtr, actualCiphertextLen) !=
        1) {
      throw StateError('EVP_DecryptUpdate failed');
    }
    final decLen = _outLen.value;

    // Set expected tag for verification
    if (_ctxCtrl(_ctx, _EVP_CTRL_GCM_SET_TAG, 16, _tagPtr.cast()) != 1) {
      throw StateError('Failed to set auth tag');
    }

    // Finalize and verify tag
    if (_decryptFinal(_ctx, _outPtr + decLen, _outLen) != 1) {
      throw StateError('Authentication failed');
    }

    // Build result
    final result = Uint8List(decLen);
    for (var i = 0; i < decLen; i++) {
      result[i] = _outPtr[i];
    }

    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    if (_initialized) {
      _ctxFree(_ctx);
      calloc.free(_keyPtr);
      calloc.free(_ivPtr);
      calloc.free(_inPtr);
      calloc.free(_outPtr);
      calloc.free(_aadPtr);
      calloc.free(_outLen);
      calloc.free(_tagPtr);
    }
  }
}
