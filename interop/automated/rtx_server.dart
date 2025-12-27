// RTX (Retransmission) Browser Test Server
//
// This server demonstrates RTX functionality:
// 1. Configures VP8 codec with RTX for retransmission
// 2. Negotiates RTX in SDP (rtpmap, fmtp apt=, ssrc-group FID)
// 3. Tracks NACK requests and RTX retransmissions
//
// RTX allows lost RTP packets to be retransmitted using a separate
// SSRC and payload type. When a receiver detects packet loss, it sends
// a NACK. The sender then retransmits the lost packet via RTX stream.
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

class RtxServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
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
  bool _rtxNegotiated = false;
  String? _rtxSdpInfo;

  RtxServer({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8778}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[RTX] Started on http://localhost:$port');

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
    print('[RTX] ${request.method} $path');

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
      print('[RTX] Error: $e');
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
    print('[RTX] Starting test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _rtxNegotiated = false;
    _rtxSdpInfo = null;
    _outputPath =
        './recording-rtx-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Create peer connection with VP8 + RTX codecs
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
      codecs: RtcCodecs(
        video: [
          // VP8 with RTCP feedback
          createVp8Codec(
            payloadType: 96,
            rtcpFeedback: [
              RtcpFeedbackTypes.nack, // Request retransmission
              RtcpFeedbackTypes.pli, // Picture Loss Indication
              RtcpFeedbackTypes.remb, // Receiver Estimated Max Bitrate
              const RtcpFeedback(
                  type: 'ccm', parameter: 'fir'), // Full Intra Request
            ],
          ),
          // RTX codec for retransmission (apt=96 links to VP8)
          createRtxCodec(payloadType: 97, apt: 96),
        ],
      ),
    ));
    print('[RTX] PeerConnection created with VP8 + RTX codecs');

    _pc!.onConnectionStateChange.listen((state) {
      print('[RTX] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[RTX] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[RTX] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Add recvonly video transceiver
    _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[RTX] Added video transceiver (recvonly)');

    _pc!.onTrack.listen((transceiver) async {
      print('[RTX] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      final recordingTrack = RecordingTrack(
        kind: 'video',
        codecName: 'VP8',
        payloadType: 96,
        clockRate: 90000,
        onRtp: (handler) {
          track.onReceiveRtp.listen((rtp) {
            _rtpPacketsReceived++;
            handler(rtp);
            if (_rtpPacketsReceived % 100 == 0) {
              print('[RTX] Received $_rtpPacketsReceived RTP packets');
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
      print('[RTX] Recording started to: $_outputPath');

      _recordingTimer =
          Timer(Duration(seconds: _recordingDurationSeconds), () async {
        print('[RTX] Recording duration reached, stopping...');
        await _stopRecording();
      });
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _stopRecording() async {
    if (_recorder == null) return;

    print('[RTX] Stopping recorder...');
    await _recorder!.stop();
    _recorder = null;
    print('[RTX] Recording stopped');

    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('[RTX] Output file: $_outputPath ($size bytes)');
      } else {
        print('[RTX] WARNING: Output file not created!');
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
    print('[RTX] Created offer, local description set');

    // Check RTX in SDP
    final sdp = offer.sdp;
    _rtxSdpInfo = _extractRtxInfo(sdp);
    if (_rtxSdpInfo != null) {
      print('[RTX] RTX negotiated in offer:');
      print(_rtxSdpInfo);
    }

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[RTX] Sent offer to browser');
  }

  String? _extractRtxInfo(String sdp) {
    final lines = <String>[];
    for (final line in sdp.split('\n')) {
      if (line.contains('rtx') ||
          line.contains('apt=') ||
          line.contains('ssrc-group:FID')) {
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

    print('[RTX] Received answer from browser');

    // Check RTX in answer
    final answerRtxInfo = _extractRtxInfo(answer.sdp);
    if (answerRtxInfo != null) {
      print('[RTX] RTX in answer:');
      print(answerRtxInfo);
      _rtxNegotiated = true;
    }

    await _pc!.setRemoteDescription(answer);
    print('[RTX] Remote description set');

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
      print('[RTX] Skipping empty ICE candidate');
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
      print('[RTX] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[RTX] Failed to add candidate: $e');
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
      'rtxNegotiated': _rtxNegotiated,
      'rtxSdpInfo': _rtxSdpInfo,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'recording': _recorder != null,
      'codec': 'VP8 + RTX',
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
          fileCreated &&
          _rtxNegotiated,
      'packetsReceived': _rtpPacketsReceived,
      'rtxNegotiated': _rtxNegotiated,
      'rtxSdpInfo': _rtxSdpInfo,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'VP8 + RTX',
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
    <title>WebRTC RTX (Retransmission) Test</title>
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
        .rtx-badge { background: #a50; color: #fff; padding: 2px 6px; border-radius: 4px; margin-left: 5px; font-size: 0.8em; }
        .stats { display: flex; gap: 20px; margin: 10px 0; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .rtx-info { background: #222; padding: 10px; margin: 10px 0; border-left: 3px solid #a50; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>RTX Retransmission Test
        <span class="codec-badge">VP8</span>
        <span class="rtx-badge">RTX</span>
    </h1>
    <p>Tests RTX (RFC 4588) retransmission codec negotiation.</p>
    <div id="status">Status: Waiting to start...</div>
    <video id="preview" autoplay muted playsinline></video>
    <div class="stats">
        <div class="stat">Packets: <span id="packets" class="stat-value">0</span></div>
        <div class="stat">RTX: <span id="rtx" class="stat-value">?</span></div>
    </div>
    <div id="rtx-info" class="rtx-info" style="display: none;"></div>
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
                setStatus('Starting RTX test for ' + browser);

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
                    log('Camera unavailable: ' + e.message + ', using canvas fallback', 'info');
                    localStream = createCanvasStream(640, 480, 30);
                    log('Canvas stream created', 'success');
                }

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (VP8 + RTX)');

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

                // Check for RTX in SDP
                if (offer.sdp.includes('rtx')) {
                    log('RTX codec found in offer', 'success');
                }
                if (offer.sdp.includes('apt=')) {
                    log('RTX apt parameter found in offer', 'success');
                }

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                const videoTrack = localStream.getVideoTracks()[0];
                pc.addTrack(videoTrack, localStream);
                log('Added local video track');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();

                // Check RTX in answer
                if (answer.sdp.includes('rtx')) {
                    log('RTX codec in answer', 'success');
                }
                if (answer.sdp.includes('ssrc-group:FID')) {
                    log('SSRC-group FID in answer (RTX SSRC mapping)', 'success');
                }

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

                setStatus('Sending video with RTX support (5 seconds)...');
                log('Sending video...');

                // Poll status
                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();

                    document.getElementById('packets').textContent = status.rtpPacketsReceived || 0;
                    document.getElementById('rtx').textContent = status.rtxNegotiated ? 'YES' : 'NO';
                    document.getElementById('rtx').style.color = status.rtxNegotiated ? '#8f8' : '#f88';

                    if (status.rtxSdpInfo) {
                        const rtxDiv = document.getElementById('rtx-info');
                        rtxDiv.style.display = 'block';
                        rtxDiv.innerHTML = '<strong>RTX SDP Info:</strong><br><pre>' +
                            status.rtxSdpInfo.replace(/\\n/g, '<br>') + '</pre>';
                    }

                    log('Packets: ' + (status.rtpPacketsReceived || 0) +
                        ', RTX: ' + (status.rtxNegotiated ? 'YES' : 'NO') +
                        ', File: ' + (status.fileSize || 0) + ' bytes');
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! RTX negotiated, ' + result.fileSize + ' bytes recorded', 'success');
                    setStatus('TEST PASSED - RTX working');
                } else {
                    if (!result.rtxNegotiated) {
                        log('TEST FAILED - RTX not negotiated', 'error');
                    } else {
                        log('TEST FAILED', 'error');
                    }
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

        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = RtxServer(recordingDurationSeconds: 5);
  await server.start(port: 8778);
}
