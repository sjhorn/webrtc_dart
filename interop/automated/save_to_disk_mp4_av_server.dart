// Save to Disk MP4 A/V Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send camera video (H.264) + microphone audio (Opus)
// 2. Creates a PeerConnection configured for H.264 video and Opus audio
// 3. Records both streams to a fragmented MP4 file
// 4. Stops recording after a configurable duration
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)
// Output: MP4 file with H.264 video + Opus audio

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/container/mp4/container.dart';

class SaveToDiskMp4AvServer {
  HttpServer? _server;
  RTCPeerConnection? _pc;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _videoPacketsReceived = 0;
  int _audioPacketsReceived = 0;
  int _videoFramesWritten = 0;
  int _audioFramesWritten = 0;
  String? _outputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;

  // H.264 depacketization state
  Uint8List? _fragment;
  Uint8List? _sps;
  Uint8List? _pps;
  bool _videoInitialized = false;
  bool _audioInitialized = false;
  int _videoBaseTimestamp = 0;
  int _audioBaseTimestamp = 0;
  bool _gotFirstVideoTimestamp = false;
  bool _gotFirstAudioTimestamp = false;

  // MP4 output
  Mp4Container? _container;
  final List<Uint8List> _outputChunks = [];
  StreamSubscription<Mp4Data>? _outputSub;
  bool _stopped = false;

  SaveToDiskMp4AvServer({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8772}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SaveToDisk-MP4-AV] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Enable CORS
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers
        .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers
        .add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    print('[SaveToDisk-MP4-AV] ${request.method} $path');

    try {
      switch (path) {
        case '/':
        case '/index.html':
          await _serveTestPage(request);
          break;
        case '/start':
          await _handleStart(request);
          break;
        case '/offer':
          await _handleOffer(request);
          break;
        case '/answer':
          await _handleAnswer(request);
          break;
        case '/candidate':
          await _handleCandidate(request);
          break;
        case '/candidates':
          await _handleCandidates(request);
          break;
        case '/status':
          await _handleStatus(request);
          break;
        case '/result':
          await _handleResult(request);
          break;
        case '/shutdown':
          await _handleShutdown(request);
          break;
        default:
          request.response.statusCode = 404;
          request.response.write('Not found');
      }
    } catch (e, st) {
      print('[SaveToDisk-MP4-AV] Error: $e');
      print(st);
      request.response.statusCode = 500;
      request.response.write('Error: $e');
    }

