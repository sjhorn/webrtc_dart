/// MP4 Container - Fragmented MP4 (fMP4) container support
///
/// Implements ISO Base Media File Format (ISO/IEC 14496-12)
/// for fragmented MP4 output. Supports H.264/AVC and Opus codecs.
///
/// Ported from werift-webrtc mp4/container.ts
library;

import 'dart:async';
import 'dart:typed_data';

/// Supported MP4 codecs
enum Mp4Codec {
  avc1, // H.264/AVC
  opus, // Opus audio
  hev1, // H.265/HEVC (future)
}

/// MP4 data output type
enum Mp4DataType {
  init, // Initialization segment (ftyp + moov)
  delta, // Delta/P-frame
  key, // Key/I-frame
}

/// MP4 data chunk
class Mp4Data {
  /// Data type
  final Mp4DataType type;

  /// Timestamp in microseconds
  final int timestamp;

  /// Duration in microseconds
  final int duration;

  /// Raw data
  final Uint8List data;

  /// Track kind
  final String kind; // 'audio' or 'video'

  Mp4Data({
    required this.type,
    required this.timestamp,
    required this.duration,
    required this.data,
    required this.kind,
  });
}

/// Audio decoder configuration
class AudioDecoderConfig {
  final String codec;
  final Uint8List? description;
  final int numberOfChannels;
  final int sampleRate;

  AudioDecoderConfig({
    required this.codec,
    this.description,
    required this.numberOfChannels,
    required this.sampleRate,
  });
}

/// Video decoder configuration
class VideoDecoderConfig {
  final String codec;
  final int? codedWidth;
  final int? codedHeight;
  final Uint8List? description;
  final int? displayAspectWidth;
  final int? displayAspectHeight;

  VideoDecoderConfig({
    required this.codec,
    this.codedWidth,
    this.codedHeight,
    this.description,
    this.displayAspectWidth,
    this.displayAspectHeight,
  });
}

/// Encoded chunk (audio or video)
class EncodedChunk {
  final int byteLength;
  final int? duration;
  final int timestamp;
  final String type; // 'key' or 'delta'
  final Uint8List data;

  EncodedChunk({
    required this.byteLength,
    this.duration,
    required this.timestamp,
    required this.type,
    required this.data,
  });
}

/// MP4 container for fragmented MP4 output
///
/// Creates ISO BMFF compliant fragmented MP4 files with:
/// - ftyp (file type)
/// - moov (movie header with trak entries)
/// - moof + mdat pairs (movie fragments with media data)
class Mp4Container {
  /// Whether audio track is expected
  final bool hasAudio;

  /// Whether video track is expected
  final bool hasVideo;

  /// Audio track ID
  int? audioTrack;

  /// Video track ID
  int? videoTrack;

  /// Audio frame buffer (for duration calculation)
  EncodedChunk? _audioFrame;

  /// Video frame buffer (for duration calculation)
  EncodedChunk? _videoFrame;

  /// Audio segment counter
  int _audioSegment = 0;

  /// Video segment counter
  int _videoSegment = 0;

  /// Next track ID
  int _nextTrackId = 1;

  /// Track configurations
  AudioDecoderConfig? _audioConfig;
  VideoDecoderConfig? _videoConfig;

  /// Frame buffer (for when tracks aren't ready)
  final List<(EncodedChunk, String)> _frameBuffer = [];

  /// Data output stream
  final StreamController<Mp4Data> _dataController =
      StreamController<Mp4Data>.broadcast();

  /// Data stream
  Stream<Mp4Data> get onData => _dataController.stream;

  Mp4Container({
    required this.hasAudio,
    required this.hasVideo,
  });

  /// Check if all expected tracks are initialized
  bool get tracksReady {
    if (hasAudio && audioTrack == null) return false;
    if (hasVideo && videoTrack == null) return false;
    return true;
  }

  /// Initialize audio track
  void initAudioTrack(AudioDecoderConfig config) {
    _audioConfig = config;
    audioTrack = _nextTrackId++;

    if (tracksReady) {
      _writeInitSegment();
    }
  }

  /// Initialize video track
  void initVideoTrack(VideoDecoderConfig config) {
    _videoConfig = config;
    videoTrack = _nextTrackId++;

    if (tracksReady) {
      _writeInitSegment();
    }
  }

