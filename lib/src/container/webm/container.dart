import 'dart:math';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/crypto.dart';

import 'ebml/ebml.dart';
import 'ebml/id.dart';

/// Supported codecs for WebM container
enum WebmCodec {
  vp8('VP8'),
  vp9('VP9'),
  av1('AV1'),
  h264('MPEG4/ISO/AVC'),
  opus('OPUS');

  final String name;
  const WebmCodec(this.name);
}

/// Track kind for WebM container
enum TrackKind {
  video(1),
  audio(2);

  final int value;
  const TrackKind(this.value);
}

/// Track configuration for WebM container
class WebmTrack {
  final int trackNumber;
  final TrackKind kind;
  final WebmCodec codec;
  final int? width;
  final int? height;
  final double? roll;

  WebmTrack({
    required this.trackNumber,
    required this.kind,
    required this.codec,
    this.width,
    this.height,
    this.roll,
  });
}

/// AES encryption algorithm value for WebM/Matroska
class ContentEncAlgorithm {
  /// AES encryption (value 5)
  static const int aes = 5;
}

/// AES cipher mode values for WebM/Matroska
class AesCipherMode {
  /// CTR (Counter) mode (value 1)
  static const int ctr = 1;
}

/// WebM container builder
///
/// Implements WebM container format for recording audio/video.
/// WebM is a subset of Matroska, using EBML encoding.
///
/// Supports optional AES-128-CTR encryption per WebM/Matroska specification.
///
/// Usage:
/// ```dart
/// final container = WebmContainer([
///   WebmTrack(trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8, width: 640, height: 480),
///   WebmTrack(trackNumber: 2, kind: TrackKind.audio, codec: WebmCodec.opus),
/// ]);
///
/// // Get EBML header (write once at start)
/// final header = container.ebmlHeader;
///
/// // Get segment with track info
/// final segment = container.createSegment();
///
/// // Create clusters with media frames
/// final cluster = container.createCluster(0); // timecode in ms
/// final block = container.createSimpleBlock(frame, true, 1, 0);
/// ```
///
/// For encrypted WebM:
/// ```dart
/// final encryptionKey = randomBytes(16); // 128-bit key
/// final container = WebmContainer(tracks, encryptionKey: encryptionKey);
/// ```
class WebmContainer {
  /// Tracks configured for this container
  final List<WebmTrack> tracks;

  /// Optional 128-bit AES encryption key
  final Uint8List? encryptionKey;

  /// Random 128-bit key ID (generated per container)
  late final Uint8List? _encryptionKeyId;

  /// Per-track IV counters (64-bit counter stored as two 32-bit values)
  final Map<int, List<int>> _trackIvCounters = {};

  /// TimecodeScale: 1,000,000 ns = 1 ms
  static const int timecodeScaleNs = 1000000;

  WebmContainer(this.tracks, {this.encryptionKey}) {
    if (encryptionKey != null) {
      if (encryptionKey!.length != 16) {
        throw ArgumentError('Encryption key must be exactly 16 bytes');
      }
      // Generate random key ID
      _encryptionKeyId = randomBytes(16);

      // Initialize IV counters for each track with random values
      final random = Random.secure();
      for (final track in tracks) {
        // 64-bit counter stored as [high32, low32]
        _trackIvCounters[track.trackNumber] = [
          random.nextInt(0xFFFFFFFF),
          random.nextInt(0xFFFFFFFF),
        ];
      }
    } else {
      _encryptionKeyId = null;
    }
  }

  /// Check if encryption is enabled
  bool get isEncrypted => encryptionKey != null;

  /// EBML header - write this at the start of the file
  Uint8List get ebmlHeader => ebmlBuild(
        ebmlElement(EbmlId.ebml, [
          ebmlElement(EbmlId.ebmlVersion, ebmlNumber(1)),
          ebmlElement(EbmlId.ebmlReadVersion, ebmlNumber(1)),
          ebmlElement(EbmlId.ebmlMaxIdLength, ebmlNumber(4)),
          ebmlElement(EbmlId.ebmlMaxSizeLength, ebmlNumber(8)),
          ebmlElement(EbmlId.docType, ebmlString('webm')),
          ebmlElement(EbmlId.docTypeVersion, ebmlNumber(2)),
          ebmlElement(EbmlId.docTypeReadVersion, ebmlNumber(2)),
        ]),
      );

