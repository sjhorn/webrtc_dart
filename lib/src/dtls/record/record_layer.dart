import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/header.dart';
import 'package:webrtc_dart/src/dtls/record/record.dart';

final _log = WebRtcLogging.dtlsRecord;

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

  /// Process received records
  Future<List<ProcessedRecord>> processRecords(Uint8List data) async {
    final records = DtlsRecord.parseMultiple(data);
    final processed = <ProcessedRecord>[];

    for (final record in records) {
      try {
        // Check epoch
        if (record.epoch > dtlsContext.readEpoch) {
          // Future epoch - might be retransmission, buffer it
          _log.fine(
              'Skipping record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch})');
          continue;
        }

        if (record.epoch < dtlsContext.readEpoch) {
          // Old epoch - ignore
          _log.fine(
              'Ignoring old record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch})');
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
          _log.fine(
              'Buffering future-epoch record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch}), type=${record.contentType}');
          futureEpochBuffer.add(record.serialize());
          continue;
        }

        if (record.epoch < dtlsContext.readEpoch) {
          // Old epoch - ignore
          _log.fine(
              'Ignoring old record with epoch ${record.epoch} (readEpoch=${dtlsContext.readEpoch})');
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
        _log.fine('Error processing record: $e');
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