  /// Add audio chunk
  void addAudioChunk(EncodedChunk chunk) {
    if (!tracksReady) {
      _frameBuffer.add((chunk, 'audio'));
      return;
    }

    _flushBuffer();
    _processAudioChunk(chunk);
  }

  /// Add video chunk
  void addVideoChunk(EncodedChunk chunk) {
    if (!tracksReady) {
      if (chunk.type == 'key') {
        _frameBuffer.add((chunk, 'video'));
      }
      return;
    }

    _flushBuffer();
    _processVideoChunk(chunk);
  }

  void _flushBuffer() {
    for (final (chunk, kind) in _frameBuffer) {
      if (kind == 'audio') {
        _processAudioChunk(chunk);
      } else {
        _processVideoChunk(chunk);
      }
    }
    _frameBuffer.clear();
  }

  void _processAudioChunk(EncodedChunk chunk) {
    _audioSegment++;

    // Buffer one frame to compute duration
    if (_audioFrame == null) {
      _audioFrame = chunk;
      return;
    }

    final buffered = _audioFrame!;
    final duration = chunk.timestamp - buffered.timestamp;

    _writeFragment(
      trackId: audioTrack!,
      chunk: buffered,
      duration: duration,
      kind: 'audio',
    );

    _audioFrame = chunk;
  }

  void _processVideoChunk(EncodedChunk chunk) {
    if (chunk.type == 'key') {
      _videoSegment++;
    } else if (_videoSegment == 0) {
      // Must start with keyframe
      return;
    }

    // Buffer one frame to compute duration
    if (_videoFrame == null) {
      _videoFrame = chunk;
      return;
    }

    final buffered = _videoFrame!;
    final duration = chunk.timestamp - buffered.timestamp;

    _writeFragment(
      trackId: videoTrack!,
      chunk: buffered,
      duration: duration,
      kind: 'video',
    );

    _videoFrame = chunk;
  }

  void _writeInitSegment() {
    final builder = Mp4BoxBuilder();

    // ftyp box
    builder.addBox(_buildFtyp());

    // moov box
    builder.addBox(_buildMoov());

    final data = builder.build();
    _dataController.add(Mp4Data(
      type: Mp4DataType.init,
      timestamp: 0,
      duration: 0,
      data: data,
      kind: 'video', // Init segment is always marked as video
    ));
  }

  void _writeFragment({
    required int trackId,
    required EncodedChunk chunk,
    required int duration,
    required String kind,
  }) {
    final builder = Mp4BoxBuilder();

    // moof box
    builder.addBox(_buildMoof(
      trackId: trackId,
      timestamp: chunk.timestamp,
      duration: duration,
      isKeyframe: chunk.type == 'key',
      dataSize: chunk.data.length,
    ));

    // mdat box
    builder.addBox(_buildMdat(chunk.data));

    final data = builder.build();
    _dataController.add(Mp4Data(
      type: chunk.type == 'key' ? Mp4DataType.key : Mp4DataType.delta,
      timestamp: chunk.timestamp,
      duration: duration,
      data: data,
      kind: kind,
    ));
  }

  Uint8List _buildFtyp() {
    // ftyp: isom, iso5, avc1, mp41
    final builder = Mp4BoxBuilder();
    builder.writeBytes([0x69, 0x73, 0x6F, 0x6D]); // major_brand: isom
    builder.writeUint32(0x00000001); // minor_version
    builder.writeBytes([0x69, 0x73, 0x6F, 0x6D]); // compatible_brand: isom
    builder.writeBytes([0x69, 0x73, 0x6F, 0x35]); // compatible_brand: iso5
    builder.writeBytes([0x61, 0x76, 0x63, 0x31]); // compatible_brand: avc1
    builder.writeBytes([0x6D, 0x70, 0x34, 0x31]); // compatible_brand: mp41

    return _wrapBox('ftyp', builder.build());
  }

