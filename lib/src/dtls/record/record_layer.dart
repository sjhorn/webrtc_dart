import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/header.dart';
import 'package:webrtc_dart/src/dtls/record/record.dart';

/// DTLS Record Layer
/// Handles record framing, encryption, and decryption
class DtlsRecordLayer {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;

  DtlsRecordLayer({
    required this.dtlsContext,
    required this.cipherContext,
  });

  /// Create a record with the given content
  DtlsRecord createRecord({
    required ContentType contentType,
    required Uint8List data,
  }) {
    final epoch = dtlsContext.writeEpoch;
    final sequenceNumber = dtlsContext.getNextWriteSequence();

    return DtlsRecord(
      contentType: contentType,
      version: ProtocolVersion.dtls12,
      epoch: epoch,
      sequenceNumber: sequenceNumber,
      fragment: data,
    );
  }

  /// Wrap handshake message in a record
  DtlsRecord wrapHandshake(Uint8List handshakeData) {
    return createRecord(
      contentType: ContentType.handshake,
      data: handshakeData,
    );
  }

  /// Wrap alert message in a record
  DtlsRecord wrapAlert(Alert alert) {
    return createRecord(
      contentType: ContentType.alert,
      data: alert.serialize(),
    );
  }

  /// Wrap application data in a record
  DtlsRecord wrapApplicationData(Uint8List data) {
    return createRecord(
      contentType: ContentType.applicationData,
      data: data,
    );
  }

  /// Encrypt a record (after ChangeCipherSpec)
  Future<Uint8List> encryptRecord(DtlsRecord record) async {
    // If no cipher is active OR record is epoch 0, send plaintext
    if (!cipherContext.isEncryptionReady || record.epoch == 0) {
      return record.serialize();
    }

    // Get the appropriate cipher
    final cipher = cipherContext.isClient
        ? cipherContext.clientWriteCipher
        : cipherContext.serverWriteCipher;

    if (cipher == null) {
      throw StateError('Encryption cipher not initialized');
    }

    // Create record header for cipher
    final header = RecordHeader(
      contentType: record.contentType.value,
      protocolVersion: record.version,
      epoch: record.epoch,
      sequenceNumber: record.sequenceNumber,
      contentLen: record.fragment.length,
    );

    // Encrypt using cipher
    final ciphertext = await cipher.encrypt(record.fragment, header);

    // Create encrypted record with ciphertext
    final encryptedRecord = DtlsRecord(
      contentType: record.contentType,
      version: record.version,
      epoch: record.epoch,
      sequenceNumber: record.sequenceNumber,
      fragment: ciphertext,
    );

    return encryptedRecord.serialize();
  }

  /// Decrypt a record
  Future<Uint8List> decryptRecord(DtlsRecord record) async {
    // If cipher not active yet OR record is from epoch 0, return plaintext
    if (!cipherContext.isDecryptionReady || record.epoch == 0) {
      return record.fragment;
    }

    // Get the appropriate cipher
    final cipher = cipherContext.isClient
        ? cipherContext.serverWriteCipher
        : cipherContext.clientWriteCipher;

    if (cipher == null) {
      throw StateError('Decryption cipher not initialized');
    }

    // Create record header for cipher
    // Note: For decryption, the contentLen is the ciphertext length (including explicit nonce and tag)
    final header = RecordHeader(
      contentType: record.contentType.value,
      protocolVersion: record.version,
      epoch: record.epoch,
      sequenceNumber: record.sequenceNumber,
      contentLen: record.fragment.length,
    );

    // Decrypt using cipher
    try {
      final plaintext = await cipher.decrypt(record.fragment, header);
      return plaintext;
    } catch (e) {
      throw StateError('Decryption failed: $e');
    }
  }

  /// Construct Additional Authenticated Data for AEAD
  Uint8List _constructAAD({
    required int epoch,
    required int sequenceNumber,
    required ContentType contentType,
    required ProtocolVersion version,
    required int length,
  }) {
    // AAD = seq_num + type + version + length
    // RFC 5246 Section 6.2.3.3
    final buffer = ByteData(13);

    // Epoch (2 bytes)
    buffer.setUint16(0, epoch);

    // Sequence number (6 bytes)
    buffer.setUint16(2, (sequenceNumber >> 32) & 0xFFFF);
    buffer.setUint32(4, sequenceNumber & 0xFFFFFFFF);

    // Content type (1 byte)
    buffer.setUint8(8, contentType.value);

    // Version (2 bytes)
    buffer.setUint8(9, version.major);
    buffer.setUint8(10, version.minor);

    // Length (2 bytes) - plaintext length
    buffer.setUint16(11, length);

    return buffer.buffer.asUint8List();
  }

