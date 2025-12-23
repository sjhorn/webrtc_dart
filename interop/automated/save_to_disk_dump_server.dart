// Save to Disk RTP Dump Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send camera video + microphone audio
// 2. Creates a PeerConnection to receive media from browser
// 3. Dumps raw RTP packets to binary files for analysis
// 4. Stops recording after a configurable duration
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)
// Output: Binary files with raw RTP packets

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:webrtc_dart/webrtc_dart.dart';

class SaveToDiskDumpServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _videoPacketsReceived = 0;
  int _audioPacketsReceived = 0;
  String? _videoOutputPath;
  String? _audioOutputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;

  // Output files
  RandomAccessFile? _videoFile;
  RandomAccessFile? _audioFile;
  int _videoBytes = 0;
  int _audioBytes = 0;
  bool _stopped = false;

  SaveToDiskDumpServer({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8774}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SaveToDisk-Dump] Started on http://localhost:$port');

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
    print('[SaveToDisk-Dump] ${request.method} $path');

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
      print('[SaveToDisk-Dump] Error: $e');
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
    print('[SaveToDisk-Dump] Starting RTP dump test for: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _videoPacketsReceived = 0;
    _audioPacketsReceived = 0;
    _videoBytes = 0;
    _audioBytes = 0;
    _stopped = false;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _videoOutputPath = './dump-video-$timestamp.rtp';
    _audioOutputPath = './dump-audio-$timestamp.rtp';

    // Open output files
    _videoFile = await File(_videoOutputPath!).open(mode: FileMode.write);
    _audioFile = await File(_audioOutputPath!).open(mode: FileMode.write);
    print('[SaveToDisk-Dump] Output files opened');

    // Create peer connection
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[SaveToDisk-Dump] PeerConnection created');

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[SaveToDisk-Dump] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SaveToDisk-Dump] ICE state: $state');
    });

    // Track ICE candidates
    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[SaveToDisk-Dump] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
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
    print('[SaveToDisk-Dump] Added video transceiver (recvonly)');

    // Add recvonly audio transceiver
    _pc!.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-Dump] Added audio transceiver (recvonly)');

    // Handle incoming tracks
    _pc!.onTrack.listen((transceiver) async {
      print('[SaveToDisk-Dump] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      if (transceiver.kind == MediaStreamTrackKind.video) {
        // Listen for video RTP packets
        track.onReceiveRtp.listen((rtp) {
          if (_stopped) return;
          _videoPacketsReceived++;
          _writeVideoPacket(rtp);

          if (_videoPacketsReceived % 100 == 0) {
            print(
                '[SaveToDisk-Dump] Video: $_videoPacketsReceived packets, $_videoBytes bytes');
          }
        });
      } else if (transceiver.kind == MediaStreamTrackKind.audio) {
        // Listen for audio RTP packets
        track.onReceiveRtp.listen((rtp) {
          if (_stopped) return;
          _audioPacketsReceived++;
          _writeAudioPacket(rtp);

          if (_audioPacketsReceived % 100 == 0) {
            print(
                '[SaveToDisk-Dump] Audio: $_audioPacketsReceived packets, $_audioBytes bytes');
          }
        });
      }
    });

    print('[SaveToDisk-Dump] Dumping to: $_videoOutputPath, $_audioOutputPath');

    // Stop recording after duration
    _recordingTimer =
        Timer(Duration(seconds: _recordingDurationSeconds), () async {
      print('[SaveToDisk-Dump] Recording duration reached, stopping...');
      await _stopRecording();
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  void _writeVideoPacket(RtpPacket rtp) {
    if (_videoFile == null || _stopped) return;

    // Write packet length (4 bytes) + raw RTP data
    final serialized = rtp.serialize();
    final lengthBytes = Uint8List(4);
    final view = ByteData.view(lengthBytes.buffer);
    view.setUint32(0, serialized.length, Endian.big);

    _videoFile!.writeFromSync(lengthBytes);
    _videoFile!.writeFromSync(serialized);
    _videoBytes += 4 + serialized.length;
  }

  void _writeAudioPacket(RtpPacket rtp) {
    if (_audioFile == null || _stopped) return;

    // Write packet length (4 bytes) + raw RTP data
    final serialized = rtp.serialize();
    final lengthBytes = Uint8List(4);
    final view = ByteData.view(lengthBytes.buffer);
    view.setUint32(0, serialized.length, Endian.big);

    _audioFile!.writeFromSync(lengthBytes);
    _audioFile!.writeFromSync(serialized);
    _audioBytes += 4 + serialized.length;
  }

  Future<void> _stopRecording() async {
    if (_stopped) return;

    print('[SaveToDisk-Dump] Stopping recording...');
    _stopped = true;

    await _videoFile?.close();
    await _audioFile?.close();
    _videoFile = null;
    _audioFile = null;

    print('[SaveToDisk-Dump] Video output: $_videoOutputPath ($_videoBytes bytes)');
    print('[SaveToDisk-Dump] Audio output: $_audioOutputPath ($_audioBytes bytes)');
    print('[SaveToDisk-Dump] Recording stopped');
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
    print('[SaveToDisk-Dump] Created offer, local description set');

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[SaveToDisk-Dump] Sent offer to browser');
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final answer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[SaveToDisk-Dump] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[SaveToDisk-Dump] Remote description set');

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
      print('[SaveToDisk-Dump] Skipping empty ICE candidate');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      return;
    }

    if (candidateStr.startsWith('candidate:')) {
      candidateStr = candidateStr.substring('candidate:'.length);
    }

    try {
      final candidate = Candidate.fromSdp(candidateStr);
      await _pc!.addIceCandidate(candidate);
      print('[SaveToDisk-Dump] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[SaveToDisk-Dump] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    int? videoFileSize;
    int? audioFileSize;
    if (_videoOutputPath != null) {
      final file = File(_videoOutputPath!);
      if (await file.exists()) {
        videoFileSize = await file.length();
      }
    }
    if (_audioOutputPath != null) {
      final file = File(_audioOutputPath!);
      if (await file.exists()) {
        audioFileSize = await file.length();
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'videoPacketsReceived': _videoPacketsReceived,
      'audioPacketsReceived': _audioPacketsReceived,
      'videoBytes': _videoBytes,
      'audioBytes': _audioBytes,
      'videoFileSize': videoFileSize,
      'audioFileSize': audioFileSize,
      'format': 'Raw RTP',
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    // Stop recording if still running
    await _stopRecording();

    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    // Check output files
    int videoFileSize = 0;
    int audioFileSize = 0;
    bool filesCreated = false;

    if (_videoOutputPath != null) {
      final file = File(_videoOutputPath!);
      if (await file.exists()) {
        videoFileSize = await file.length();
      }
    }
    if (_audioOutputPath != null) {
      final file = File(_audioOutputPath!);
      if (await file.exists()) {
        audioFileSize = await file.length();
      }
    }
    filesCreated = videoFileSize > 0 && audioFileSize > 0;

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _videoPacketsReceived > 0 &&
          _audioPacketsReceived > 0 &&
          filesCreated,
      'videoPacketsReceived': _videoPacketsReceived,
      'audioPacketsReceived': _audioPacketsReceived,
      'videoFileSize': videoFileSize,
      'audioFileSize': audioFileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'format': 'Raw RTP',
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
    <title>WebRTC Save to Disk RTP Dump Test</title>
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
        #mediaInfo { color: #ff8; margin: 5px 0; }
        .format-badge { background: #f80; color: #fff; padding: 2px 8px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>WebRTC RTP Dump Test <span class="format-badge">Raw RTP</span></h1>
    <p>Browser sends video + audio to Dart, which dumps raw RTP packets to files.</p>
    <div id="status">Status: Waiting to start...</div>
    <video id="localVideo" autoPlay muted playsinline></video>
    <div id="mediaInfo">Waiting for camera/microphone...</div>
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
                setStatus('Starting RTP dump test for ' + browser);

                // Get camera + microphone
                setStatus('Getting camera and microphone access...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        video: { width: 640, height: 480 },
                        audio: true
                    });
                    log('Got camera + microphone stream');
                    const localVideo = document.getElementById('localVideo');
                    localVideo.srcObject = localStream;
                    document.getElementById('mediaInfo').textContent =
                        'Camera: ' + localStream.getVideoTracks()[0].label +
                        ', Mic: ' + localStream.getAudioTracks()[0].label;
                } catch (e) {
                    throw new Error('Failed to get media: ' + e.message);
                }

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (Raw RTP dump)');

                // Create browser peer connection
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

                // Set remote description
                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // Add video and audio tracks
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
                setStatus('Dumping RTP packets (5 seconds)...');
                log('Sending video + audio for RTP dump...');

                // Poll status
                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: Video=' + status.videoPacketsReceived + ' pkts (' +
                        (status.videoFileSize || 0) + ' bytes), Audio=' +
                        status.audioPacketsReceived + ' pkts (' +
                        (status.audioFileSize || 0) + ' bytes)');
                }

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! RTP dump files created: video=' +
                        result.videoFileSize + ' bytes, audio=' +
                        result.audioFileSize + ' bytes', 'success');
                    setStatus('TEST PASSED - RTP dump complete');
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
  final server = SaveToDiskDumpServer(recordingDurationSeconds: 5);
  await server.start(port: 8774);
}