  Uint8List _buildMoov() {
    final builder = Mp4BoxBuilder();

    // mvhd (movie header)
    builder.addBox(_buildMvhd());

    // trak boxes for each track
    if (videoTrack != null && _videoConfig != null) {
      builder.addBox(_buildVideoTrak(videoTrack!, _videoConfig!));
    }
    if (audioTrack != null && _audioConfig != null) {
      builder.addBox(_buildAudioTrak(audioTrack!, _audioConfig!));
    }

    // mvex (movie extends)
    builder.addBox(_buildMvex());

    return _wrapBox('moov', builder.build());
  }

  Uint8List _buildMvhd() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // creation_time
    builder.writeUint32(0); // modification_time
    builder.writeUint32(1000000); // timescale (microseconds)
    builder.writeUint32(0); // duration (unknown for fragmented)
    builder.writeUint32(0x00010000); // rate = 1.0
    builder.writeUint16(0x0100); // volume = 1.0
    builder.writeBytes(List.filled(10, 0)); // reserved
    // Matrix (identity)
    builder.writeUint32(0x00010000);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0x00010000);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0x40000000);
    builder.writeBytes(List.filled(24, 0)); // pre_defined
    builder.writeUint32(_nextTrackId); // next_track_id

    return _wrapFullBox('mvhd', 0, 0, builder.build());
  }

  Uint8List _buildVideoTrak(int trackId, VideoDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildTkhd(trackId, config.codedWidth ?? 640,
        config.codedHeight ?? 480, false));
    builder.addBox(_buildVideoMdia(config));
    return _wrapBox('trak', builder.build());
  }

  Uint8List _buildAudioTrak(int trackId, AudioDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildTkhd(trackId, 0, 0, true));
    builder.addBox(_buildAudioMdia(config));
    return _wrapBox('trak', builder.build());
  }

  Uint8List _buildTkhd(int trackId, int width, int height, bool isAudio) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, isAudio ? 1 : 3]); // flags (track enabled)
    builder.writeUint32(0); // creation_time
    builder.writeUint32(0); // modification_time
    builder.writeUint32(trackId); // track_id
    builder.writeUint32(0); // reserved
    builder.writeUint32(0); // duration
    builder.writeBytes(List.filled(8, 0)); // reserved
    builder.writeUint16(0); // layer
    builder.writeUint16(isAudio ? 1 : 0); // alternate_group
    builder.writeUint16(isAudio ? 0x0100 : 0); // volume
    builder.writeUint16(0); // reserved
    // Matrix
    builder.writeUint32(0x00010000);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0x00010000);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0);
    builder.writeUint32(0x40000000);
    builder.writeUint32((width << 16) & 0xFFFFFFFF); // width
    builder.writeUint32((height << 16) & 0xFFFFFFFF); // height

    return _wrapFullBox('tkhd', 0, 0, builder.build());
  }

  Uint8List _buildVideoMdia(VideoDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildMdhd(1000000));
    builder.addBox(_buildHdlr('vide', 'VideoHandler'));
    builder.addBox(_buildVideoMinf(config));
    return _wrapBox('mdia', builder.build());
  }

  Uint8List _buildAudioMdia(AudioDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildMdhd(config.sampleRate));
    builder.addBox(_buildHdlr('soun', 'SoundHandler'));
    builder.addBox(_buildAudioMinf(config));
    return _wrapBox('mdia', builder.build());
  }

  Uint8List _buildMdhd(int timescale) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // creation_time
    builder.writeUint32(0); // modification_time
    builder.writeUint32(timescale); // timescale
    builder.writeUint32(0); // duration
    builder.writeUint16(0x55C4); // language (und)
    builder.writeUint16(0); // pre_defined

    return _wrapFullBox('mdhd', 0, 0, builder.build());
  }

  Uint8List _buildHdlr(String type, String name) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // pre_defined
    builder.writeBytes(type.codeUnits); // handler_type
    builder.writeBytes(List.filled(12, 0)); // reserved
    builder.writeBytes(name.codeUnits);
    builder.writeUint8(0); // null terminator

    return _wrapFullBox('hdlr', 0, 0, builder.build());
  }

  Uint8List _buildVideoMinf(VideoDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildVmhd());
    builder.addBox(_buildDinf());
    builder.addBox(_buildVideoStbl(config));
    return _wrapBox('minf', builder.build());
  }

  Uint8List _buildAudioMinf(AudioDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildSmhd());
    builder.addBox(_buildDinf());
    builder.addBox(_buildAudioStbl(config));
    return _wrapBox('minf', builder.build());
  }

  Uint8List _buildVmhd() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 1]); // flags
    builder.writeUint16(0); // graphics_mode
    builder.writeBytes([0, 0, 0, 0, 0, 0]); // opcolor

    return _wrapFullBox('vmhd', 0, 1, builder.build());
  }

  Uint8List _buildSmhd() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint16(0); // balance
    builder.writeUint16(0); // reserved

    return _wrapFullBox('smhd', 0, 0, builder.build());
  }

  Uint8List _buildDinf() {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildDref());
    return _wrapBox('dinf', builder.build());
  }

  Uint8List _buildDref() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(1); // entry_count

    // url entry
    final urlBuilder = Mp4BoxBuilder();
    urlBuilder.writeUint8(0); // version
    urlBuilder.writeBytes([0, 0, 1]); // flags (self-contained)
    builder.addBox(_wrapFullBox('url ', 0, 1, urlBuilder.build()));

    return _wrapFullBox('dref', 0, 0, builder.build());
  }

  Uint8List _buildVideoStbl(VideoDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildVideoStsd(config));
    builder.addBox(_buildStts());
    builder.addBox(_buildStsc());
    builder.addBox(_buildStsz());
    builder.addBox(_buildStco());
    return _wrapBox('stbl', builder.build());
  }

  Uint8List _buildAudioStbl(AudioDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildAudioStsd(config));
    builder.addBox(_buildStts());
    builder.addBox(_buildStsc());
    builder.addBox(_buildStsz());
    builder.addBox(_buildStco());
    return _wrapBox('stbl', builder.build());
  }

  Uint8List _buildVideoStsd(VideoDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(1); // entry_count
    builder.addBox(_buildAvc1(config));

    return _wrapFullBox('stsd', 0, 0, builder.build());
  }

  Uint8List _buildAudioStsd(AudioDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(1); // entry_count
    builder.addBox(_buildOpus(config));

    return _wrapFullBox('stsd', 0, 0, builder.build());
  }

  Uint8List _buildAvc1(VideoDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.writeBytes(List.filled(6, 0)); // reserved
    builder.writeUint16(1); // data_reference_index
    builder.writeBytes(List.filled(16, 0)); // pre_defined + reserved
    builder.writeUint16(config.codedWidth ?? 640); // width
    builder.writeUint16(config.codedHeight ?? 480); // height
    builder.writeUint32(0x00480000); // horizresolution (72 dpi)
    builder.writeUint32(0x00480000); // vertresolution (72 dpi)
    builder.writeUint32(0); // reserved
    builder.writeUint16(1); // frame_count
    builder.writeBytes(List.filled(32, 0)); // compressor_name
    builder.writeUint16(0x0018); // depth
    builder.writeInt16(-1); // pre_defined

    // avcC box
    if (config.description != null) {
      builder.addBox(_wrapBox('avcC', config.description!));
    }

    return _wrapBox('avc1', builder.build());
  }

  Uint8List _buildOpus(AudioDecoderConfig config) {
    final builder = Mp4BoxBuilder();
    builder.writeBytes(List.filled(6, 0)); // reserved
    builder.writeUint16(1); // data_reference_index
    builder.writeBytes(List.filled(8, 0)); // reserved
    builder.writeUint16(config.numberOfChannels); // channel_count
    builder.writeUint16(16); // sample_size
    builder.writeBytes(List.filled(4, 0)); // pre_defined + reserved
    builder.writeUint32((config.sampleRate << 16) & 0xFFFFFFFF); // sample_rate

    // dOps box
    if (config.description != null && config.description!.length > 8) {
      builder.addBox(_buildDops(config.description!));
    }

    return _wrapBox('Opus', builder.build());
  }

  Uint8List _buildDops(Uint8List opusHead) {
    // Skip "OpusHead" magic (8 bytes)
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    final data = opusHead.sublist(8);
    builder.writeBytes(data);
    return _wrapBox('dOps', builder.build());
  }

  Uint8List _buildStts() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // entry_count

    return _wrapFullBox('stts', 0, 0, builder.build());
  }

  Uint8List _buildStsc() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // entry_count

    return _wrapFullBox('stsc', 0, 0, builder.build());
  }

  Uint8List _buildStsz() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // sample_size
    builder.writeUint32(0); // sample_count

    return _wrapFullBox('stsz', 0, 0, builder.build());
  }

  Uint8List _buildStco() {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(0); // entry_count

    return _wrapFullBox('stco', 0, 0, builder.build());
  }

  Uint8List _buildMvex() {
    final builder = Mp4BoxBuilder();
    if (videoTrack != null) {
      builder.addBox(_buildTrex(videoTrack!));
    }
    if (audioTrack != null) {
      builder.addBox(_buildTrex(audioTrack!));
    }
    return _wrapBox('mvex', builder.build());
  }

  Uint8List _buildTrex(int trackId) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(trackId); // track_id
    builder.writeUint32(1); // default_sample_description_index
    builder.writeUint32(0); // default_sample_duration
    builder.writeUint32(0); // default_sample_size
    builder.writeUint32(0); // default_sample_flags

    return _wrapFullBox('trex', 0, 0, builder.build());
  }

  Uint8List _buildMoof({
    required int trackId,
    required int timestamp,
    required int duration,
    required bool isKeyframe,
    required int dataSize,
  }) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildMfhd(_videoSegment + _audioSegment));
    builder.addBox(_buildTraf(
      trackId: trackId,
      timestamp: timestamp,
      duration: duration,
      isKeyframe: isKeyframe,
      dataSize: dataSize,
    ));
    return _wrapBox('moof', builder.build());
  }

  Uint8List _buildMfhd(int sequenceNumber) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint32(sequenceNumber);

    return _wrapFullBox('mfhd', 0, 0, builder.build());
  }

  Uint8List _buildTraf({
    required int trackId,
    required int timestamp,
    required int duration,
    required bool isKeyframe,
    required int dataSize,
  }) {
    final builder = Mp4BoxBuilder();
    builder.addBox(_buildTfhd(trackId));
    builder.addBox(_buildTfdt(timestamp));
    builder.addBox(_buildTrun(
      duration: duration,
      dataSize: dataSize,
      isKeyframe: isKeyframe,
    ));
    return _wrapBox('traf', builder.build());
  }

  Uint8List _buildTfhd(int trackId) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    builder.writeBytes([0x02, 0x00, 0x20]); // flags: default-base-is-moof
    builder.writeUint32(trackId);

    return _wrapFullBox('tfhd', 0, 0x020020, builder.build());
  }

  Uint8List _buildTfdt(int baseMediaDecodeTime) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(1); // version 1 for 64-bit time
    builder.writeBytes([0, 0, 0]); // flags
    builder.writeUint64(baseMediaDecodeTime);

    return _wrapFullBox('tfdt', 1, 0, builder.build());
  }

  Uint8List _buildTrun({
    required int duration,
    required int dataSize,
    required bool isKeyframe,
  }) {
    final builder = Mp4BoxBuilder();
    builder.writeUint8(0); // version
    // flags: data-offset-present, sample-duration-present,
    // sample-size-present, sample-flags-present
    builder.writeBytes([0x00, 0x0F, 0x01]);
    builder.writeUint32(1); // sample_count

    // Calculate data offset (moof header + traf + trun + mdat header)
    // This is filled in by the caller
    builder.writeUint32(0); // data_offset (placeholder)

    // Sample entry
    builder.writeUint32(duration); // sample_duration
    builder.writeUint32(dataSize); // sample_size

    // sample_flags
    if (isKeyframe) {
      builder.writeUint32(0x02000000); // is_leading=0, depends_on=2 (does not depend)
    } else {
      builder.writeUint32(0x01010000); // is_leading=0, depends_on=1 (depends on another)
    }

    return _wrapFullBox('trun', 0, 0x000F01, builder.build());
  }

  Uint8List _buildMdat(Uint8List data) {
    return _wrapBox('mdat', data);
  }

  Uint8List _wrapBox(String type, Uint8List data) {
    final size = 8 + data.length;
    final builder = Mp4BoxBuilder();
    builder.writeUint32(size);
    builder.writeBytes(type.codeUnits);
    builder.writeBytes(data);
    return builder.build();
  }

  Uint8List _wrapFullBox(String type, int version, int flags, Uint8List data) {
    final fullData = Uint8List(4 + data.length);
    fullData[0] = version;
    fullData[1] = (flags >> 16) & 0xFF;
    fullData[2] = (flags >> 8) & 0xFF;
    fullData[3] = flags & 0xFF;
    fullData.setAll(4, data);
    return _wrapBox(type, fullData);
  }

  /// Close the container
  void close() {
    _dataController.close();
  }
}