  /// Construct nonce for AEAD cipher
  Uint8List _constructNonce(int epoch, int sequenceNumber, bool isClient) {
    // Nonce = implicit_nonce (4 bytes) XOR (epoch + seq_num)
    // Get implicit nonce (fixed part)
    final implicitNonce = isClient
        ? cipherContext.clientWriteIV
        : cipherContext.serverWriteIV;

    if (implicitNonce == null || implicitNonce.length != 4) {
      throw StateError('Invalid implicit nonce');
    }

    // Construct explicit nonce (epoch + seq_num as 8 bytes)
    final explicitNonce = ByteData(8);
    explicitNonce.setUint16(0, epoch);
    explicitNonce.setUint16(2, (sequenceNumber >> 32) & 0xFFFF);
    explicitNonce.setUint32(4, sequenceNumber & 0xFFFFFFFF);

    // XOR the last 8 bytes
    final nonce = Uint8List(12);

    // First 4 bytes are the implicit nonce
    nonce.setRange(0, 4, implicitNonce);

    // Last 8 bytes are explicit nonce (for now, just copy - XOR happens in cipher)
    nonce.setRange(4, 12, explicitNonce.buffer.asUint8List());

    return nonce;
  }

  /// Process received records
  Future<List<ProcessedRecord>> processRecords(Uint8List data) async {
    final records = DtlsRecord.parseMultiple(data);
    final processed = <ProcessedRecord>[];

    for (final record in records) {
      try {
        // Check epoch
        if (record.epoch > dtlsContext.readEpoch) {
          // Future epoch - might be retransmission, buffer it
          print('[RECORD] Skipping record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch})');
          continue;
        }

        if (record.epoch < dtlsContext.readEpoch) {
          // Old epoch - ignore
          print('[RECORD] Ignoring old record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch})');
          continue;
        }

        // Decrypt if needed
        final plaintext = await decryptRecord(record);

        processed.add(ProcessedRecord(
          contentType: record.contentType,
          data: plaintext,
          epoch: record.epoch,
          sequenceNumber: record.sequenceNumber,
        ));
      } catch (e) {
        // Record processing failed - continue with others
        continue;
      }
    }

    return processed;
  }

  /// Process received records with future-epoch buffering
  /// Future-epoch records are added to the buffer instead of being skipped
  /// This allows them to be reprocessed after ChangeCipherSpec
  Future<List<ProcessedRecord>> processRecordsWithFutureEpoch(
    Uint8List data,
    List<Uint8List> futureEpochBuffer,
  ) async {
    final records = DtlsRecord.parseMultiple(data);
    final processed = <ProcessedRecord>[];

    for (final record in records) {
      try {
        // Check epoch
        if (record.epoch > dtlsContext.readEpoch) {
          // Future epoch - buffer the raw record for later processing
          print('[RECORD] Buffering future-epoch record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch}), type=${record.contentType}');
          futureEpochBuffer.add(record.serialize());
          continue;
        }

        if (record.epoch < dtlsContext.readEpoch) {
          // Old epoch - ignore
          print('[RECORD] Ignoring old record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch})');
          continue;
        }

        // Decrypt if needed
        final plaintext = await decryptRecord(record);

        processed.add(ProcessedRecord(
          contentType: record.contentType,
          data: plaintext,
          epoch: record.epoch,
          sequenceNumber: record.sequenceNumber,
        ));
      } catch (e) {
        // Record processing failed - continue with others
        print('[RECORD] Error processing record: $e');
        continue;
      }
    }

    return processed;
  }
}

/// Processed record after decryption
class ProcessedRecord {
  final ContentType contentType;
  final Uint8List data;
  final int epoch;
  final int sequenceNumber;

  ProcessedRecord({
    required this.contentType,
    required this.data,
    required this.epoch,
    required this.sequenceNumber,
  });
}