    await request.response.close();
  }

  Future<void> _serveTestPage(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_testPageHtml);
  }

  Future<void> _handleStart(HttpRequest request) async {
    _currentBrowser = request.uri.queryParameters['browser'] ?? 'unknown';
    print('[SaveToDisk-MP4-AV] Starting MP4 A/V test for: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _videoPacketsReceived = 0;
    _audioPacketsReceived = 0;
    _videoFramesWritten = 0;
    _audioFramesWritten = 0;
    _outputPath =
        './recording-mp4-av-${DateTime.now().millisecondsSinceEpoch}.mp4';
    _fragment = null;
    _sps = null;
    _pps = null;
    _videoInitialized = false;
    _audioInitialized = false;
    _videoBaseTimestamp = 0;
    _audioBaseTimestamp = 0;
    _gotFirstVideoTimestamp = false;
    _gotFirstAudioTimestamp = false;
    _outputChunks.clear();
    _stopped = false;

    // Create MP4 container expecting both video and audio
    _container = Mp4Container(
      hasVideo: true,
      hasAudio: true,
    );

    // Listen for output
    _outputSub = _container!.onData.listen((data) {
      _outputChunks.add(data.data);
      if (data.type == Mp4DataType.init) {
        print(
            '[SaveToDisk-MP4-AV] MP4 init segment: ${data.data.length} bytes');
      }
    });

    // Create peer connection with STUN server
    _pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
      codecs: RtcCodecs(
        video: [
          createH264Codec(
            payloadType: 96,
            parameters:
                'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f',
          ),
        ],
        audio: [
          createOpusCodec(payloadType: 111),
        ],
      ),
    ));
    print('[SaveToDisk-MP4-AV] PeerConnection created with H.264 + Opus');

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[SaveToDisk-MP4-AV] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SaveToDisk-MP4-AV] ICE state: $state');
    });

    // Track ICE candidates
    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[SaveToDisk-MP4-AV] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': candidate.sdpMLineIndex.toString(),
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    });

    // Add recvonly video transceiver
    _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-MP4-AV] Added video transceiver (recvonly)');

    // Add recvonly audio transceiver
    _pc!.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-MP4-AV] Added audio transceiver (recvonly)');

    // Handle incoming tracks
    _pc!.onTrack.listen((transceiver) async {
      print('[SaveToDisk-MP4-AV] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      if (transceiver.kind == MediaStreamTrackKind.video) {
        // Listen for video RTP packets
        track.onReceiveRtp.listen((rtp) {
          _videoPacketsReceived++;
          _processVideoRtpPacket(rtp);

          if (_videoPacketsReceived % 100 == 0) {
            print(
                '[SaveToDisk-MP4-AV] Video: $_videoPacketsReceived packets, $_videoFramesWritten frames');
          }
        });
      } else if (transceiver.kind == MediaStreamTrackKind.audio) {
        // Listen for audio RTP packets
        track.onReceiveRtp.listen((rtp) {
          _audioPacketsReceived++;
          _processAudioRtpPacket(rtp);

          if (_audioPacketsReceived % 100 == 0) {
            print(
                '[SaveToDisk-MP4-AV] Audio: $_audioPacketsReceived packets, $_audioFramesWritten frames');
          }
        });
      }
    });

    print('[SaveToDisk-MP4-AV] Recording will start to: $_outputPath');

    // Stop recording after duration
    _recordingTimer =
        Timer(Duration(seconds: _recordingDurationSeconds), () async {
      print('[SaveToDisk-MP4-AV] Recording duration reached, stopping...');
      await _stopRecording();
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  void _processVideoRtpPacket(RtpPacket rtp) {
    if (_stopped) return;

    // Depacketize H.264
    final h264 = H264RtpPayload.deserialize(rtp.payload, _fragment);
    _fragment = h264.fragment;

    if (h264.payload.isEmpty) {
      return; // Incomplete fragment
    }

    // Get timestamp relative to start
    if (!_gotFirstVideoTimestamp) {
      _videoBaseTimestamp = rtp.timestamp;
      _gotFirstVideoTimestamp = true;
    }
    final relativeTimestamp = rtp.timestamp - _videoBaseTimestamp;
    // Convert from 90kHz clock to microseconds
    final timestampUs = (relativeTimestamp * 1000000 ~/ 90000);

    // Parse NAL units from Annex B payload
    _parseAndProcessVideoNalUnits(h264.payload, timestampUs, h264.isKeyframe);
  }

  void _parseAndProcessVideoNalUnits(
      Uint8List annexB, int timestampUs, bool isKeyframe) {
    var i = 0;
    while (i < annexB.length) {
      // Find start code
      int startCodeLen = 0;
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

      // Extract NAL unit (without start code)
      final nalu = annexB.sublist(i + startCodeLen, j);
      if (nalu.isNotEmpty) {
        _processVideoNalUnit(nalu, timestampUs, isKeyframe);
      }

      i = j;
    }
  }

  void _processVideoNalUnit(Uint8List nalu, int timestampUs, bool isKeyframe) {
    if (nalu.isEmpty || _stopped) return;

    final nalType = nalu[0] & 0x1F;

    // Extract SPS (type 7) and PPS (type 8)
    if (nalType == 7) {
      _sps = nalu;
      print('[SaveToDisk-MP4-AV] Got SPS (${nalu.length} bytes)');
      _tryInitializeVideoTrack();
      return;
    }

    if (nalType == 8) {
      _pps = nalu;
      print('[SaveToDisk-MP4-AV] Got PPS (${nalu.length} bytes)');
      _tryInitializeVideoTrack();
      return;
    }

    // Skip if video track not initialized yet
    if (!_videoInitialized || _container == null) {
      return;
    }

    // Convert NAL unit to AVCC format (4-byte length prefix)
    final avccNalu = Uint8List(4 + nalu.length);
    avccNalu[0] = (nalu.length >> 24) & 0xFF;
    avccNalu[1] = (nalu.length >> 16) & 0xFF;
    avccNalu[2] = (nalu.length >> 8) & 0xFF;
    avccNalu[3] = nalu.length & 0xFF;
    avccNalu.setAll(4, nalu);

    // Determine if keyframe (IDR slice = type 5)
    final isIdr = nalType == 5;

    // Add to container
    _container!.addVideoChunk(EncodedChunk(
      byteLength: avccNalu.length,
      timestamp: timestampUs,
      duration: 33333, // ~30fps
      type: isIdr ? 'key' : 'delta',
      data: avccNalu,
    ));

    _videoFramesWritten++;
  }

  void _tryInitializeVideoTrack() {
    if (_videoInitialized ||
        _sps == null ||
        _pps == null ||
        _container == null) {
      return;
    }

    print('[SaveToDisk-MP4-AV] Initializing video track with SPS/PPS');

    // Create AVCDecoderConfigurationRecord
    final avcC = H264Utils.createAvccFromSpsPps(_sps!, _pps!);

    // Initialize video track
    _container!.initVideoTrack(VideoDecoderConfig(
      codec: 'avc1.42e01f',
      codedWidth: 640,
      codedHeight: 480,
      description: avcC,
    ));

    _videoInitialized = true;
    print('[SaveToDisk-MP4-AV] Video track initialized');
  }

  void _processAudioRtpPacket(RtpPacket rtp) {
    if (_stopped) return;

    // Initialize audio track on first packet
    if (!_audioInitialized && _container != null) {
      _initializeAudioTrack();
    }

    if (!_audioInitialized || _container == null) {
      return;
    }

    // Get timestamp relative to start
    if (!_gotFirstAudioTimestamp) {
      _audioBaseTimestamp = rtp.timestamp;
      _gotFirstAudioTimestamp = true;
    }
    final relativeTimestamp = rtp.timestamp - _audioBaseTimestamp;
    // Convert from 48kHz clock to microseconds
    final timestampUs = (relativeTimestamp * 1000000 ~/ 48000);

    // Opus payload is directly in RTP payload (no depacketization needed for simple case)
    final opusData = rtp.payload;

    if (opusData.isEmpty) {
      return;
    }

    // Add to container
    _container!.addAudioChunk(EncodedChunk(
      byteLength: opusData.length,
      timestamp: timestampUs,
      duration: 20000, // Opus typically uses 20ms frames
      type: 'key', // All Opus frames are keyframes
      data: opusData,
    ));

    _audioFramesWritten++;
  }

  void _initializeAudioTrack() {
    if (_audioInitialized || _container == null) return;

    print('[SaveToDisk-MP4-AV] Initializing audio track (Opus)');

    // Create OpusHead for decoder config
    final opusHead = Uint8List.fromList([
      0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64, // "OpusHead"
      0x01, // Version
      0x02, // Channel count (stereo)
      0x00, 0x00, // Pre-skip (little-endian)
      0x80, 0xBB, 0x00, 0x00, // Sample rate 48000 (little-endian)
      0x00, 0x00, // Output gain
      0x00, // Channel mapping family
    ]);

    // Initialize audio track
    _container!.initAudioTrack(AudioDecoderConfig(
      codec: 'opus',
      numberOfChannels: 2,
      sampleRate: 48000,
      description: opusHead,
    ));

    _audioInitialized = true;
    print('[SaveToDisk-MP4-AV] Audio track initialized');
  }

  Future<void> _stopRecording() async {
    if (_container == null || _stopped) return;

    print('[SaveToDisk-MP4-AV] Stopping recording...');
    _stopped = true;
    _container!.close();
    await _outputSub?.cancel();
    _outputSub = null;

    // Write output file
    if (_outputPath != null && _outputChunks.isNotEmpty) {
      final totalLength =
          _outputChunks.fold(0, (sum, chunk) => sum + chunk.length);
      final mp4Data = Uint8List(totalLength);
      var offset = 0;
      for (final chunk in _outputChunks) {
        mp4Data.setAll(offset, chunk);
        offset += chunk.length;
      }

      final file = File(_outputPath!);
      await file.writeAsBytes(mp4Data);
      print(
          '[SaveToDisk-MP4-AV] Output file: $_outputPath (${mp4Data.length} bytes)');
    } else {
      print('[SaveToDisk-MP4-AV] WARNING: No output data!');
    }

    _container = null;
    print('[SaveToDisk-MP4-AV] Recording stopped');
  }

  Future<void> _handleOffer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    // Create offer
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[SaveToDisk-MP4-AV] Created offer, local description set');

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[SaveToDisk-MP4-AV] Sent offer to browser');
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final answer = RTCSessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[SaveToDisk-MP4-AV] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[SaveToDisk-MP4-AV] Remote description set');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidate(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    String candidateStr = data['candidate'] as String? ?? '';

    // Skip empty candidates
    if (candidateStr.isEmpty || candidateStr.trim().isEmpty) {
      print('[SaveToDisk-MP4-AV] Skipping empty ICE candidate');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      return;
    }

    if (candidateStr.startsWith('candidate:')) {
      candidateStr = candidateStr.substring('candidate:'.length);
    }

    try {
      final candidate = RTCIceCandidate.fromSdp(candidateStr);
      await _pc!.addIceCandidate(candidate);
      print('[SaveToDisk-MP4-AV] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[SaveToDisk-MP4-AV] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    int? fileSize;
    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        fileSize = await file.length();
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'videoPacketsReceived': _videoPacketsReceived,
      'audioPacketsReceived': _audioPacketsReceived,
      'videoFramesWritten': _videoFramesWritten,
      'audioFramesWritten': _audioFramesWritten,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'videoInitialized': _videoInitialized,
      'audioInitialized': _audioInitialized,
      'hasSps': _sps != null,
      'hasPps': _pps != null,
      'codec': 'H264+Opus',
      'container': 'MP4',
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    // Stop recording if still running
    await _stopRecording();

    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    // Check output file
    int fileSize = 0;
    bool fileCreated = false;
    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        fileSize = await file.length();
        fileCreated = fileSize > 0;
      }
    }

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _videoPacketsReceived > 0 &&
          _audioPacketsReceived > 0 &&
          fileCreated,
      'videoPacketsReceived': _videoPacketsReceived,
      'audioPacketsReceived': _audioPacketsReceived,
      'videoFramesWritten': _videoFramesWritten,
      'audioFramesWritten': _audioFramesWritten,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'H264+Opus',
      'container': 'MP4',
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result));
  }

  Future<void> _handleShutdown(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'shutting down'}));

    await _cleanup();

    Future.delayed(Duration(milliseconds: 100), () {
      _server?.close();
    });
  }

  Future<void> _cleanup() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _stopRecording();
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Save to Disk MP4 A/V Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        video {
            width: 320px;
            height: 240px;
            background: #000;
            border: 2px solid #333;
            margin: 10px 0;
        }
        #videoInfo { color: #ff8; margin: 5px 0; }
        .codec-badge { background: #f80; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .container-badge { background: #08f; color: #fff; padding: 2px 8px; border-radius: 4px; margin-left: 5px; }
        .audio-badge { background: #0a8; color: #fff; padding: 2px 8px; border-radius: 4px; margin-left: 5px; }
    </style>
</head>
<body>
    <h1>WebRTC Save to Disk Test <span class="codec-badge">H.264</span><span class="audio-badge">Opus</span><span class="container-badge">MP4</span></h1>
    <p>Browser sends H.264 video + Opus audio to Dart, which records to a fragmented MP4 file.</p>
    <div id="status">Status: Waiting to start...</div>
    <video id="localVideo" autoPlay muted playsinline></video>
    <div id="videoInfo">Waiting for camera/microphone...</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let localStream = null;
        const serverBase = window.location.origin;

        function log(msg, className = 'info') {
            const logDiv = document.getElementById('log');
            const line = document.createElement('div');
            line.className = className;
            line.textContent = '[' + new Date().toISOString().substr(11, 12) + '] ' + msg;
            logDiv.appendChild(line);
            logDiv.scrollTop = logDiv.scrollHeight;
            console.log(msg);
        }

        function setStatus(msg) {
            document.getElementById('status').textContent = 'Status: ' + msg;
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting MP4 A/V save_to_disk test for ' + browser);

                // Get local camera + microphone stream
                setStatus('Getting camera and microphone access...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        video: {
                            width: 640,
                            height: 480,
                        },
                        audio: true
                    });
                    log('Got local camera + microphone stream');
                    const localVideo = document.getElementById('localVideo');
                    localVideo.srcObject = localStream;
                    document.getElementById('videoInfo').textContent =
                        'Camera: ' + localStream.getVideoTracks()[0].label +
                        ', Mic: ' + localStream.getAudioTracks()[0].label;
                } catch (e) {
                    throw new Error('Failed to get media: ' + e.message);
                }

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (H.264 + Opus -> MP4)');

                // Create browser peer connection with STUN server
                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                // Set up ICE candidate handler
                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
                        log('Sending ICE candidate to Dart');
                        await fetch(serverBase + '/candidate', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                candidate: e.candidate.candidate,
                                sdpMid: e.candidate.sdpMid,
                                sdpMLineIndex: e.candidate.sdpMLineIndex
                            })
                        });
                    }
                };

                pc.oniceconnectionstatechange = () => {
                    log('ICE state: ' + pc.iceConnectionState,
                        pc.iceConnectionState === 'connected' ? 'success' : 'info');
                };

                pc.onconnectionstatechange = () => {
                    log('Connection state: ' + pc.connectionState,
                        pc.connectionState === 'connected' ? 'success' : 'info');
                };

                // Get offer from Dart server
                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                // Check codecs in offer
                if (offer.sdp.includes('H264')) {
                    log('H.264 codec found in offer', 'success');
                }
                if (offer.sdp.includes('opus')) {
                    log('Opus codec found in offer', 'success');
                }

                // Set remote description
                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // Add local video and audio tracks
                const videoTrack = localStream.getVideoTracks()[0];
                const audioTrack = localStream.getAudioTracks()[0];
                pc.addTrack(videoTrack, localStream);
                pc.addTrack(audioTrack, localStream);
                log('Added local video + audio tracks');

                // Create answer
                setStatus('Creating answer...');
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                // Wait for ICE gathering
                await new Promise(resolve => setTimeout(resolve, 500));

                // Send answer to Dart
                setStatus('Sending answer to Dart...');
                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

                // Get Dart's ICE candidates
                setStatus('Exchanging ICE candidates...');
                await new Promise(resolve => setTimeout(resolve, 500));

                const candidatesResp = await fetch(serverBase + '/candidates');
                const dartCandidates = await candidatesResp.json();
                log('Received ' + dartCandidates.length + ' ICE candidates from Dart');

                for (const c of dartCandidates) {
                    try {
                        await pc.addIceCandidate(new RTCIceCandidate(c));
                        log('Added Dart ICE candidate');
                    } catch (e) {
                        log('Failed to add candidate: ' + e.message, 'error');
                    }
                }

                // Wait for connection
                setStatus('Waiting for connection...');
                await waitForConnection();
                log('Connection established!', 'success');

                // Wait for recording
                setStatus('Recording H.264+Opus to MP4 (5 seconds)...');
                log('Sending video + audio for MP4 recording...');

                // Poll status
                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: V=' + status.videoPacketsReceived + '/' + status.videoFramesWritten +
                        ' A=' + status.audioPacketsReceived + '/' + status.audioFramesWritten +
                        ' file=' + (status.fileSize || 0) + ' bytes');
                }

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! MP4 A/V file created: ' + result.fileSize + ' bytes', 'success');
                    setStatus('TEST PASSED - ' + result.fileSize + ' bytes recorded (H.264+Opus MP4)');
                } else {
                    log('TEST FAILED', 'error');
                    setStatus('TEST FAILED');
                }

                console.log('TEST_RESULT:' + JSON.stringify(result));
                window.testResult = result;

            } catch (e) {
                log('Error: ' + e.message, 'error');
                setStatus('ERROR: ' + e.message);
                console.log('TEST_RESULT:' + JSON.stringify({ success: false, error: e.message }));
                window.testResult = { success: false, error: e.message };
            }
        }

        async function waitForConnection() {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('Connection timeout')), 30000);

                const check = () => {
                    if (pc.connectionState === 'connected' || pc.iceConnectionState === 'connected') {
                        clearTimeout(timeout);
                        resolve();
                    } else if (pc.connectionState === 'failed' || pc.iceConnectionState === 'failed') {
                        clearTimeout(timeout);
                        reject(new Error('Connection failed'));
                    } else {
                        setTimeout(check, 100);
                    }
                };
                check();
            });
        }

        // Create animated canvas stream as fallback for Safari headless
        function createCanvasStream(width, height, frameRate) {
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            let frame = 0;

            function draw() {
                ctx.fillStyle = '#1a1a2e';
                ctx.fillRect(0, 0, width, height);
                const x = width/2 + Math.sin(frame * 0.05) * (width/4);
                const y = height/2 + Math.cos(frame * 0.03) * (height/4);
                ctx.beginPath();
                ctx.arc(x, y, 40, 0, Math.PI * 2);
                ctx.fillStyle = '#ff6b6b';
                ctx.fill();
                ctx.fillStyle = '#fff';
                ctx.font = '20px sans-serif';
                ctx.fillText('Canvas Stream - Frame ' + frame, 20, 30);
                frame++;
                requestAnimationFrame(draw);
            }
            draw();
            return canvas.captureStream(frameRate);
        }

        function detectBrowser() {
            const ua = navigator.userAgent;
            if (ua.includes('Firefox')) return 'firefox';
            if (ua.includes('Safari') && !ua.includes('Chrome')) return 'safari';
            if (ua.includes('Chrome')) return 'chrome';
            return 'unknown';
        }

        // Auto-start test
        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = SaveToDiskMp4AvServer(recordingDurationSeconds: 5);
  await server.start(port: 8772);
}
