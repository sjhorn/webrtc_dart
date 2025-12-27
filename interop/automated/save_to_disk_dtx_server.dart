// Save to Disk DTX (Discontinuous Transmission) Server for Automated Browser Testing
//
// This server tests DTX handling for audio:
// 1. Serves static HTML for browser to send camera+microphone (VP8+Opus with DTX)
// 2. Creates a PeerConnection to receive both audio and video from browser
// 3. Uses DtxProcessor to detect and fill gaps in audio during silence
// 4. Records the streams to a WebM file using MediaRecorder
// 5. Tracks DTX statistics (silence frames inserted, etc.)
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)
// Output: WebM file with VP8 video + Opus audio (DTX enabled)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

class SaveToDiskDtxServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  MediaRecorder? _recorder;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _videoPacketsReceived = 0;
  int _audioPacketsReceived = 0;
  int _dtxFramesInserted = 0;
  int _speechFrames = 0;
  int _comfortNoiseFrames = 0;
  String? _outputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;
  bool _recorderStarted = false;
  int _tracksReceived = 0;

  // DTX processor for gap filling
  DtxProcessor? _dtxProcessor;
  DtxStateTracker? _dtxStateTracker;

  SaveToDiskDtxServer({int recordingDurationSeconds = 10})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8775}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SaveToDisk-DTX] Started on http://localhost:$port');

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
    print('[SaveToDisk-DTX] ${request.method} $path');

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
      print('[SaveToDisk-DTX] Error: $e');
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
    print('[SaveToDisk-DTX] Starting DTX test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _videoPacketsReceived = 0;
    _audioPacketsReceived = 0;
    _dtxFramesInserted = 0;
    _speechFrames = 0;
    _comfortNoiseFrames = 0;
    _recorderStarted = false;
    _tracksReceived = 0;
    _outputPath =
        './recording-dtx-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Initialize DTX processor for 20ms frames at 48kHz
    _dtxProcessor = DtxProcessor(ptime: 20, clockRate: 48000, enabled: true);
    _dtxStateTracker = DtxStateTracker();
    print('[SaveToDisk-DTX] DTX processor initialized (20ms @ 48kHz)');

    // Create peer connection with VP8 video and Opus audio (DTX enabled)
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[SaveToDisk-DTX] PeerConnection created');

    _pc!.onConnectionStateChange.listen((state) {
      print('[SaveToDisk-DTX] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SaveToDisk-DTX] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[SaveToDisk-DTX] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Add recvonly video transceiver (VP8)
    _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-DTX] Added video transceiver (recvonly)');

    // Add recvonly audio transceiver (Opus with DTX)
    _pc!.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-DTX] Added audio transceiver (recvonly, DTX enabled)');

    // Track recording setup
    final recordingTracks = <RecordingTrack>[];

    _pc!.onTrack.listen((transceiver) async {
      print('[SaveToDisk-DTX] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;
      _tracksReceived++;

      if (transceiver.kind == MediaStreamTrackKind.video) {
        recordingTracks.add(RecordingTrack(
          kind: 'video',
          codecName: 'VP8',
          payloadType: 96,
          clockRate: 90000,
          onRtp: (handler) {
            track.onReceiveRtp.listen((rtp) {
              _videoPacketsReceived++;
              handler(rtp);
              if (_videoPacketsReceived % 100 == 0) {
                print(
                    '[SaveToDisk-DTX] Video: $_videoPacketsReceived RTP packets');
              }
            });
          },
        ));
      } else if (transceiver.kind == MediaStreamTrackKind.audio) {
        recordingTracks.add(RecordingTrack(
          kind: 'audio',
          codecName: 'opus',
          payloadType: 111,
          clockRate: 48000,
          onRtp: (handler) {
            track.onReceiveRtp.listen((rtp) {
              _audioPacketsReceived++;

              // Process through DTX processor
              if (_dtxProcessor != null && _dtxStateTracker != null) {
                final frames =
                    _dtxProcessor!.processPacket(rtp.timestamp, rtp.payload);

                for (final frame in frames) {
                  _dtxStateTracker!.updateState(frame);

                  if (frame.isSilence) {
                    _dtxFramesInserted++;
                  } else if (frame.isComfortNoise) {
                    _comfortNoiseFrames++;
                  } else if (frame.isSpeech) {
                    _speechFrames++;
                  }
                }
              }

              handler(rtp);
              if (_audioPacketsReceived % 100 == 0) {
                print(
                    '[SaveToDisk-DTX] Audio: $_audioPacketsReceived RTP, DTX fill: $_dtxFramesInserted, speech: $_speechFrames');
              }
            });
          },
        ));
      }

      // Start recorder when we have both tracks
      if (_tracksReceived >= 2 && !_recorderStarted) {
        _recorderStarted = true;
        print('[SaveToDisk-DTX] Both tracks received, starting recorder...');

        _recorder = MediaRecorder(
          tracks: recordingTracks,
          path: _outputPath,
          options: MediaRecorderOptions(
            width: 640,
            height: 480,
            disableLipSync: false,
            disableNtp: true,
          ),
        );

        await _recorder!.start();
        print('[SaveToDisk-DTX] Recording started to: $_outputPath');

        _recordingTimer =
            Timer(Duration(seconds: _recordingDurationSeconds), () async {
          print('[SaveToDisk-DTX] Recording duration reached, stopping...');
          await _stopRecording();
        });
      }
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _stopRecording() async {
    if (_recorder == null) return;

    print('[SaveToDisk-DTX] Stopping recorder...');
    await _recorder!.stop();
    _recorder = null;
    print('[SaveToDisk-DTX] Recording stopped');

    // Log final DTX statistics
    print('[SaveToDisk-DTX] DTX Stats:');
    print('  - Audio packets received: $_audioPacketsReceived');
    print('  - Speech frames: $_speechFrames');
    print('  - Comfort noise frames: $_comfortNoiseFrames');
    print('  - DTX frames inserted: $_dtxFramesInserted');
    if (_dtxProcessor != null) {
      print('  - DTX processor fill count: ${_dtxProcessor!.fillCount}');
    }
    if (_dtxStateTracker != null) {
      print('  - DTX periods: ${_dtxStateTracker!.dtxPeriodCount}');
    }

    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('[SaveToDisk-DTX] Output file: $_outputPath ($size bytes)');
      } else {
        print('[SaveToDisk-DTX] WARNING: Output file not created!');
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

    // Modify SDP to request DTX (usedtx=1)
    var sdp = offer.sdp;
    // Add usedtx=1 to opus fmtp line if not present
    if (sdp.contains('a=rtpmap:111 opus/48000/2') &&
        !sdp.contains('usedtx=1')) {
      // Find opus fmtp line and add usedtx=1
      if (sdp.contains('a=fmtp:111')) {
        sdp = sdp.replaceFirst(
            RegExp(r'a=fmtp:111 ([^\r\n]+)'), r'a=fmtp:111 $1;usedtx=1');
      } else {
        // Add fmtp line after rtpmap
        sdp = sdp.replaceFirst(
            'a=rtpmap:111 opus/48000/2',
            'a=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10;useinbandfec=1;usedtx=1');
      }
      print('[SaveToDisk-DTX] Added usedtx=1 to SDP');
    }

    final modifiedOffer = SessionDescription(type: offer.type, sdp: sdp);
    await _pc!.setLocalDescription(modifiedOffer);
    print('[SaveToDisk-DTX] Created offer with DTX, local description set');

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': modifiedOffer.type,
      'sdp': modifiedOffer.sdp,
    }));
    print('[SaveToDisk-DTX] Sent offer to browser');
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

    print('[SaveToDisk-DTX] Received answer from browser');

    // Check if browser accepted DTX
    final sdp = answer.sdp;
    if (sdp.contains('usedtx=1')) {
      print('[SaveToDisk-DTX] Browser accepted DTX');
    } else {
      print('[SaveToDisk-DTX] Browser did not include usedtx in answer');
    }

    await _pc!.setRemoteDescription(answer);
    print('[SaveToDisk-DTX] Remote description set');

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
      print('[SaveToDisk-DTX] Skipping empty ICE candidate');
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
      print('[SaveToDisk-DTX] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[SaveToDisk-DTX] Failed to add candidate: $e');
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
      'speechFrames': _speechFrames,
      'comfortNoiseFrames': _comfortNoiseFrames,
      'dtxFramesInserted': _dtxFramesInserted,
      'dtxPeriods': _dtxStateTracker?.dtxPeriodCount ?? 0,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'recording': _recorder != null,
      'tracksReceived': _tracksReceived,
      'codec': 'VP8+Opus(DTX)',
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
          _videoPacketsReceived > 0 &&
          _audioPacketsReceived > 0 &&
          fileCreated,
      'videoPacketsReceived': _videoPacketsReceived,
      'audioPacketsReceived': _audioPacketsReceived,
      'speechFrames': _speechFrames,
      'comfortNoiseFrames': _comfortNoiseFrames,
      'dtxFramesInserted': _dtxFramesInserted,
      'dtxPeriods': _dtxStateTracker?.dtxPeriodCount ?? 0,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'VP8+Opus(DTX)',
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
    _dtxProcessor = null;
    _dtxStateTracker = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Save to Disk DTX Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .dtx { color: #fa8; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .codec-badge { background: #a80; color: #fff; padding: 2px 8px; border-radius: 4px; margin-left: 5px; }
        .dtx-badge { background: #0a8; }
        video { max-width: 320px; border: 1px solid #333; margin: 10px 0; }
        #meter { width: 200px; height: 20px; background: #333; margin: 10px 0; display: inline-block; }
        #meterBar { height: 100%; width: 0%; background: #0f0; transition: width 0.1s; }
        .media-info { display: flex; gap: 20px; align-items: center; }
        .dtx-info { margin: 10px 0; padding: 10px; background: #234; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>WebRTC DTX Test <span class="codec-badge">VP8</span><span class="codec-badge dtx-badge">Opus+DTX</span></h1>
    <p>Tests Discontinuous Transmission (DTX) - audio silence detection and gap filling.</p>
    <div class="dtx-info">
        <strong>DTX Info:</strong> DTX allows sending only during active speech.
        During silence, the browser may send smaller "comfort noise" packets or skip sending entirely.
        The Dart server detects gaps and fills them with silence frames for smooth playback.
    </div>
    <div id="status">Status: Waiting to start...</div>
    <div class="media-info">
        <div>
            <video id="preview" autoplay muted playsinline></video>
        </div>
        <div>
            <div>Audio Level:</div>
            <div id="meter"><div id="meterBar"></div></div>
            <div id="dtxStatus">DTX: --</div>
        </div>
    </div>
    <div id="log"></div>

    <script>
        let pc = null;
        let localStream = null;
        let audioContext = null;
        let analyser = null;
        let silenceCount = 0;
        let speechCount = 0;
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

        function updateMeter() {
            if (!analyser) return;
            const dataArray = new Uint8Array(analyser.frequencyBinCount);
            analyser.getByteFrequencyData(dataArray);
            const avg = dataArray.reduce((a, b) => a + b, 0) / dataArray.length;
            const level = Math.min(100, avg / 128 * 100);
            document.getElementById('meterBar').style.width = level + '%';

            // Track silence/speech for DTX monitoring
            if (level < 5) {
                silenceCount++;
            } else {
                speechCount++;
            }

            const total = silenceCount + speechCount;
            if (total > 0 && total % 50 === 0) {
                const silencePercent = Math.round(silenceCount / total * 100);
                document.getElementById('dtxStatus').textContent =
                    'DTX: ' + silencePercent + '% silence';
            }

            requestAnimationFrame(updateMeter);
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting DTX save_to_disk test for ' + browser);

                // Get camera and microphone
                setStatus('Getting camera and microphone access...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        video: { width: 640, height: 480 },
                        audio: true
                    });
                    log('Got camera + microphone stream');

                    // Show preview
                    document.getElementById('preview').srcObject = localStream;

                    // Set up audio meter
                    audioContext = new AudioContext();
                    const source = audioContext.createMediaStreamSource(localStream);
                    analyser = audioContext.createAnalyser();
                    analyser.fftSize = 256;
                    source.connect(analyser);
                    updateMeter();
                } catch (e) {
                    throw new Error('Failed to get media: ' + e.message);
                }

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (VP8+Opus with DTX)');

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

                setStatus('Getting offer from Dart (with DTX)...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                // Check if DTX is requested
                if (offer.sdp.includes('usedtx=1')) {
                    log('DTX requested in offer (usedtx=1)', 'dtx');
                }

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // Add both video and audio tracks
                const videoTrack = localStream.getVideoTracks()[0];
                const audioTrack = localStream.getAudioTracks()[0];
                pc.addTrack(videoTrack, localStream);
                pc.addTrack(audioTrack, localStream);
                log('Added local video + audio tracks');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                // Check if DTX is in answer
                if (answer.sdp.includes('usedtx=1')) {
                    log('DTX accepted in answer (usedtx=1)', 'dtx');
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

                setStatus('Recording A/V with DTX (10 seconds)...');
                log('Sending video + audio (DTX enabled)...');

                for (let i = 0; i < 12; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: video=' + status.videoPacketsReceived +
                        ' audio=' + status.audioPacketsReceived +
                        ' speech=' + status.speechFrames +
                        ' dtx_fill=' + status.dtxFramesInserted);
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! DTX file created: ' + result.fileSize + ' bytes', 'success');
                    log('DTX stats: speech=' + result.speechFrames +
                        ', comfort_noise=' + result.comfortNoiseFrames +
                        ', dtx_filled=' + result.dtxFramesInserted, 'dtx');
                    setStatus('TEST PASSED - ' + result.fileSize + ' bytes (DTX: ' +
                        result.dtxFramesInserted + ' frames inserted)');
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
  final server = SaveToDiskDtxServer(recordingDurationSeconds: 10);
  await server.start(port: 8775);
}