  /// Create a track entry element
  EbmlData _createTrackEntry(WebmTrack track) {
    final trackElements = <EbmlData>[];

    if (track.kind == TrackKind.video) {
      final width = track.width ?? 640;
      final height = track.height ?? 360;

      final videoElements = <EbmlData>[
        ebmlElement(EbmlId.pixelWidth, ebmlNumber(width)),
        ebmlElement(EbmlId.pixelHeight, ebmlNumber(height)),
      ];

      if (track.roll != null) {
        videoElements.add(
          ebmlElement(EbmlId.projection, [
            ebmlElement(EbmlId.projectionType, ebmlNumber(0)),
            ebmlElement(EbmlId.projectionPoseRoll, ebmlFloat(track.roll!)),
          ]),
        );
      }

      trackElements.add(ebmlElement(EbmlId.video, videoElements));
    } else {
      // Audio track
      trackElements.add(
        ebmlElement(EbmlId.audio, [
          ebmlElement(EbmlId.samplingFrequency, ebmlFloat(48000.0)),
          ebmlElement(EbmlId.channels, ebmlNumber(2)),
        ]),
      );

      // Opus codec private data (OpusHead)
      if (track.codec == WebmCodec.opus) {
        trackElements.add(
          ebmlElement(EbmlId.codecPrivate, ebmlBytes(_createOpusPrivate())),
        );
      }
    }

    final codecId = track.kind == TrackKind.video
        ? 'V_${track.codec.name}'
        : 'A_${track.codec.name}';

    // Add encryption metadata if encryption is enabled
    if (isEncrypted) {
      trackElements.add(_createContentEncodings());
    }

    return ebmlElement(EbmlId.trackEntry, [
      ebmlElement(EbmlId.trackNumber, ebmlNumber(track.trackNumber)),
      ebmlElement(EbmlId.trackUid, ebmlNumber(track.trackNumber)),
      ebmlElement(EbmlId.codecName, ebmlString(track.codec.name)),
      ebmlElement(EbmlId.trackType, ebmlNumber(track.kind.value)),
      ebmlElement(EbmlId.codecId, ebmlString(codecId)),
      ...trackElements,
    ]);
  }

  /// Create ContentEncodings element for encrypted tracks
  EbmlData _createContentEncodings() {
    return ebmlElement(EbmlId.contentEncodings, [
      ebmlElement(EbmlId.contentEncoding, [
        ebmlElement(EbmlId.contentEncodingOrder, ebmlNumber(0)),
        ebmlElement(EbmlId.contentEncodingScope, ebmlNumber(1)), // 1 = All frame contents
        ebmlElement(EbmlId.contentEncodingType, ebmlNumber(1)), // 1 = Encryption
        ebmlElement(EbmlId.contentEncryption, [
          ebmlElement(EbmlId.contentEncAlgo, ebmlNumber(ContentEncAlgorithm.aes)),
          ebmlElement(EbmlId.contentEncKeyId, ebmlBytes(_encryptionKeyId!)),
          ebmlElement(EbmlId.contentEncAesSettings, [
            ebmlElement(EbmlId.aesSettingsCipherMode, ebmlNumber(AesCipherMode.ctr)),
          ]),
        ]),
      ]),
    ]);
  }

  /// Create Opus codec private data (OpusHead structure)
  /// See RFC 7845
  Uint8List _createOpusPrivate() {
    final buf = Uint8List(19);
    // "OpusHead" magic signature
    buf.setAll(0, [0x4f, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]);
    buf[8] = 1; // Version
    buf[9] = 2; // Channel count
    // Pre-skip (little-endian 16-bit)
    buf[10] = 0x00;
    buf[11] = 0x00;
    // Sample rate 48000 (little-endian 32-bit)
    buf[12] = 0x80;
    buf[13] = 0xbb;
    buf[14] = 0x00;
    buf[15] = 0x00;
    // Output gain (little-endian 16-bit)
    buf[16] = 0x00;
    buf[17] = 0x00;
    // Channel mapping family
    buf[18] = 0;
    return buf;
  }

