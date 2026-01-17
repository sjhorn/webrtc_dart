/// Dump H264 packets from Ring camera to a file for offline testing
///
/// Usage:
///   cd example/ring && dart run dump_h264.dart [duration_seconds]
///
/// Output: ring_capture.h264
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ring_client_api/ring_client_api.dart' as ring;

import 'peer.dart';

/// H264 Annex B start code
final _startCode = Uint8List.fromList([0x00, 0x00, 0x00, 0x01]);

/// Reassemble FU-A fragments into complete NAL units
class FuaReassembler {
  final _fragments = <Uint8List>[];
  int? _nalType;
  int? _nri;

  /// Process an FU-A fragment, returns complete NAL unit when done
  Uint8List? addFragment(Uint8List fuaPayload) {
    if (fuaPayload.length < 2) return null;

    final fuIndicator = fuaPayload[0];
    final fuHeader = fuaPayload[1];

    final nri = (fuIndicator >> 5) & 0x03;
    final nalType = fuHeader & 0x1F;
    final isStart = (fuHeader & 0x80) != 0;
    final isEnd = (fuHeader & 0x40) != 0;

    if (isStart) {
      _fragments.clear();
      _nalType = nalType;
      _nri = nri;
    }

    // Add fragment data (skip FU indicator and header)
    if (fuaPayload.length > 2) {
      _fragments.add(fuaPayload.sublist(2));
    }

    if (isEnd && _nalType != null) {
      // Reassemble: NAL header + all fragment data
      final nalHeader = (_nri! << 5) | _nalType!;
      var totalLen = 1; // NAL header
      for (final f in _fragments) {
        totalLen += f.length;
      }

      final result = Uint8List(totalLen);
      result[0] = nalHeader;
      var offset = 1;
      for (final f in _fragments) {
        result.setRange(offset, offset + f.length, f);
        offset += f.length;
      }

      _fragments.clear();
      _nalType = null;
      return result;
    }

    return null;
  }
}

void main(List<String> args) async {
  final durationSeconds = args.isNotEmpty ? int.tryParse(args[0]) ?? 30 : 30;

  // Load refresh token
  final token = _loadRefreshToken();
  if (token == null) {
    print('Error: Set RING_REFRESH_TOKEN in .env file');
    exit(1);
  }

  print('H264 Capture from Ring Camera');
  print('Duration: ${durationSeconds}s');
  print('');

  // Open output file
  final outputFile = File('ring_capture.h264');
  final sink = outputFile.openWrite();
  var nalCount = 0;
  var frameCount = 0;
  var bytesWritten = 0;

  // FU-A reassembler
  final reassembler = FuaReassembler();

  /// Write NAL unit with Annex B start code
  void writeNalUnit(Uint8List nalUnit) {
    sink.add(_startCode);
    sink.add(nalUnit);
    nalCount++;
    bytesWritten += 4 + nalUnit.length;
  }

  // Connect to Ring
  print('Connecting to Ring...');
  final ringApi = ring.RingApi(
    ring.RefreshTokenAuth(refreshToken: token),
    options: ring.RingApiOptions(debug: false),
  );

  final cameras = await ringApi.getCameras();
  if (cameras.isEmpty) {
    print('Error: No cameras found');
    exit(1);
  }

  final camera = cameras[0]; // Use same camera as werift (index 0)
  print('Camera: ${camera.name}');

  // Create peer connection
  final pc = CustomPeerConnection();

  // Track capture stats
  var rtpPackets = 0;
  final startTime = DateTime.now();

  // Subscribe to video RTP
  pc.onVideoRtp.listen((rtp) {
    rtpPackets++;

    if (rtp.payload.isEmpty) return;

    final nalHeader = rtp.payload[0];
    final nalType = nalHeader & 0x1F;

    if (nalType >= 1 && nalType <= 23) {
      // Single NAL unit
      writeNalUnit(rtp.payload);
    } else if (nalType == 28) {
      // FU-A fragmented unit
      final complete = reassembler.addFragment(rtp.payload);
      if (complete != null) {
        writeNalUnit(complete);
      }
    } else if (nalType == 24) {
      // STAP-A aggregated packet
      var offset = 1;
      while (offset + 2 <= rtp.payload.length) {
        final size = (rtp.payload[offset] << 8) | rtp.payload[offset + 1];
        offset += 2;
        if (offset + size <= rtp.payload.length) {
          writeNalUnit(rtp.payload.sublist(offset, offset + size));
        }
        offset += size;
      }
    }

    // Count frames (marker bit indicates end of frame)
    if (rtp.marker) {
      frameCount++;
      if (frameCount % 30 == 0) {
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        print(
            'Progress: $frameCount frames, $nalCount NALs, ${bytesWritten ~/ 1024} KB ($elapsed s)');
      }
    }
  });

  // Connection state
  var connected = false;
  pc.onConnectionState.listen((state) {
    if (state == ring.ConnectionState.connected && !connected) {
      connected = true;
      print('Connected! Capturing...');
    }
  });

  // Start live call
  final session = await camera.startLiveCall(
    ring.StreamingConnectionOptions(createPeerConnection: () => pc),
  );

  // Wait for connection
  await Future.delayed(Duration(seconds: 5));
  if (!connected) {
    print('Warning: Not connected after 5s, continuing anyway...');
  }

  // Capture for specified duration
  print('Capturing for $durationSeconds seconds...');
  await Future.delayed(Duration(seconds: durationSeconds));

  // Close
  print('');
  print('Stopping capture...');
  await sink.flush();
  await sink.close();
  session.stop();
  pc.close();

  // Summary
  final fileSize = outputFile.lengthSync();
  print('');
  print('='.padRight(50, '='));
  print('Capture Complete');
  print('='.padRight(50, '='));
  print('Output: ${outputFile.path}');
  print('Size: ${(fileSize / 1024).toStringAsFixed(1)} KB');
  print('RTP packets: $rtpPackets');
  print('NAL units: $nalCount');
  print('Frames: $frameCount');
  print('Duration: ${durationSeconds}s');
  if (frameCount > 0) {
    print('Frame rate: ${(frameCount / durationSeconds).toStringAsFixed(1)} fps');
  }
  print('');
  print('Test with: ffprobe ring_capture.h264');
  print('Play with: ffplay ring_capture.h264');

  exit(0);
}

String? _loadRefreshToken() {
  var token = Platform.environment['RING_REFRESH_TOKEN'];
  if (token != null && token.isNotEmpty) return token;

  final envFile = File('.env');
  if (envFile.existsSync()) {
    for (final line in envFile.readAsLinesSync()) {
      if (line.startsWith('RING_REFRESH_TOKEN=')) {
        token = line.substring('RING_REFRESH_TOKEN='.length).trim();
        if (token.isNotEmpty) return token;
      }
    }
  }
  return null;
}
