/// Ring Video Streaming Automated Test Server
///
/// This server:
/// 1. Connects to Ring camera using bundlePolicy: disable
/// 2. Receives video via RTP/SRTP
/// 3. Forwards video to browser clients via WebRTC
/// 4. Serves test page that verifies video frames are received
///
/// Usage:
///   export RING_REFRESH_TOKEN="your_token"
///   cd example/ring && dart run ring_video_server.dart
///
/// Then run the Playwright test:
///   node interop/automated/ring_video_test.mjs
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:ring_client_api/ring_client_api.dart' as ring;
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

import 'peer.dart';

/// Debug flag: Enable verbose logging
/// To use: set environment variable RING_DEBUG=1
final bool _debug = Platform.environment['RING_DEBUG'] == '1';

/// Configure logging level for ring_client_api and webrtc_dart
void _configureLogging() {
  // Suppress all logging by default
  hierarchicalLoggingEnabled = true;
  Logger.root.level = _debug ? Level.ALL : Level.OFF;

  // Configure webrtc_dart logging via WebRtcLogging
  if (_debug) {
    WebRtcLogging.enable();
  } else {
    WebRtcLogging.disable();
  }

  // Clear any existing listeners
  Logger.root.clearListeners();

  // Only log if debug is enabled
  if (_debug) {
    Logger.root.onRecord.listen((record) {
      _realPrint('${record.level.name}: ${record.message}');
    });
  }
}

// Store reference to real print before zone override
final void Function(String) _realPrint = Zone.current.print;

/// Run main with filtered output
void _runWithFilteredOutput(void Function() body) {
  if (_debug) {
    // Debug mode: show all output
    body();
  } else {
    // Production mode: filter output to only show our messages
    runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          // Only show our messages (prefixed with [Server], [Ring], [Browser], [ERROR])
          if (line.startsWith('[Server]') ||
              line.startsWith('[Ring]') ||
              line.startsWith('[Browser') ||
              line.startsWith('[ERROR]')) {
            parent.print(zone, line);
          }
        },
      ),
    );
  }
}

/// Debug flag: Set to true to disable mid extension for testing
/// To use: set environment variable DISABLE_MID_EXT=1
final bool _disableMidExtension =
    Platform.environment['DISABLE_MID_EXT'] == '1';

/// Debug logging helper - only prints when RING_DEBUG=1
void _log(String message) {
  if (_debug) print(message);
}

/// Test state tracking
class RingTestState {
  bool ringConnected = false;
  bool ringReceivingVideo = false;
  int rtpPacketsReceived = 0;
  int markerBitsReceived = 0; // Count of packets with marker bit set
  DateTime? firstRtpPacketTime;
  final browserClients = <String, BrowserClient>{};
}

class BrowserClient {
  final String id;
  final RtcPeerConnection pc;
  final nonstandard.MediaStreamTrack videoTrack;
  final nonstandard.MediaStreamTrack audioTrack;
  RtpTransceiver? videoTransceiver;
  RtpTransceiver? audioTransceiver;
  bool connected = false;
  bool videoFlowing = false;
  bool audioFlowing = false;
  int videoPacketsSent = 0;
  int audioPacketsSent = 0;

  BrowserClient({
    required this.id,
    required this.pc,
    required this.videoTrack,
    required this.audioTrack,
  });
}

class RingVideoServer {
  HttpServer? _httpServer;
  HttpServer? _wsServer;
  ring.RingApi? _ringApi;
  ring.StreamingSession? _ringSession;
  CustomPeerConnection? _ringPc;
  final _state = RingTestState();
  StreamSubscription? _videoRtpSubscription;
  StreamSubscription? _audioRtpSubscription;

  Future<void> start(String refreshToken) async {
    // Apply debug settings
    if (_disableMidExtension) {
      RtpSender.debugDisableMidExtension = true;
      _log('[Server] Mid extension DISABLED');
    }

    // Start HTTP server for test page
    _httpServer = await HttpServer.bind('localhost', 8080);
    print('[Server] http://localhost:8080');

    // Start WebSocket server for WebRTC signaling
    _wsServer = await HttpServer.bind('localhost', 8888);

    // Connect to Ring camera
    print('[Server] Connecting to Ring...');
    await _connectToRing(refreshToken);

    // Handle HTTP requests (serves test page and status)
    _httpServer!.listen(_handleHttpRequest);

    // Handle WebSocket connections (browser clients)
    _wsServer!.listen(_handleWebSocketRequest);
  }