  /// Create segment element with track info
  ///
  /// [duration] is optional duration in milliseconds
  Uint8List createSegment({double? duration}) {
    final infoElements = <EbmlData>[
      ebmlElement(EbmlId.timecodeScale, ebmlNumber(timecodeScaleNs)),
      ebmlElement(EbmlId.muxingApp, ebmlString('webrtc-dart')),
      ebmlElement(EbmlId.writingApp, ebmlString('webrtc-dart')),
    ];

    if (duration != null) {
      infoElements.add(ebmlElement(EbmlId.duration, ebmlFloat(duration)));
    }

    final trackEntries = tracks.map(_createTrackEntry).toList();

    return ebmlBuild(
      ebmlUnknownSizeElement(EbmlId.segment, [
        ebmlElement(EbmlId.seekHead, <EbmlData>[]),
        ebmlElement(EbmlId.info, infoElements),
        ebmlElement(EbmlId.tracks, trackEntries),
      ]),
    );
  }

  /// Create a duration element (for updating duration after recording)
  Uint8List createDuration(double durationMs) {
    return ebmlBuild(ebmlElement(EbmlId.duration, ebmlFloat(durationMs)));
  }

  /// Create a cluster element
  ///
  /// [timecode] is the cluster timestamp in milliseconds
  Uint8List createCluster(int timecode) {
    return ebmlBuild(
      ebmlUnknownSizeElement(EbmlId.cluster, [
        ebmlElement(EbmlId.timecode, ebmlNumber(timecode)),
      ]),
    );
  }

  /// Create a SimpleBlock element for a media frame
  ///
  /// [frame] is the raw frame data
  /// [isKeyframe] indicates if this is a keyframe
  /// [trackNumber] is the track number (1-based)
  /// [relativeTimestamp] is the timestamp relative to the cluster in milliseconds
  ///
  /// For unencrypted containers, this is synchronous.
  /// For encrypted containers, use [createSimpleBlockAsync] instead.
  Uint8List createSimpleBlock(
    Uint8List frame,
    bool isKeyframe,
    int trackNumber,
    int relativeTimestamp,
  ) {
    if (isEncrypted) {
      throw StateError(
          'Use createSimpleBlockAsync for encrypted containers');
    }
    return _buildSimpleBlock(frame, isKeyframe, trackNumber, relativeTimestamp);
  }

  /// Create a SimpleBlock element for a media frame (async version for encryption)
  ///
  /// [frame] is the raw frame data
  /// [isKeyframe] indicates if this is a keyframe
  /// [trackNumber] is the track number (1-based)
  /// [relativeTimestamp] is the timestamp relative to the cluster in milliseconds
  Future<Uint8List> createSimpleBlockAsync(
    Uint8List frame,
    bool isKeyframe,
    int trackNumber,
    int relativeTimestamp,
  ) async {
    if (!isEncrypted) {
      return _buildSimpleBlock(frame, isKeyframe, trackNumber, relativeTimestamp);
    }

    // Encrypt the frame using AES-128-CTR
    final encryptedFrame = await _encryptFrame(frame, trackNumber);
    return _buildSimpleBlock(encryptedFrame, isKeyframe, trackNumber, relativeTimestamp);
  }

