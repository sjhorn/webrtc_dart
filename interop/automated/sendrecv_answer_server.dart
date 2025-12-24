// Sendrecv Answer Server for Automated Browser Testing
//
// This server tests Dart as ANSWERER for sendrecv media (browser is offerer):
// 1. Browser creates PeerConnection with sendrecv video track
// 2. Browser creates offer and sends to Dart
// 3. Dart creates answer with sendrecv video
// 4. Dart receives video from browser and echoes it back
//
// Pattern: Browser is OFFERER, Dart is ANSWERER
// This pattern may work with Firefox (which fails when Dart is offerer)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

class SendrecvAnswerServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  nonstandard.MediaStreamTrack? _sendTrack;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _packetsReceived = 0;
  int _packetsEchoed = 0;
  bool _trackReceived = false;
  bool _echoStarted = false;
  Timer? _testTimer;
  final int _testDurationSeconds;

  // Track all subscriptions for proper cleanup
  final List<StreamSubscription> _subscriptions = [];

  SendrecvAnswerServer({int testDurationSeconds = 5})
      : _testDurationSeconds = testDurationSeconds;

  Future<void> start({int port = 8777}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Sendrecv-Answer] Started on http://localhost:$port');

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
    print('[Sendrecv-Answer] ${request.method} $path');

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
      print('[Sendrecv-Answer] Error: $e');
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
    print(
        '[Sendrecv-Answer] Starting sendrecv answer test for: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _packetsReceived = 0;
    _packetsEchoed = 0;
    _trackReceived = false;
    _echoStarted = false;

    // Create peer connection
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[Sendrecv-Answer] PeerConnection created');

    // Create a nonstandard track for sending echoed video
    // This matches the WORKING pattern from media_sendrecv_server.dart
    _sendTrack = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);

    // Pre-create a transceiver with our send track BEFORE receiving the offer
    // With the MID matching fix, this transceiver will be matched by kind when
    // processing the browser's offer, and its MID updated to match.
    final transceiver = _pc!.addTransceiverWithTrack(
      _sendTrack!,
      direction: RtpTransceiverDirection.sendrecv,
    );
    print('[Sendrecv-Answer] Pre-created video transceiver with track (sendrecv), mid=${transceiver.mid}, ssrc=${transceiver.sender.rtpSession.localSsrc}');

    // Track connection state
    _subscriptions.add(_pc!.onConnectionStateChange.listen((state) {
      print('[Sendrecv-Answer] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    }));

    _subscriptions.add(_pc!.onIceConnectionStateChange.listen((state) {
      print('[Sendrecv-Answer] ICE state: $state');
    }));

    // Track ICE candidates
    _subscriptions.add(_pc!.onIceCandidate.listen((candidate) {
      print(
          '[Sendrecv-Answer] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    }));

    // Handle incoming tracks - echo RTP via writeRtp on our send track
    // This matches the WORKING pattern from media_sendrecv_server.dart
    _subscriptions.add(_pc!.onTrack.listen((transceiver) {
      print('[Sendrecv-Answer] onTrack fired: kind=${transceiver.kind}, mid=${transceiver.mid}, '
          'ssrc=${transceiver.sender.rtpSession.localSsrc}, direction=${transceiver.direction}');
      _trackReceived = true;

      if (transceiver.kind == MediaStreamTrackKind.video) {
        final receivedTrack = transceiver.receiver.track;

        print('[Sendrecv-Answer] Setting up echo via writeRtp');
        _echoStarted = true;

        // Echo RTP packets via writeRtp on our send track
        bool pliSent = false;
        _subscriptions.add(receivedTrack.onReceiveRtp.listen((rtpPacket) {
          _packetsReceived++;

          // Echo the RTP packet back to the browser via our send track
          if (_sendTrack != null) {
            _sendTrack!.writeRtp(rtpPacket);
            _packetsEchoed++;
          }

          // Send PLI after first RTP packet to request keyframe
          if (!pliSent) {
            pliSent = true;
            transceiver.sender.rtpSession.sendPli(rtpPacket.ssrc);
          }

          if (_packetsReceived % 100 == 0) {
            print('[Sendrecv-Answer] Received=$_packetsReceived, Echoed=$_packetsEchoed');
          }
        }));
      }
    }));

    // Stop test after duration
    _testTimer = Timer(Duration(seconds: _testDurationSeconds), () {
      print('[Sendrecv-Answer] Test duration reached');
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleOffer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final offer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[Sendrecv-Answer] Received offer from browser');
    await _pc!.setRemoteDescription(offer);

    // Create answer
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    print('[Sendrecv-Answer] Created answer');

    // Debug: Print answer SDP to see SSRC and header extensions
    final sdpLines = answer.sdp.split('\n');
    for (final line in sdpLines) {
      if (line.startsWith('a=ssrc:') ||
          line.startsWith('a=sendrecv') ||
          line.startsWith('a=extmap:') ||
          line.startsWith('m=video')) {
        print('[Sendrecv-Answer] SDP: $line');
      }
    }

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': answer.type,
      'sdp': answer.sdp,
    }));
    print('[Sendrecv-Answer] Sent answer to browser');
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
      print('[Sendrecv-Answer] Skipping empty ICE candidate');
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
      print('[Sendrecv-Answer] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[Sendrecv-Answer] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'trackReceived': _trackReceived,
      'packetsReceived': _packetsReceived,
      'packetsEchoed': _packetsEchoed,
      'echoStarted': _echoStarted,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _trackReceived &&
          _packetsReceived > 0 &&
          _echoStarted,
      'trackReceived': _trackReceived,
      'packetsReceived': _packetsReceived,
      'packetsEchoed': _packetsEchoed,
      'echoStarted': _echoStarted,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'pattern': 'Browser=Offerer, Dart=Answerer',
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
    _testTimer?.cancel();
    _testTimer = null;

    // Cancel all stream subscriptions to prevent interference between tests
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    _sendTrack?.stop();
    _sendTrack = null;

    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Sendrecv Answer Test (Echo)</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 150px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .pattern-badge { background: #f80; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .video-container { display: flex; gap: 20px; margin: 10px 0; }
        .video-box { text-align: center; }
        .video-box label { display: block; margin-bottom: 5px; color: #ff8; }
        video {
            width: 320px;
            height: 240px;
            background: #000;
            border: 2px solid #333;
        }
        #localVideo { border-color: #8af; }
        #remoteVideo { border-color: #8f8; }
        #videoInfo { color: #ff8; margin: 5px 0; }
    </style>
</head>
<body>
    <h1>WebRTC Sendrecv Answer Test <span class="pattern-badge">Browser=Offerer</span></h1>
    <p>Browser creates offer with sendrecv video, Dart answers and echoes video back.</p>
    <p>This tests the Dart-as-Answerer pattern for bidirectional media.</p>
    <div id="status">Status: Waiting to start...</div>
    <div class="video-container">
        <div class="video-box">
            <label>Local Camera</label>
            <video id="localVideo" autoPlay muted playsinline></video>
        </div>
        <div class="video-box">
            <label>Remote (Echo from Dart)</label>
            <video id="remoteVideo" autoPlay muted playsinline></video>
        </div>
    </div>
    <div id="videoInfo">Waiting for video...</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let localStream = null;
        let remoteFramesReceived = 0;
        let videoStartTime = null;
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

        function updateVideoInfo() {
            const localVideo = document.getElementById('localVideo');
            const remoteVideo = document.getElementById('remoteVideo');
            const info = document.getElementById('videoInfo');
            const parts = [];

            if (localVideo.videoWidth > 0) {
                parts.push('Local: ' + localVideo.videoWidth + 'x' + localVideo.videoHeight);
            }
            if (remoteVideo.videoWidth > 0) {
                parts.push('Remote: ' + remoteVideo.videoWidth + 'x' + remoteVideo.videoHeight);
            }
            parts.push('Echo frames: ' + remoteFramesReceived);

            if (videoStartTime) {
                const elapsed = ((Date.now() - videoStartTime) / 1000).toFixed(1);
                parts.push('Time: ' + elapsed + 's');
            }

            info.textContent = parts.join(' | ');
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting sendrecv answer test for ' + browser);

                // Get camera access
                setStatus('Getting camera access...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        video: { width: 640, height: 480 },
                        audio: false
                    });
                    log('Got camera stream');
                    document.getElementById('localVideo').srcObject = localStream;
                } catch (e) {
                    throw new Error('Failed to get camera: ' + e.message);
                }

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (Dart as Answerer)');

                // Create browser peer connection (we are the offerer!)
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

                // Handle incoming video track (echoed from Dart)
                pc.ontrack = (e) => {
                    log('Received remote track: ' + e.track.kind, 'success');
                    const remoteVideo = document.getElementById('remoteVideo');
                    if (!remoteVideo.srcObject) {
                        remoteVideo.srcObject = new MediaStream();
                    }
                    remoteVideo.srcObject.addTrack(e.track);
                    videoStartTime = Date.now();

                    // Count frames
                    if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
                        const countFrame = () => {
                            remoteFramesReceived++;
                            updateVideoInfo();
                            remoteVideo.requestVideoFrameCallback(countFrame);
                        };
                        remoteVideo.requestVideoFrameCallback(countFrame);
                    } else {
                        setInterval(updateVideoInfo, 100);
                    }
                };

                // Add video track with sendrecv
                const videoTrack = localStream.getVideoTracks()[0];
                pc.addTransceiver(videoTrack, { direction: 'sendrecv' });
                log('Added video transceiver (sendrecv)');

                // Create offer (browser is offerer!)
                setStatus('Creating offer...');
                const offer = await pc.createOffer();
                await pc.setLocalDescription(offer);
                log('Created offer, local description set');

                // Wait for ICE gathering
                await new Promise(resolve => setTimeout(resolve, 500));

                // Send offer to Dart and get answer
                setStatus('Sending offer to Dart, getting answer...');
                const answerResp = await fetch(serverBase + '/offer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: offer.type, sdp: pc.localDescription.sdp })
                });
                const answer = await answerResp.json();
                log('Received answer from Dart');

                // Set remote description (answer)
                await pc.setRemoteDescription(new RTCSessionDescription(answer));
                log('Remote description set (answer)');

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

                // Wait for echo video
                setStatus('Waiting for echo video from Dart...');
                try {
                    await waitForVideo();
                    log('Echo video playing!', 'success');
                } catch (e) {
                    log('No echo video received: ' + e.message, 'error');
                }

                // Let video echo for a few seconds
                setStatus('Receiving echo video (5 seconds)...');
                for (let i = 0; i < 6; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: recv=' + status.packetsReceived + ', echo=' + status.packetsEchoed);
                }

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();
                result.echoFramesReceived = remoteFramesReceived;
                result.success = result.success && remoteFramesReceived > 0;

                if (result.success) {
                    log('TEST PASSED! Echo working - ' + result.packetsReceived + ' packets recv, ' + remoteFramesReceived + ' echo frames', 'success');
                    setStatus('TEST PASSED - Echo working');
                } else {
                    log('TEST FAILED - recv=' + result.packetsReceived + ', frames=' + remoteFramesReceived, 'error');
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

        async function waitForVideo() {
            const video = document.getElementById('remoteVideo');
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('Remote video timeout')), 15000);

                const check = () => {
                    if (video.videoWidth > 0 && video.videoHeight > 0) {
                        clearTimeout(timeout);
                        resolve();
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
  final server = SendrecvAnswerServer(testDurationSeconds: 5);
  await server.start(port: 8777);
}
