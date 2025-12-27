// RED Audio Sendrecv (Echo) Server for Automated Browser Testing
//
// This server:
// 1. Creates PeerConnection with RED + Opus codecs
// 2. Receives audio from browser
// 3. Echoes audio back to browser via RTP forwarding
//
// Pattern: Dart is OFFERER (sendrecv), Browser is ANSWERER (sendrecv)
// Tests RED (RFC 2198) codec negotiation and audio echo

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

class RedSendrecvServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  nonstandard.MediaStreamTrack? _sendTrack;
  final List<Map<String, dynamic>> _localCandidates = [];
  final List<StreamSubscription> _subscriptions = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _packetsReceived = 0;
  int _packetsEchoed = 0;
  bool _echoStarted = false;
  final int _testDurationSeconds;
  Timer? _testTimer;

  RedSendrecvServer({int testDurationSeconds = 10})
      : _testDurationSeconds = testDurationSeconds;

  Future<void> start({int port = 8778}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[RED-Sendrecv] Started on http://localhost:$port');

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
    print('[RED-Sendrecv] ${request.method} $path');

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
      print('[RED-Sendrecv] Error: $e');
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
    print('[RED-Sendrecv] Starting RED audio echo test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _packetsReceived = 0;
    _packetsEchoed = 0;
    _echoStarted = false;

    // Create peer connection - RED + Opus codecs will be used
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[RED-Sendrecv] PeerConnection created');

    // Create nonstandard track for sending echoed audio
    _sendTrack = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.audio);

    // Add sendrecv audio transceiver with our send track
    final transceiver = _pc!.addTransceiverWithTrack(
      _sendTrack!,
      direction: RtpTransceiverDirection.sendrecv,
    );
    print('[RED-Sendrecv] Added audio transceiver (sendrecv), mid=${transceiver.mid}');

    _pc!.onConnectionStateChange.listen((state) {
      print('[RED-Sendrecv] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[RED-Sendrecv] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print('[RED-Sendrecv] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Handle incoming audio - echo via writeRtp
    _subscriptions.add(_pc!.onTrack.listen((transceiver) {
      print('[RED-Sendrecv] onTrack: kind=${transceiver.kind}, mid=${transceiver.mid}');

      if (transceiver.kind == MediaStreamTrackKind.audio) {
        final receivedTrack = transceiver.receiver.track;

        print('[RED-Sendrecv] Setting up audio echo via writeRtp');
        _echoStarted = true;

        // Echo RTP packets via writeRtp on our send track
        _subscriptions.add(receivedTrack.onReceiveRtp.listen((rtpPacket) {
          _packetsReceived++;

          // Echo the RTP packet back to the browser
          if (_sendTrack != null) {
            _sendTrack!.writeRtp(rtpPacket);
            _packetsEchoed++;
          }

          if (_packetsReceived % 50 == 0) {
            print('[RED-Sendrecv] Received=$_packetsReceived, Echoed=$_packetsEchoed');
          }
        }));
      }
    }));

    // Stop test after duration
    _testTimer = Timer(Duration(seconds: _testDurationSeconds), () {
      print('[RED-Sendrecv] Test duration reached');
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

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // Log RED codec in SDP
    final sdpLines = offer.sdp.split('\n');
    for (final line in sdpLines) {
      if (line.toLowerCase().contains('red') || line.contains('opus')) {
        print('[RED-Sendrecv] SDP: ${line.trim()}');
      }
    }

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[RED-Sendrecv] Sent offer to browser');
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

    print('[RED-Sendrecv] Received answer from browser');

    // Check if browser accepted RED
    if (answer.sdp.toLowerCase().contains('red')) {
      print('[RED-Sendrecv] Browser accepted RED codec');
    } else {
      print('[RED-Sendrecv] Browser using Opus (no RED)');
    }

    await _pc!.setRemoteDescription(answer);
    print('[RED-Sendrecv] Remote description set');

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
      print('[RED-Sendrecv] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[RED-Sendrecv] Failed to add candidate: $e');
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
          _packetsReceived > 0 &&
          _packetsEchoed > 0,
      'packetsReceived': _packetsReceived,
      'packetsEchoed': _packetsEchoed,
      'echoStarted': _echoStarted,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'RED/Opus',
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
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _pc?.close();
    _pc = null;
    _sendTrack = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC RED Audio Echo Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .codec-badge { background: #a08; color: #fff; padding: 2px 8px; border-radius: 4px; }
        audio { margin: 10px 0; }
    </style>
</head>
<body>
    <h1>WebRTC RED Audio Echo Test <span class="codec-badge">RED + Opus</span></h1>
    <p>Browser sends audio to Dart, Dart echoes back with RED codec support.</p>
    <div id="status">Status: Waiting to start...</div>
    <div>
        <audio id="remoteAudio" autoplay controls></audio>
    </div>
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
                setStatus('Starting RED audio echo test for ' + browser);

                // Get microphone audio
                setStatus('Getting microphone access...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        audio: true,
                        video: false
                    });
                    log('Got microphone stream');
                } catch (e) {
                    throw new Error('Failed to get microphone: ' + e.message);
                }

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (RED/Opus)');

                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

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

                // Handle incoming echo audio
                let echoFrames = 0;
                pc.ontrack = (e) => {
                    log('Received remote track: ' + e.track.kind, 'success');
                    document.getElementById('remoteAudio').srcObject = e.streams[0];

                    // Count echo by checking if audio is playing
                    const checkAudio = setInterval(() => {
                        const audio = document.getElementById('remoteAudio');
                        if (audio && !audio.paused && audio.currentTime > 0) {
                            echoFrames++;
                        }
                    }, 100);

                    setTimeout(() => clearInterval(checkAudio), 10000);
                };

                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                // Check for RED in offer
                if (offer.sdp.toLowerCase().includes('red')) {
                    log('RED codec found in offer', 'success');
                }
                if (offer.sdp.toLowerCase().includes('opus')) {
                    log('Opus codec found in offer', 'success');
                }

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // Add local audio track
                const audioTrack = localStream.getAudioTracks()[0];
                pc.addTrack(audioTrack, localStream);
                log('Added local audio track to send');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                // Check codec in answer
                if (answer.sdp.toLowerCase().includes('red')) {
                    log('RED codec in answer', 'success');
                } else {
                    log('Using Opus (RED not in answer)', 'info');
                }

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
                        log('Added Dart ICE candidate');
                    } catch (e) {
                        log('Failed to add candidate: ' + e.message, 'error');
                    }
                }

                setStatus('Waiting for connection...');
                await waitForConnection();
                log('Connection established!', 'success');

                setStatus('Sending audio and receiving echo...');

                // Wait and poll status
                for (let i = 0; i < 8; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: recv=' + status.packetsReceived + ', echo=' + status.packetsEchoed);
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! Echo working - ' + result.packetsReceived + ' packets recv, ' + result.packetsEchoed + ' echoed', 'success');
                    setStatus('TEST PASSED - Audio echo working');
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

        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = RedSendrecvServer(testDurationSeconds: 10);
  await server.start(port: 8778);
}
