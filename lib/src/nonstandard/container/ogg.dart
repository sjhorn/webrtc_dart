/// OGG Container Parser
///
/// Parses OGG container format for extracting Opus audio packets.
/// OGG is a free, open container format maintained by Xiph.Org Foundation.
///
/// Ported from werift-webrtc ogg/parser.ts
library;

import 'dart:typed_data';

/// Represents a parsed OGG page
///
/// An OGG bitstream consists of a sequence of pages, each containing
/// a portion of the logical bitstream data.
class OggPage {
  /// Granule position - absolute position in stream for seeking
  ///
  /// For Opus, this represents the PCM sample count at 48kHz.
  final int granulePosition;

  /// Segment data extracted from this page
  final List<Uint8List> segments;

  /// Segment table containing length of each segment (0-255 bytes each)
  final List<int> segmentTable;

  OggPage({
    required this.granulePosition,
    required this.segments,
    required this.segmentTable,
  });
}

/// OGG container parser
///
/// Parses OGG pages from binary data, extracting segments (packets).
/// Supports incremental parsing across buffer boundaries.
///
/// OGG Page Format (27+ bytes header):
/// - Bytes 0-3: Magic "OggS"
/// - Byte 4: Version (0)
/// - Byte 5: Header type flags
/// - Bytes 6-13: Granule position (64-bit LE)
/// - Bytes 14-17: Bitstream serial number (32-bit LE)
/// - Bytes 18-21: Page sequence number (32-bit LE)
/// - Bytes 22-25: CRC checksum (32-bit LE)
/// - Byte 26: Number of segments (1-255)
/// - Bytes 27+: Segment table (variable length)
/// - Segment data follows immediately after
class OggParser {
  /// Parsed pages accumulated during parsing
  final List<OggPage> pages = [];

  /// OGG magic bytes
  static const String _magic = 'OggS';

  /// Validate that all segments in a page match their declared lengths
  ({bool ok, int? invalid}) _checkSegments(OggPage? page) {
    if (page == null) {
      return (ok: true, invalid: null);
    }
    for (var i = 0; i < page.segmentTable.length; i++) {
      if (i >= page.segments.length) {
        return (ok: false, invalid: i);
      }
      final segment = page.segments[i];
      final tableLength = page.segmentTable[i];
      if (segment.length != tableLength) {
        return (ok: false, invalid: i);
      }
    }
    return (ok: true, invalid: null);
  }

  /// Export fully parsed segments from completed pages
  ///
  /// Returns all segments from pages that have been completely parsed.
  /// Removes exported pages from the internal buffer.
  List<Uint8List> exportSegments() {
    var i = 0;
    final exportedPages = <OggPage>[];

    for (; i < pages.length; i++) {
      final page = pages[i];
      final result = _checkSegments(page);
      if (result.invalid != null) {
        break;
      }
      exportedPages.add(page);
    }

    // Remove exported pages, keep remaining
    if (i > 0) {
      pages.removeRange(0, i);
    }

    // Flatten segments from all exported pages
    return exportedPages.expand((page) => page.segments).toList();
  }

  /// Parse OGG data from a buffer
  ///
  /// Incrementally parses OGG pages from [buf]. Can handle data
  /// split across multiple buffers by calling read() repeatedly.
  ///
  /// Returns this parser for method chaining.
  OggParser read(Uint8List buf) {
    var index = 0;

    while (index < buf.length) {
      try {
        // Check if last page is incomplete
        final lastPage = pages.isNotEmpty ? pages.last : null;
        final checkResult = _checkSegments(lastPage);

        if (lastPage != null && checkResult.invalid != null) {
          // Continue filling incomplete page
          for (var i = checkResult.invalid!;
              i < lastPage.segmentTable.length;
              i++) {
            final existingLength =
                i < lastPage.segments.length ? lastPage.segments[i].length : 0;
            final diff = lastPage.segmentTable[i] - existingLength;

            if (index + diff > buf.length) {
              // Not enough data yet
              final available = buf.length - index;
              if (i < lastPage.segments.length) {
                // Append to existing segment
                final combined =
                    Uint8List(lastPage.segments[i].length + available);
                combined.setAll(0, lastPage.segments[i]);
                combined.setAll(
                    lastPage.segments[i].length, buf.sublist(index));
                lastPage.segments[i] = combined;
              } else {
                // New partial segment
                lastPage.segments.add(buf.sublist(index));
              }
              return this;
            }

            if (i < lastPage.segments.length) {
              // Append remaining data to segment
              final combined = Uint8List(lastPage.segments[i].length + diff);
              combined.setAll(0, lastPage.segments[i]);
              combined.setAll(lastPage.segments[i].length,
                  buf.sublist(index, index + diff));
              lastPage.segments[i] = combined;
            } else {
              // Add new complete segment
              lastPage.segments
                  .add(Uint8List.fromList(buf.sublist(index, index + diff)));
            }
            index += diff;
          }
        } else {
          // Parse new page header
          if (index + 27 > buf.length) {
            // Not enough data for header
            break;
          }

          // Check magic bytes "OggS"
          final magic = String.fromCharCodes(buf.sublist(index, index + 4));
          if (magic != _magic) {
            break;
          }
          index += 4;

          // Skip version (1 byte)
          index += 1;

          // Header type (1 byte) - contains flags for continuation, BOS, EOS
          // final headerType = buf[index];
          index += 1;

          // Granule position (8 bytes, little-endian signed 64-bit)
          final granulePosition = _readInt64LE(buf, index);
          index += 8;

          // Bitstream serial number (4 bytes, little-endian)
          // final bitstreamSerialNumber = _readUint32LE(buf, index);
          index += 4;

          // Page sequence number (4 bytes, little-endian)
          // final pageSequenceNumber = _readUint32LE(buf, index);
          index += 4;

          // Page checksum (4 bytes, little-endian)
          // final pageChecksum = _readUint32LE(buf, index);
          index += 4;

          // Number of segments (1 byte)
          final pageSegments = buf[index];
          index += 1;

          // Check if we have enough data for segment table
          if (index + pageSegments > buf.length) {
            // Rewind to start of page and wait for more data
            index -= 27;
            break;
          }

          // Read segment table
          final segmentTable = List<int>.generate(
            pageSegments,
            (i) => buf[index + i],
          );
          index += pageSegments;

          // Read segment data
          final segments = <Uint8List>[];
          for (var i = 0; i < pageSegments; i++) {
            final segmentLength = segmentTable[i];
            if (index + segmentLength > buf.length) {
              // Partial segment - add what we have
              segments.add(Uint8List.fromList(buf.sublist(index)));
              index = buf.length;
              break;
            }
            segments.add(
                Uint8List.fromList(buf.sublist(index, index + segmentLength)));
            index += segmentLength;
          }

          pages.add(OggPage(
            granulePosition: granulePosition,
            segments: segments,
            segmentTable: segmentTable,
          ));
        }
      } catch (e) {
        // Parsing error - stop and return what we have
        break;
      }
    }

    return this;
  }

