/// Save to Disk (MP4) Example
///
/// This example demonstrates how to use the Mp4Container to create
/// a fragmented MP4 (fMP4) file from video and audio frames.
///
/// Note: This is a structural example showing the fMP4 container API.
/// In a real application, frames would come from decoded RTP packets.
///
/// Usage: dart run examples/save_to_disk_mp4.dart
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:webrtc_dart/src/container/mp4/container.dart';

void main() async {
  print('Save to Disk (MP4) Example');
  print('=' * 50);
  print('');

  // Create output filename with timestamp
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final outputPath = './recording-$timestamp.mp4';

  print('Output file: $outputPath');
  print('');

  // Collect output data
  final outputChunks = <Uint8List>[];

  // Create MP4 container with video and audio tracks
  final container = Mp4Container(
    hasVideo: true,
    hasAudio: true,
  );

  // Listen for output data
  final outputSub = container.onData.listen((data) {
    outputChunks.add(data.data);
    if (data.type == Mp4DataType.init) {
      print('Received init segment (${data.data.length} bytes)');
    }
  });

  // Initialize video track (H.264/AVC)
  print('Initializing video track (H.264)...');
  container.initVideoTrack(VideoDecoderConfig(
    codec: 'avc1.42E01E', // H.264 Baseline Profile
    codedWidth: 640,
    codedHeight: 480,
    // In real usage, this would be the SPS/PPS from the H.264 stream
    description: _createFakeAvcDescription(),
  ));

  // Initialize audio track (Opus)
  print('Initializing audio track (Opus)...');
  container.initAudioTrack(AudioDecoderConfig(
    codec: 'opus',
    numberOfChannels: 2,
    sampleRate: 48000,
    description: _createFakeOpusDescription(),
  ));

  // Simulate recording for 3 seconds at 30fps
  print('');
  print('Generating simulated frames...');
  final random = Random();
  final durationSeconds = 3;
  final fps = 30;
  final totalFrames = durationSeconds * fps;

  var videoFrameCount = 0;
  var audioFrameCount = 0;

  for (var i = 0; i < totalFrames; i++) {
    // Video timestamp in microseconds
    final videoTimestampUs = (i * 1000000 / fps).round();

    // Generate simulated H.264 frame
    final isKeyframe = i % fps == 0; // Keyframe every second
    final frameSize = isKeyframe ? 8000 : 1000 + random.nextInt(2000);
    final videoData = Uint8List(frameSize);
    for (var j = 0; j < frameSize; j++) {
      videoData[j] = random.nextInt(256);
    }

    // Add video frame
    container.addVideoChunk(EncodedChunk(
      byteLength: videoData.length,
      timestamp: videoTimestampUs,
      duration: (1000000 / fps).round(),
      type: isKeyframe ? 'key' : 'delta',
      data: videoData,
    ));
    videoFrameCount++;

    if (videoFrameCount % 30 == 0) {
      print('Video frames: $videoFrameCount');
    }

    // Add audio frames (multiple per video frame for 48kHz audio)
    // Opus typically uses 20ms frames, so ~50 frames per second
    if (i % 2 == 0) {
      final audioTimestampUs = videoTimestampUs;
      final audioSize = 40 + random.nextInt(60);
      final audioData = Uint8List(audioSize);
      for (var j = 0; j < audioSize; j++) {
        audioData[j] = random.nextInt(256);
      }

      container.addAudioChunk(EncodedChunk(
        byteLength: audioData.length,
        timestamp: audioTimestampUs,
        duration: 20000, // 20ms in microseconds
        type: 'key', // All audio frames are keyframes
        data: audioData,
      ));
      audioFrameCount++;
    }
  }

  // Finalize by closing the container
  print('');
  print('Finalizing MP4...');
  container.close();

  // Cancel subscription
  await outputSub.cancel();

  // Concatenate all output chunks
  final totalLength = outputChunks.fold(0, (sum, chunk) => sum + chunk.length);
  final mp4Data = Uint8List(totalLength);
  var offset = 0;
  for (final chunk in outputChunks) {
    mp4Data.setAll(offset, chunk);
    offset += chunk.length;
  }

  // Save to file
  final file = File(outputPath);
  await file.writeAsBytes(mp4Data);

  print('');
  print('--- Recording Summary ---');
  print('Duration: $durationSeconds seconds');
  print('Video frames: $videoFrameCount');
  print('Audio frames: $audioFrameCount');
  print('File size: ${mp4Data.length} bytes (${(mp4Data.length / 1024).toStringAsFixed(1)} KB)');
  print('Output file: $outputPath');
  print('');

  if (mp4Data.isNotEmpty) {
    print('SUCCESS: MP4 file created!');
    print('');
    print('Note: This is simulated data with fake codec descriptions.');
    print('The file structure is valid fMP4, but the media data is random.');
    print('');
    print('Fragmented MP4 (fMP4) is used for:');
    print('  - Live streaming (DASH, HLS)');
    print('  - MSE (Media Source Extensions) playback');
    print('  - Progressive download');
  } else {
    print('WARNING: MP4 file is empty');
  }
}

/// Create fake AVC (H.264) decoder configuration
/// In real usage, this would come from the H.264 SPS/PPS NAL units
Uint8List _createFakeAvcDescription() {
  // This is a minimal AVCDecoderConfigurationRecord
  // Version 1, Profile 66, Compatibility 0, Level 30
  return Uint8List.fromList([
    0x01, // configurationVersion
    0x42, // AVCProfileIndication (Baseline)
    0x00, // profile_compatibility
    0x1E, // AVCLevelIndication (3.0)
    0xFF, // lengthSizeMinusOne (3 = 4 bytes NAL length)
    0xE1, // numOfSequenceParameterSets (1)
    0x00, 0x04, // SPS length
    0x67, 0x42, 0x00, 0x1E, // Fake SPS
    0x01, // numOfPictureParameterSets
    0x00, 0x04, // PPS length
    0x68, 0xCE, 0x3C, 0x80, // Fake PPS
  ]);
}

/// Create fake Opus decoder configuration
/// In real usage, this would be the OpusHead from the stream
Uint8List _createFakeOpusDescription() {
  // OpusHead structure (RFC 7845)
  return Uint8List.fromList([
    0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
    0x01, // Version
    0x02, // Channel count
    0x00, 0x00, // Pre-skip (little-endian)
    0x80, 0xBB, 0x00, 0x00, // Sample rate 48000 (little-endian)
    0x00, 0x00, // Output gain
    0x00, // Channel mapping family
  ]);
}