  /// Encrypt a frame using AES-128-CTR
  Future<Uint8List> _encryptFrame(Uint8List frame, int trackNumber) async {
    // Get the IV counter for this track
    final counter = _trackIvCounters[trackNumber]!;

    // Build 16-byte IV from counter (8 bytes counter + 8 bytes padding)
    final iv = Uint8List(16);
    final ivBuffer = ByteData.sublistView(iv);
    ivBuffer.setUint32(0, counter[0]); // High 32 bits
    ivBuffer.setUint32(4, counter[1]); // Low 32 bits
    // Remaining 8 bytes are zero-padded

    // Encrypt the frame
    final encrypted = await aesCtrEncrypt(
      key: encryptionKey!,
      iv: iv,
      plaintext: frame,
    );

    // Increment the counter
    counter[1]++;
    if (counter[1] == 0) {
      counter[0]++; // Overflow to high bits
    }

    // WebM encryption format:
    // Signal byte (1 byte): bits 0-2 = reserved, bit 3 = partitioning, bit 7 = encrypted
    // IV (8 bytes): first 8 bytes of the 16-byte IV
    // Encrypted data
    final signalByte = 0x01; // Bit 0 set = encrypted
    final result = Uint8List(1 + 8 + encrypted.length);
    result[0] = signalByte;
    result.setRange(1, 9, iv.sublist(0, 8)); // First 8 bytes of IV
    result.setRange(9, result.length, encrypted);

    return result;
  }

  /// Build a SimpleBlock element (internal, without encryption)
  Uint8List _buildSimpleBlock(
    Uint8List frame,
    bool isKeyframe,
    int trackNumber,
    int relativeTimestamp,
  ) {
    // SimpleBlock element ID
    final elementId = Uint8List.fromList([0xa3]);

    // Track number as VINT
    final trackVint = vintEncode(
        numberToByteArray(trackNumber, getEbmlByteLength(trackNumber)));

    // Relative timestamp as signed 16-bit big-endian
    final timestampBytes = Uint8List(2);
    ByteData.view(timestampBytes.buffer).setInt16(0, relativeTimestamp);

    // Flags byte
    // Bit 0: Keyframe
    // Bits 1-3: Reserved
    // Bit 4: Invisible
    // Bits 5-6: Lacing (00 = no lacing)
    // Bit 7: Discardable
    final flags = isKeyframe ? 0x80 : 0x00;

    // Block data: trackNumber (vint) + timestamp (2 bytes) + flags (1 byte) + frame
    final blockData = Uint8List(trackVint.length + 2 + 1 + frame.length);
    var offset = 0;
    blockData.setAll(offset, trackVint);
    offset += trackVint.length;
    blockData.setAll(offset, timestampBytes);
    offset += 2;
    blockData[offset] = flags;
    offset += 1;
    blockData.setAll(offset, frame);

    // Content size as VINT
    final contentSize = vintEncode(numberToByteArray(
        blockData.length, getEbmlByteLength(blockData.length)));

    // Full SimpleBlock: elementId + contentSize + blockData
    final result =
        Uint8List(elementId.length + contentSize.length + blockData.length);
    offset = 0;
    result.setAll(offset, elementId);
    offset += elementId.length;
    result.setAll(offset, contentSize);
    offset += contentSize.length;
    result.setAll(offset, blockData);

    return result;
  }

  /// Create a CuePoint element for seeking
  ///
  /// [relativeTimestamp] is the timestamp in milliseconds
  /// [trackNumber] is the track number
  /// [clusterPosition] is the byte position of the cluster from segment start
  /// [blockNumber] is the block number within the cluster (1-based)
  EbmlData createCuePoint(
    int relativeTimestamp,
    int trackNumber,
    int clusterPosition,
    int blockNumber,
  ) {
    return ebmlElement(EbmlId.cuePoint, [
      ebmlElement(EbmlId.cueTime, ebmlNumber(relativeTimestamp)),
      ebmlElement(EbmlId.cueTrackPositions, [
        ebmlElement(EbmlId.cueTrack, ebmlNumber(trackNumber)),
        ebmlElement(EbmlId.cueClusterPosition, ebmlNumber(clusterPosition)),
        ebmlElement(EbmlId.cueBlockNumber, ebmlNumber(blockNumber)),
      ]),
    ]);
  }

  /// Create a Cues element containing all cue points
  Uint8List createCues(List<EbmlData> cuePoints) {
    return ebmlBuild(ebmlElement(EbmlId.cues, cuePoints));
  }
}
