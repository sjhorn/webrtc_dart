// Simulcast Browser Test Server
//
// This server demonstrates simulcast functionality:
// 1. Configures transceiver for simulcast receive (high, mid, low layers)
// 2. Negotiates simulcast in SDP (rid, simulcast attributes)
// 3. Tracks packets by RID header extension
//
// Simulcast allows sending/receiving multiple encoding layers of the same
// video track at different qualities (bitrates, resolutions, frame rates).
//
// Pattern: Dart is OFFERER (recvonly with simulcast), Browser is ANSWERER (sendonly)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

class SimulcastServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  RtpTransceiver? _transceiver;
  MediaRecorder? _recorder;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsReceived = 0;
  String? _outputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;
  bool _simulcastNegotiated = false;
  String? _simulcastSdpInfo;
  final Map<String, int> _ridCounts = {};

  SimulcastServer({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8780}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Simulcast] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
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
    print('[Simulcast] ${request.method} $path');

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
      print('[Simulcast] Error: $e');
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
    print('[Simulcast] Starting test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _simulcastNegotiated = false;
    _simulcastSdpInfo = null;
    _ridCounts.clear();
    _outputPath =
        './recording-simulcast-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Create peer connection with simulcast support
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
      codecs: RtcCodecs(
        video: [
          createVp8Codec(
            payloadType: 96,
            rtcpFeedback: [
              RtcpFeedbackTypes.nack,
              RtcpFeedbackTypes.pli,
              RtcpFeedbackTypes.remb,
            ],
          ),
        ],
      ),
    ));
    print('[Simulcast] PeerConnection created with VP8');

    _pc!.onConnectionStateChange.listen((state) {
      print('[Simulcast] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[Simulcast] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[Simulcast] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Add recvonly video transceiver with simulcast support
    _transceiver = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    // Add simulcast layers for receiving
    _transceiver!.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'high', direction: SimulcastDirection.recv),
    );
    _transceiver!.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'mid', direction: SimulcastDirection.recv),
    );
    _transceiver!.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'low', direction: SimulcastDirection.recv),
    );
    print('[Simulcast] Added video transceiver (recvonly with simulcast)');

    _pc!.onTrack.listen((transceiver) async {
      print('[Simulcast] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      // Check if track has RID (simulcast layer)
      if (track.rid != null) {
        print('[Simulcast] Track RID: ${track.rid}');
      }

      final recordingTrack = RecordingTrack(
        kind: 'video',
        codecName: 'VP8',
        payloadType: 96,
        clockRate: 90000,
        onRtp: (handler) {
          track.onReceiveRtp.listen((rtp) {
            _rtpPacketsReceived++;

            // Track packets by RID if available
            final rid = track.rid ?? 'default';
            _ridCounts[rid] = (_ridCounts[rid] ?? 0) + 1;

            handler(rtp);
            if (_rtpPacketsReceived % 100 == 0) {
              print('[Simulcast] Received $_rtpPacketsReceived RTP packets');
              print('[Simulcast] RID counts: $_ridCounts');
            }
          });
        },
      );

      _recorder = MediaRecorder(
        tracks: [recordingTrack],
        path: _outputPath,
        options: MediaRecorderOptions(
          width: 640,
          height: 480,
          disableLipSync: true,
          disableNtp: true,
        ),
      );

      await _recorder!.start();
      print('[Simulcast] Recording started to: $_outputPath');

      _recordingTimer =
          Timer(Duration(seconds: _recordingDurationSeconds), () async {
        print('[Simulcast] Recording duration reached, stopping...');
        await _stopRecording();
      });
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _stopRecording() async {
    if (_recorder == null) return;

    print('[Simulcast] Stopping recorder...');
    await _recorder!.stop();
    _recorder = null;
    print('[Simulcast] Recording stopped');

    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('[Simulcast] Output file: $_outputPath ($size bytes)');
      } else {
        print('[Simulcast] WARNING: Output file not created!');
      }
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[Simulcast] Created offer, local description set');

    // Check simulcast in SDP
    final sdp = offer.sdp;
    _simulcastSdpInfo = _extractSimulcastInfo(sdp);
    if (_simulcastSdpInfo != null) {
      print('[Simulcast] Simulcast features in offer:');
      print(_simulcastSdpInfo);
      _simulcastNegotiated = true;
    }

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[Simulcast] Sent offer to browser');
  }

  String? _extractSimulcastInfo(String sdp) {
    final lines = <String>[];
    for (final line in sdp.split('\n')) {
      if (line.contains('a=rid') ||
          line.contains('a=simulcast') ||
          line.contains('rtp-stream-id')) {
        lines.add(line.trim());
      }
    }
    if (lines.isEmpty) return null;
    return lines.join('\n');
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

    print('[Simulcast] Received answer from browser');

    // Check simulcast in answer
    final answerSimulcastInfo = _extractSimulcastInfo(answer.sdp);
    if (answerSimulcastInfo != null) {
      print('[Simulcast] Simulcast in answer:');
      print(answerSimulcastInfo);
    }

    await _pc!.setRemoteDescription(answer);
    print('[Simulcast] Remote description set');

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

    if (candidateStr.isEmpty || candidateStr.trim().isEmpty) {
      print('[Simulcast] Skipping empty ICE candidate');
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
      print('[Simulcast] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[Simulcast] Failed to add candidate: $e');
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
      'rtpPacketsReceived': _rtpPacketsReceived,
      'simulcastNegotiated': _simulcastNegotiated,
      'simulcastSdpInfo': _simulcastSdpInfo,
      'ridCounts': _ridCounts,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'recording': _recorder != null,
      'codec': 'VP8 + Simulcast',
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    await _stopRecording();

    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

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
          _rtpPacketsReceived > 0 &&
          fileCreated,
      'simulcastNegotiated': _simulcastNegotiated,
      'packetsReceived': _rtpPacketsReceived,
      'ridCounts': _ridCounts,
      'simulcastSdpInfo': _simulcastSdpInfo,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'VP8 + Simulcast',
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
    <title>WebRTC Simulcast Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 250px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .warn { color: #fa8; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        video { max-width: 320px; border: 1px solid #333; margin: 10px 0; }
        .codec-badge { background: #080; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .sim-badge { background: #808; color: #fff; padding: 2px 6px; border-radius: 4px; margin-left: 5px; font-size: 0.8em; }
        .stats { display: flex; gap: 20px; margin: 10px 0; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .sim-info { background: #222; padding: 10px; margin: 10px 0; border-left: 3px solid #808; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>Simulcast Test
        <span class="codec-badge">VP8</span>
        <span class="sim-badge">Simulcast</span>
    </h1>
    <p>Tests simulcast SDP negotiation (high/mid/low layers).</p>
    <div id="status">Status: Waiting to start...</div>
    <video id="preview" autoplay muted playsinline></video>
    <div class="stats">
        <div class="stat">Packets: <span id="packets" class="stat-value">0</span></div>
        <div class="stat">Simulcast: <span id="simulcast" class="stat-value">?</span></div>
    </div>
    <div id="sim-info" class="sim-info" style="display: none;"></div>
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
                setStatus('Starting simulcast test for ' + browser);

                // Get camera
                setStatus('Getting camera access...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        video: { width: 640, height: 480 },
                        audio: false
                    });
                    log('Got camera stream');
                    document.getElementById('preview').srcObject = localStream;
                } catch (e) {
                    throw new Error('Failed to get camera: ' + e.message);
                }

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (VP8 + Simulcast)');

                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
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

                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                // Check for simulcast in SDP
                if (offer.sdp.includes('a=rid')) {
                    log('RID attributes found in offer', 'success');
                }
                if (offer.sdp.includes('a=simulcast')) {
                    log('Simulcast attribute found in offer', 'success');
                }

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                const videoTrack = localStream.getVideoTracks()[0];
                pc.addTrack(videoTrack, localStream);
                log('Added local video track');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();

                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                await new Promise(resolve => setTimeout(resolve, 500));

                setStatus('Sending answer to Dart...');
                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

                setStatus('Exchanging ICE candidates...');
                await new Promise(resolve => setTimeout(resolve, 500));

                const candidatesResp = await fetch(serverBase + '/candidates');
                const dartCandidates = await candidatesResp.json();
                log('Received ' + dartCandidates.length + ' ICE candidates from Dart');

                for (const c of dartCandidates) {
                    try {
                        await pc.addIceCandidate(new RTCIceCandidate(c));
                    } catch (e) {
                        log('Failed to add candidate: ' + e.message, 'warn');
                    }
                }

                setStatus('Waiting for connection...');
                await waitForConnection();
                log('Connection established!', 'success');

                setStatus('Sending video (5 seconds)...');
                log('Sending video...');

                // Poll status
                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();

                    document.getElementById('packets').textContent = status.rtpPacketsReceived || 0;
                    document.getElementById('simulcast').textContent = status.simulcastNegotiated ? 'YES' : 'NO';
                    document.getElementById('simulcast').style.color = status.simulcastNegotiated ? '#8f8' : '#fa8';

                    if (status.simulcastSdpInfo) {
                        const simDiv = document.getElementById('sim-info');
                        simDiv.style.display = 'block';
                        simDiv.innerHTML = '<strong>Simulcast SDP Info:</strong><br><pre>' +
                            status.simulcastSdpInfo.replace(/\\n/g, '<br>') + '</pre>';
                    }

                    log('Packets: ' + (status.rtpPacketsReceived || 0) +
                        ', Simulcast: ' + (status.simulcastNegotiated ? 'YES' : 'NO') +
                        ', File: ' + (status.fileSize || 0) + ' bytes');
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! ' + result.fileSize + ' bytes recorded', 'success');
                    if (result.simulcastNegotiated) {
                        log('Simulcast SDP negotiated', 'success');
                    } else {
                        log('Note: Simulcast SDP not negotiated (browser may not support)', 'warn');
                    }
                    setStatus('TEST PASSED');
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

        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = SimulcastServer(recordingDurationSeconds: 5);
  await server.start(port: 8780);
}
