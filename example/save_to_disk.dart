/// Save to Disk Example
///
/// This example demonstrates how to use the WebmContainer to create
/// a WebM file from video and audio frames.
///
/// Note: This is a structural example showing the WebM container API.
/// In a real application, frames would come from decoded RTP packets.
///
/// Usage: dart run examples/save_to_disk.dart
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:webrtc_dart/src/container/webm/container.dart';
import 'package:webrtc_dart/src/container/webm/processor.dart';

void main() async {
  print('Save to Disk Example');
  print('=' * 50);
  print('');

  // Create output filename with timestamp
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final outputPath = './recording-$timestamp.webm';

  print('Output file: $outputPath');
  print('');

  // Collect output data
  final outputChunks = <Uint8List>[];

  // Create tracks for WebM container
  final tracks = [
    WebmTrack(
      trackNumber: 1,
      kind: TrackKind.video,
      codec: WebmCodec.vp8,
      width: 640,
      height: 480,
    ),
    WebmTrack(
      trackNumber: 2,
      kind: TrackKind.audio,
      codec: WebmCodec.opus,
    ),
  ];

  // Create WebM processor with tracks and output callback
  final processor = WebmProcessor(
    tracks: tracks,
    onOutput: (output) {
      if (output.data != null) {
        outputChunks.add(output.data!);
      }
    },
  );

  // Start the processor (writes EBML header and segment)
  processor.start();

  // Simulate recording for 3 seconds at 30fps
  print('Generating simulated frames...');
  final random = Random();
  final durationSeconds = 3;
  final fps = 30;
  final totalFrames = durationSeconds * fps;

  var videoFrameCount = 0;
  var audioFrameCount = 0;

  for (var i = 0; i < totalFrames; i++) {
    // Video timestamp in milliseconds
    final videoTimestampMs = (i * 1000 / fps).round();

    // Generate simulated VP8 frame
    final isKeyframe = i % fps == 0; // Keyframe every second
    final frameSize = isKeyframe ? 5000 : 500 + random.nextInt(1000);
    final videoData = Uint8List(frameSize);
    for (var j = 0; j < frameSize; j++) {
      videoData[j] = random.nextInt(256);
    }

    // Add video frame
    processor.processVideoFrame(WebmFrame(
      data: videoData,
      timeMs: videoTimestampMs,
      isKeyframe: isKeyframe,
      trackNumber: 1,
    ));
    videoFrameCount++;

    if (videoFrameCount % 30 == 0) {
      print('Video frames: $videoFrameCount');
    }

    // Add audio frames (multiple per video frame for 48kHz audio)
    // Opus typically uses 20ms frames, so ~50 frames per second
    if (i % 2 == 0) {
      // Every ~33ms (alternating video frames)
      final audioTimestampMs = videoTimestampMs;
      final audioSize = 40 + random.nextInt(60); // Typical Opus frame size
      final audioData = Uint8List(audioSize);
      for (var j = 0; j < audioSize; j++) {
        audioData[j] = random.nextInt(256);
      }

      processor.processAudioFrame(WebmFrame(
        data: audioData,
        timeMs: audioTimestampMs,
        isKeyframe: true,
        trackNumber: 2,
      ));
      audioFrameCount++;
    }
  }

  // Finalize the recording
  print('');
  print('Finalizing WebM...');
  processor.stop();

  // Concatenate all output chunks
  final totalLength = outputChunks.fold(0, (sum, chunk) => sum + chunk.length);
  final webmData = Uint8List(totalLength);
  var offset = 0;
  for (final chunk in outputChunks) {
    webmData.setAll(offset, chunk);
    offset += chunk.length;
  }

  // Save to file
  final file = File(outputPath);
  await file.writeAsBytes(webmData);

  print('');
  print('--- Recording Summary ---');
  print('Duration: $durationSeconds seconds');
  print('Video frames: $videoFrameCount');
  print('Audio frames: $audioFrameCount');
  print(
      'File size: ${webmData.length} bytes (${(webmData.length / 1024).toStringAsFixed(1)} KB)');
  print('Output file: $outputPath');
  print('');

  if (webmData.isNotEmpty) {
    print('SUCCESS: WebM file created!');
    print('');
    print('Note: This is simulated data. To play, use:');
    print('  ffplay $outputPath');
    print('');
    print('The file may not play correctly as the video/audio data');
    print('is random bytes, not actual encoded media.');
  } else {
    print('WARNING: WebM file is empty');
  }
}