  /// Read 64-bit signed little-endian integer
  int _readInt64LE(Uint8List buf, int offset) {
    final bytes = ByteData.sublistView(buf, offset, offset + 8);
    return bytes.getInt64(0, Endian.little);
  }

  /// Clear all parsed pages
  void clear() {
    pages.clear();
  }
}

/// OGG Opus packet extractor
///
/// Extracts Opus audio packets from OGG container, handling:
/// - OpusHead (ID header) - codec configuration
/// - OpusTags (comment header) - metadata
/// - Audio packets - actual audio data
class OggOpusExtractor {
  final OggParser _parser = OggParser();

  /// Whether the ID header (OpusHead) has been parsed
  bool _hasIdHeader = false;

  /// Whether the comment header (OpusTags) has been parsed
  bool _hasCommentHeader = false;

  /// Channel count from OpusHead
  int? channelCount;

  /// Pre-skip samples from OpusHead
  int? preSkip;

  /// Original sample rate from OpusHead
  int? originalSampleRate;

  /// Output gain from OpusHead
  int? outputGain;

  /// Feed OGG data to the extractor
  ///
  /// Returns a list of Opus audio packets extracted from the data.
  /// The first two packets (ID header and comment header) are consumed
  /// internally and not returned.
  List<Uint8List> feed(Uint8List data) {
    _parser.read(data);
    final segments = _parser.exportSegments();
    final audioPackets = <Uint8List>[];

    for (final segment in segments) {
      if (!_hasIdHeader) {
        // First packet should be OpusHead
        if (_parseOpusHead(segment)) {
          _hasIdHeader = true;
        }
      } else if (!_hasCommentHeader) {
        // Second packet should be OpusTags
        if (_isOpusTags(segment)) {
          _hasCommentHeader = true;
        }
      } else {
        // Audio packet
        audioPackets.add(segment);
      }
    }

    return audioPackets;
  }

  /// Parse OpusHead ID header
  ///
  /// Format:
  /// - Bytes 0-7: "OpusHead"
  /// - Byte 8: Version (1)
  /// - Byte 9: Channel count
  /// - Bytes 10-11: Pre-skip (LE)
  /// - Bytes 12-15: Input sample rate (LE)
  /// - Bytes 16-17: Output gain (LE)
  /// - Byte 18: Channel mapping family
  bool _parseOpusHead(Uint8List data) {
    if (data.length < 19) return false;

    final magic = String.fromCharCodes(data.sublist(0, 8));
    if (magic != 'OpusHead') return false;

    final version = data[8];
    if (version != 1) return false;

    channelCount = data[9];

    final bytes = ByteData.sublistView(data);
    preSkip = bytes.getUint16(10, Endian.little);
    originalSampleRate = bytes.getUint32(12, Endian.little);
    outputGain = bytes.getInt16(16, Endian.little);

    return true;
  }

  /// Check if packet is OpusTags comment header
  bool _isOpusTags(Uint8List data) {
    if (data.length < 8) return false;
    final magic = String.fromCharCodes(data.sublist(0, 8));
    return magic == 'OpusTags';
  }

  /// Reset extractor state
  void reset() {
    _parser.clear();
    _hasIdHeader = false;
    _hasCommentHeader = false;
    channelCount = null;
    preSkip = null;
    originalSampleRate = null;
    outputGain = null;
  }
}