/// Helper for building MP4 boxes
class Mp4BoxBuilder {
  final BytesBuilder _builder = BytesBuilder();

  void writeUint8(int value) {
    _builder.addByte(value & 0xFF);
  }

  void writeUint16(int value) {
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte(value & 0xFF);
  }

  void writeInt16(int value) {
    writeUint16(value & 0xFFFF);
  }

  void writeUint32(int value) {
    _builder.addByte((value >> 24) & 0xFF);
    _builder.addByte((value >> 16) & 0xFF);
    _builder.addByte((value >> 8) & 0xFF);
    _builder.addByte(value & 0xFF);
  }

  void writeUint64(int value) {
    writeUint32((value >> 32) & 0xFFFFFFFF);
    writeUint32(value & 0xFFFFFFFF);
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  void addBox(Uint8List box) {
    _builder.add(box);
  }

  Uint8List build() {
    return _builder.toBytes();
  }
}

/// H.264 utilities
class H264Utils {
  /// Convert Annex B format to AVCC format
  ///
  /// Annex B uses start codes (0x000001 or 0x00000001)
  /// AVCC uses length prefixes (4 bytes)
  static Uint8List annexBToAvcc(Uint8List annexB) {
    final result = BytesBuilder();
    var i = 0;

    while (i < annexB.length) {
      // Find start code
      int startCodeLen;
      if (i + 4 <= annexB.length &&
          annexB[i] == 0 &&
          annexB[i + 1] == 0 &&
          annexB[i + 2] == 0 &&
          annexB[i + 3] == 1) {
        startCodeLen = 4;
      } else if (i + 3 <= annexB.length &&
          annexB[i] == 0 &&
          annexB[i + 1] == 0 &&
          annexB[i + 2] == 1) {
        startCodeLen = 3;
      } else {
        i++;
        continue;
      }

      // Find next start code or end
      var j = i + startCodeLen;
      while (j < annexB.length) {
        if (j + 4 <= annexB.length &&
            annexB[j] == 0 &&
            annexB[j + 1] == 0 &&
            annexB[j + 2] == 0 &&
            annexB[j + 3] == 1) {
          break;
        }
        if (j + 3 <= annexB.length &&
            annexB[j] == 0 &&
            annexB[j + 1] == 0 &&
            annexB[j + 2] == 1) {
          break;
        }
        j++;
      }

      // NAL unit
      final nalLen = j - i - startCodeLen;
      if (nalLen > 0) {
        // Write 4-byte length prefix
        result.addByte((nalLen >> 24) & 0xFF);
        result.addByte((nalLen >> 16) & 0xFF);
        result.addByte((nalLen >> 8) & 0xFF);
        result.addByte(nalLen & 0xFF);

        // Write NAL data
        result.add(annexB.sublist(i + startCodeLen, j));
      }

      i = j;
    }

    return result.toBytes();
  }

  /// Create AVCDecoderConfigurationRecord from SPS and PPS
  static Uint8List createAvccFromSpsPps(Uint8List sps, Uint8List pps) {
    final builder = BytesBuilder();

    builder.addByte(1); // configurationVersion
    builder.addByte(sps[1]); // AVCProfileIndication
    builder.addByte(sps[2]); // profile_compatibility
    builder.addByte(sps[3]); // AVCLevelIndication
    builder.addByte(0xFF); // lengthSizeMinusOne = 3 (4 bytes)

    // SPS
    builder.addByte(0xE1); // numOfSequenceParameterSets = 1
    builder.addByte((sps.length >> 8) & 0xFF);
    builder.addByte(sps.length & 0xFF);
    builder.add(sps);

    // PPS
    builder.addByte(1); // numOfPictureParameterSets = 1
    builder.addByte((pps.length >> 8) & 0xFF);
    builder.addByte(pps.length & 0xFF);
    builder.add(pps);

    return builder.toBytes();
  }
}