  Future<void> _connectToRing(String refreshToken) async {
    _ringApi = ring.RingApi(
      ring.RefreshTokenAuth(refreshToken: refreshToken),
      options: ring.RingApiOptions(debug: true),
    );

    final cameras = await _ringApi!.getCameras();
    if (cameras.isEmpty) {
      print('[ERROR] No Ring cameras found');
      exit(1);
    }

    // Use camera[1] if available, otherwise fall back to camera[0]
    // final camera = cameras.length > 1 ? cameras[1] : cameras[0];
    final camera = cameras[0];

    print('[Ring] Found camera: ${camera.name}');

    // Create custom peer connection for Ring (uses bundlePolicy: disable)
    _ringPc = CustomPeerConnection();

    // Subscribe to video RTP packets
    _videoRtpSubscription = _ringPc!.onVideoRtp.listen((rtp) {
      _state.rtpPacketsReceived++;
      if (rtp.marker) {
        _state.markerBitsReceived++;
      }

      // Debug: Log keyframe detection
      if (_debug && rtp.payload.isNotEmpty) {
        final nalHeader = rtp.payload[0];
        final nalType = nalHeader & 0x1F;
        if (nalType == 5 || nalType == 7 || nalType == 8) {
          _log(
              '[Ring] KEYFRAME NAL type=$nalType (${nalType == 5 ? "IDR" : nalType == 7 ? "SPS" : "PPS"})');
        }
        if (nalType == 28 && rtp.payload.length > 1) {
          final fuHeader = rtp.payload[1];
          final isStart = (fuHeader & 0x80) != 0;
          final innerType = fuHeader & 0x1F;
          if (innerType == 5 && isStart) {
            _log('[Ring] KEYFRAME FU-A START IDR fragment');
          }
        }
      }

      if (_state.firstRtpPacketTime == null) {
        _state.firstRtpPacketTime = DateTime.now();
        _state.ringReceivingVideo = true;
        print('[Ring] Receiving video');
      }

      // Forward RTP to each connected browser client's video track
      for (final client in _state.browserClients.values) {
        if (client.connected) {
          try {
            client.videoTrack.writeRtp(rtp);
            client.videoPacketsSent++;
            client.videoFlowing = true;
          } catch (e) {
            _log('[RingForward:${client.id}] Error writing RTP: $e');
          }
        }
      }
    });

    // Subscribe to audio RTP packets
    var audioPacketsReceived = 0;
    var audioLogged = false;
    _audioRtpSubscription = _ringPc!.onAudioRtp.listen((rtp) {
      audioPacketsReceived++;

      if (!audioLogged) {
        audioLogged = true;
        print('[Ring] Receiving audio');
      }

      // Forward audio RTP to each connected browser client's audio track
      for (final client in _state.browserClients.values) {
        if (client.connected) {
          try {
            client.audioTrack.writeRtp(rtp);
            client.audioPacketsSent++;
            client.audioFlowing = true;
          } catch (e) {
            _log('[RingAudio:${client.id}] Error writing RTP: $e');
          }
        }
      }
    });

    // Subscribe to connection state
    _ringPc!.onConnectionState.listen((state) {
      _log('[Ring] Connection state: $state');
      if (state == ring.ConnectionState.connected) {
        _state.ringConnected = true;
        print('[Ring] Connected');
      }
    });

    // Start live call
    _ringSession = await camera.startLiveCall(
      ring.StreamingConnectionOptions(createPeerConnection: () => _ringPc!),
    );

    // Activate camera speaker to enable audio from Ring
    _ringSession!.activateCameraSpeaker();
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/' || path == '/index.html') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_testPageHtml);
    } else if (path == '/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ringConnected': _state.ringConnected,
        'ringReceivingVideo': _state.ringReceivingVideo,
        'rtpPacketsReceived': _state.rtpPacketsReceived,
        'markerBitsReceived': _state.markerBitsReceived,
        'browserClients': _state.browserClients.length,
        'browserClientsConnected':
            _state.browserClients.values.where((c) => c.connected).length,
        'browserClientsReceivingVideo':
            _state.browserClients.values.where((c) => c.videoFlowing).length,
      }));
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found');
    }

    await request.response.close();
  }

  Future<void> _handleWebSocketRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final clientId = DateTime.now().millisecondsSinceEpoch.toString();
    _log('[Browser:$clientId] WebSocket connected');

    // Create peer connection for browser client
    final pc = RtcPeerConnection(
      RtcConfiguration(
        codecs: RtcCodecs(
          audio: [
            createPcmuCodec(), // PCMU (G.711 μ-law) for Ring audio
          ],
          video: [
            createH264Codec(
              payloadType: 96,
              rtcpFeedback: [
                const RtcpFeedback(type: 'transport-cc'),
                const RtcpFeedback(type: 'ccm', parameter: 'fir'),
                const RtcpFeedback(type: 'nack'),
                const RtcpFeedback(type: 'nack', parameter: 'pli'),
                const RtcpFeedback(type: 'goog-remb'),
              ],
            ),
          ],
        ),
      ),
    );

    // Create video and audio tracks for this client
    final videoTrack = nonstandard.MediaStreamTrack(
      kind: nonstandard.MediaKind.video,
    );
    final audioTrack = nonstandard.MediaStreamTrack(
      kind: nonstandard.MediaKind.audio,
    );

    final client = BrowserClient(
      id: clientId,
      pc: pc,
      videoTrack: videoTrack,
      audioTrack: audioTrack,
    );
    _state.browserClients[clientId] = client;

    // Add audio track first, then video - order matters for BUNDLE!
    // (matching werift_ring_server.ts:399-400)
    client.audioTransceiver = pc.addTransceiverWithTrack(
      audioTrack,
      direction: RtpTransceiverDirection.sendonly,
    );

    // Add video track (sendonly to browser)
    client.videoTransceiver = pc.addTransceiverWithTrack(
      videoTrack,
      direction: RtpTransceiverDirection.sendonly,
    );

    // Track connection state
    pc.onConnectionStateChange.listen((state) {
      _log('[Browser:$clientId] Connection state: $state');
      if (state == PeerConnectionState.connected) {
        client.connected = true;
        print('[Browser] Connected');

        // Request keyframe from Ring when browser connects
        if (_ringPc != null) {
          _ringPc!.requestKeyFrame();
        }
      }
    });

    // Track ICE state for debugging
    pc.onIceConnectionStateChange.listen((state) {
      _log('[Browser:$clientId] ICE state: $state');
    });

    // Create and send offer
    await pc.setLocalDescription(await pc.createOffer());
    final offer = {
      'type': pc.localDescription!.type,
      'sdp': pc.localDescription!.sdp,
    };
    socket.add(jsonEncode(offer));
    _log('[Browser:$clientId] Sent offer');

    // Handle answer from browser
    socket.listen(
      (data) async {
        try {
          final answer = jsonDecode(data as String) as Map<String, dynamic>;
          if (answer['type'] == 'answer') {
            await pc.setRemoteDescription(
              SessionDescription(
                type: answer['type'] as String,
                sdp: answer['sdp'] as String,
              ),
            );
            _log('[Browser:$clientId] Received answer');
          }
        } catch (e) {
          print('[Browser:$clientId] Error: $e');
        }
      },
      onDone: () {
        _log('[Browser:$clientId] WebSocket closed');
        _state.browserClients.remove(clientId);
        pc.close();
      },
      onError: (e) {
        print('[Browser:$clientId] WebSocket error: $e');
        _state.browserClients.remove(clientId);
        pc.close();
      },
    );
  }

  Future<void> shutdown() async {
    _videoRtpSubscription?.cancel();
    _audioRtpSubscription?.cancel();
    _ringPc?.close();
    _ringSession?.stop();

    // Close browser clients
    for (final client in _state.browserClients.values) {
      client.pc.close();
    }
    _state.browserClients.clear();

    await _httpServer?.close();
    await _wsServer?.close();

    // Note: Don't call _ringApi.disconnect() - it triggers internal errors
    // when the connection is already being torn down by SIGINT.
    // The process is exiting anyway so cleanup happens automatically.
  }

  static const _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Ring Video + Audio Test (Dart)</title>
  <style>
    body { font-family: monospace; padding: 20px; background: #1a1a2e; color: #eee; }
    video { width: 640px; height: 480px; background: #000; border: 2px solid #333; }
    #log { height: 300px; overflow-y: auto; background: #0d0d1a; padding: 10px; margin-top: 20px; font-size: 12px; }
    .success { color: #4caf50; }
    .error { color: #f44336; }
    .info { color: #2196f3; }
    #status { font-size: 18px; margin-bottom: 20px; }
    #startBtn { padding: 10px 20px; font-size: 16px; margin-bottom: 20px; cursor: pointer; }
    #audioStatus { margin-left: 20px; }
  </style>
</head>
<body>
  <h1>Ring Video + Audio Test (Dart)</h1>
  <div id="status">Status: Initializing...</div>
  <button id="startBtn">Enable Audio</button>
  <span id="audioStatus"></span>
  <br><br>
  <video id="video" autoplay playsinline muted></video>
  <div id="log"></div>

  <script>
    let pc;
    let videoFrameCount = 0;
    let audioTrackReceived = false;
    let testStartTime = Date.now();

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

    function setAudioStatus(msg) {
      document.getElementById('audioStatus').textContent = msg;
    }

    document.getElementById('startBtn').onclick = () => {
      const video = document.getElementById('video');
      const btn = document.getElementById('startBtn');
      video.muted = !video.muted;
      video.play().then(() => {
        if (video.muted) {
          btn.textContent = 'Enable Audio';
          setAudioStatus('Audio muted');
        } else {
          btn.textContent = 'Mute Audio';
          setAudioStatus('Audio enabled');
        }
        log('Audio ' + (video.muted ? 'muted' : 'unmuted'), 'info');
      }).catch(e => log('Play failed: ' + e.message, 'error'));
    };

    async function runTest() {
      try {
        log('Starting Ring video test...');
        setStatus('Connecting to WebSocket...');

        // Connect to WebSocket
        const socket = new WebSocket('ws://localhost:8888');
        await new Promise((resolve, reject) => {
          socket.onopen = resolve;
          socket.onerror = reject;
          setTimeout(() => reject(new Error('WebSocket timeout')), 10000);
        });
        log('WebSocket connected', 'success');

        // Wait for offer from server
        setStatus('Waiting for offer...');
        const offer = await new Promise((resolve, reject) => {
          socket.onmessage = (e) => resolve(JSON.parse(e.data));
          setTimeout(() => reject(new Error('Offer timeout')), 30000);
        });
        log('Received offer from Dart server');

        // Create peer connection with STUN servers
        pc = new RTCPeerConnection({
          iceServers: [
            { urls: 'stun:stun.l.google.com:19302' },
            { urls: 'stun:stun1.l.google.com:19302' },
          ]
        });

        pc.oniceconnectionstatechange = () => {
          log('ICE state: ' + pc.iceConnectionState,
              pc.iceConnectionState === 'connected' ? 'success' : 'info');
        };

        pc.onconnectionstatechange = () => {
          log('Connection state: ' + pc.connectionState,
              pc.connectionState === 'connected' ? 'success' : 'info');
        };

        // Create a combined MediaStream to hold both audio and video tracks
        const combinedStream = new MediaStream();
        const video = document.getElementById('video');

        // Handle incoming tracks (video and audio)
        pc.ontrack = (e) => {
          log('Received track: ' + e.track.kind + ' (id=' + e.track.id + ')', 'success');

          if (e.track.kind === 'audio') {
            audioTrackReceived = true;
            setAudioStatus('Audio track received');
          }

          // Add track to our combined stream
          combinedStream.addTrack(e.track);
          log('Combined stream now has ' + combinedStream.getTracks().length + ' tracks', 'info');

          // Set srcObject to our combined stream
          video.srcObject = combinedStream;

          // Try to play (may fail due to autoplay policy)
          video.play().catch(e => {
            log('Autoplay blocked - click Enable Audio button', 'info');
          });

          // Monitor video frames
          if (e.track.kind === 'video' && video.requestVideoFrameCallback) {
            const countFrames = () => {
              videoFrameCount++;
              if (videoFrameCount % 30 === 0) {
                log('Video frames received: ' + videoFrameCount, 'info');
              }
              video.requestVideoFrameCallback(countFrames);
            };
            video.requestVideoFrameCallback(countFrames);
          }
        };

        // Log ICE events
        pc.onicecandidate = (e) => {
          if (e.candidate) {
            log('ICE candidate: ' + e.candidate.candidate.substr(0, 60) + '...');
          } else {
            log('ICE gathering complete');
          }
        };

        // Set remote description (offer)
        setStatus('Processing offer...');
        await pc.setRemoteDescription(new RTCSessionDescription(offer));
        log('Remote description set');

        // Create answer
        setStatus('Creating answer...');
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        log('Local description set (answer)');

        // Wait for ICE gathering to complete
        await new Promise((resolve) => {
          if (pc.iceGatheringState === 'complete') {
            resolve();
          } else {
            pc.onicegatheringstatechange = () => {
              log('ICE gathering state: ' + pc.iceGatheringState);
              if (pc.iceGatheringState === 'complete') {
                resolve();
              }
            };
          }
          setTimeout(resolve, 5000);
        });

        log('ICE gathering done, sending answer');
        socket.send(JSON.stringify(pc.localDescription));
        log('Sent answer to server');

        setStatus('Waiting for video...');

        // Wait for video frames (timeout after 30 seconds)
        const videoReceived = await new Promise((resolve) => {
          const startWait = Date.now();
          const check = () => {
            if (videoFrameCount > 0) {
              resolve(true);
            } else if (Date.now() - startWait > 30000) {
              resolve(false);
            } else {
              setTimeout(check, 100);
            }
          };
          check();
        });

        // Wait for more frames to confirm stable streaming
        if (videoReceived) {
          log('Video streaming detected, waiting for stability...');
          await new Promise(r => setTimeout(r, 5000));
        }

        // Report results
        const testDuration = Date.now() - testStartTime;
        const result = {
          success: videoFrameCount > 10,
          videoFrameCount,
          testDurationMs: testDuration,
          connectionState: pc.connectionState,
          iceConnectionState: pc.iceConnectionState,
        };

        if (result.success) {
          log('TEST PASSED - Received ' + videoFrameCount + ' video frames!', 'success');
          setStatus('TEST PASSED - ' + videoFrameCount + ' video frames');
        } else {
          log('TEST FAILED - Only received ' + videoFrameCount + ' video frames', 'error');
          setStatus('TEST FAILED');
        }

        // Report to Playwright
        console.log('TEST_RESULT:' + JSON.stringify(result));
        window.testResult = result;

      } catch (e) {
        log('Error: ' + e.message, 'error');
        setStatus('ERROR: ' + e.message);
        const result = { success: false, error: e.message, videoFrameCount };
        console.log('TEST_RESULT:' + JSON.stringify(result));
        window.testResult = result;
      }
    }

    // Start test when page loads
    window.addEventListener('load', () => {
      setTimeout(runTest, 500);
    });
  </script>
</body>
</html>
''';
}

/// Load refresh token from .env file or environment variable
String? _loadRefreshToken() {
  // First check environment variable
  var token = Platform.environment['RING_REFRESH_TOKEN'];
  if (token != null && token.isNotEmpty) {
    return token;
  }

  // Try to load from .env file in current directory
  final envFile = File('.env');
  if (envFile.existsSync()) {
    final contents = envFile.readAsStringSync();
    for (final line in contents.split('\n')) {
      if (line.startsWith('RING_REFRESH_TOKEN=')) {
        token = line.substring('RING_REFRESH_TOKEN='.length).trim();
        if (token.isNotEmpty) {
          return token;
        }
      }
    }
  }

  return null;
}

void main() {
  _configureLogging();

  _runWithFilteredOutput(() async {
    final refreshToken = _loadRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      print('[ERROR] Set RING_REFRESH_TOKEN in .env file');
      exit(1);
    }

    final server = RingVideoServer();

    // Handle shutdown gracefully
    ProcessSignal.sigint.watch().listen((_) async {
      await server.shutdown();
      exit(0);
    });

    await server.start(refreshToken);
    print('[Server] Ready');
  });
}
