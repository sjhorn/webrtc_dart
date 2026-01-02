/// Simple RTP Forward Test Server
///
/// This server tests the nonstandard track writeRtp -> browser flow:
/// 1. Browser connects via WebSocket
/// 2. Server creates offer with sendonly video track using addTransceiverWithTrack
/// 3. Browser accepts and sends answer
/// 4. Server writes synthetic RTP packets to the track
/// 5. Test verifies browser receives the video track (connection + track event)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

class RtpForwardTestServer {
  HttpServer? _httpServer;
  HttpServer? _wsServer;
  RTCPeerConnection? _pc;
  nonstandard.MediaStreamTrack? _videoTrack;
  RTCRtpTransceiver? _transceiver;
  Timer? _rtpTimer;
  int _packetsSent = 0;
  bool _connected = false;
  bool _srtpReady = false;

  Future<void> start() async {
    // Start HTTP server for test page
    _httpServer = await HttpServer.bind('localhost', 8766);
    print('[Server] HTTP server on http://localhost:8766');

    // Start WebSocket server for signaling
    _wsServer = await HttpServer.bind('localhost', 8767);
    print('[Server] WebSocket server on ws://localhost:8767');

    _httpServer!.listen(_handleHttpRequest);
    _wsServer!.listen(_handleWebSocketRequest);
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/' || path == '/index.html') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_testPageHtml);
    } else if (path == '/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'connected': _connected,
        'srtpReady': _srtpReady,
        'packetsSent': _packetsSent,
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
    print('[Server] WebSocket connected');

    // Create peer connection with video codec
    _pc = RTCPeerConnection(
      RtcConfiguration(
        codecs: RtcCodecs(
          video: [
            createH264Codec(
              payloadType: 96,
              rtcpFeedback: [
                const RtcpFeedback(type: 'nack'),
                const RtcpFeedback(type: 'nack', parameter: 'pli'),
              ],
            ),
          ],
        ),
      ),
    );

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[Server] Connection state: $state');
      if (state == PeerConnectionState.connected) {
        _connected = true;
        _startSendingRtp();
      }
    });

    // Create nonstandard video track
    _videoTrack = nonstandard.MediaStreamTrack(
      kind: nonstandard.MediaKind.video,
    );
    print('[Server] Created nonstandard video track');

    // Add video track with sendonly direction
    _transceiver = _pc!.addTransceiver(
      _videoTrack!,
      direction: RtpTransceiverDirection.sendonly,
    );
    print('[Server] Added transceiver with track, mid=${_transceiver!.mid}');

    // Create and send offer
    await _pc!.setLocalDescription(await _pc!.createOffer());
    final offer = {
      'type': _pc!.localDescription!.type,
      'sdp': _pc!.localDescription!.sdp,
    };
    socket.add(jsonEncode(offer));
    print('[Server] Sent offer');

    // Handle answer from browser
    socket.listen(
      (data) async {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          if (msg['type'] == 'answer') {
            await _pc!.setRemoteDescription(
              RTCSessionDescription(
                type: msg['type'] as String,
                sdp: msg['sdp'] as String,
              ),
            );
            print('[Server] Set remote description (answer)');
          }
        } catch (e) {
          print('[Server] Error processing message: $e');
        }
      },
      onDone: () {
        print('[Server] WebSocket closed');
        _cleanup();
      },
      onError: (e) {
        print('[Server] WebSocket error: $e');
        _cleanup();
      },
    );
  }

  void _startSendingRtp() {
    print('[Server] Starting RTP packet generation');
    _srtpReady = true; // Assume SRTP is ready after connection

    // Send synthetic RTP packets at 30fps
    var sequenceNumber = 0;
    var timestamp = 0;
    const ssrc = 12345678;

    _rtpTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_videoTrack == null || _videoTrack!.stopped) {
        _rtpTimer?.cancel();
        return;
      }

      // Create a simple H.264 NAL unit (SPS placeholder)
      final payload = Uint8List.fromList([
        0x67, // NAL unit type 7 (SPS)
        0x42, 0xc0, 0x1e, // Profile/Level
        0x00, 0x00, 0x00, 0x01, // Start code (filler)
      ]);

      final rtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true, // End of frame
        payloadType: 96,
        sequenceNumber: sequenceNumber++ & 0xFFFF,
        timestamp: timestamp,
        ssrc: ssrc,
        csrcs: [],
        payload: payload,
      );

      try {
        _videoTrack!.writeRtp(rtp);
        _packetsSent++;

        if (_packetsSent <= 5 || _packetsSent % 100 == 0) {
          print(
              '[Server] Wrote RTP packet #$_packetsSent, seq=$sequenceNumber');
        }
      } catch (e) {
        print('[Server] Error writing RTP: $e');
      }

      timestamp += 3000; // ~30fps at 90kHz clock
    });
  }

  void _cleanup() {
    _rtpTimer?.cancel();
    _pc?.close();
    _videoTrack = null;
    _transceiver = null;
    _connected = false;
    _srtpReady = false;
    _packetsSent = 0;
  }

  Future<void> shutdown() async {
    _cleanup();
    await _httpServer?.close();
    await _wsServer?.close();
    print('[Server] Shutdown complete');
  }

  static const _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>RTP Forward Test</title>
  <style>
    body {
      font-family: monospace;
      padding: 20px;
      background: #1a1a1a;
      color: #eee;
    }
    h1 { color: #8af; }
    #video {
      width: 320px;
      height: 240px;
      background: #000;
      border: 2px solid #333;
    }
    #status {
      margin: 10px 0;
      padding: 10px;
      background: #333;
      border-radius: 4px;
    }
    #log {
      background: #0a0a0a;
      padding: 10px;
      height: 200px;
      overflow-y: auto;
      border: 1px solid #333;
      margin-top: 10px;
    }
    .info { color: #8af; }
    .success { color: #8f8; }
    .error { color: #f88; }
  </style>
</head>
<body>
  <h1>RTP Forward Test</h1>
  <video id="video" autoplay muted playsinline></video>
  <div id="status">Status: Initializing...</div>
  <div id="log"></div>

  <script>
    let pc = null;
    let trackReceived = false;

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
        log('Starting RTP forward test...');
        setStatus('Connecting to WebSocket...');

        // Connect to WebSocket
        const socket = new WebSocket('ws://localhost:8767');
        await new Promise((resolve, reject) => {
          socket.onopen = resolve;
          socket.onerror = reject;
          setTimeout(() => reject(new Error('WebSocket timeout')), 10000);
        });
        log('WebSocket connected', 'success');

        // Wait for offer from Dart server
        setStatus('Waiting for offer...');
        const offer = await new Promise((resolve, reject) => {
          socket.onmessage = (e) => resolve(JSON.parse(e.data));
          setTimeout(() => reject(new Error('Offer timeout')), 30000);
        });
        log('Received offer from Dart');

        // Create peer connection
        pc = new RTCPeerConnection({ iceServers: [] });

        pc.oniceconnectionstatechange = () => {
          log('ICE state: ' + pc.iceConnectionState,
              pc.iceConnectionState === 'connected' ? 'success' : 'info');
        };

        pc.onconnectionstatechange = () => {
          log('Connection state: ' + pc.connectionState,
              pc.connectionState === 'connected' ? 'success' : 'info');
        };

        // Handle incoming video track
        pc.ontrack = (e) => {
          log('Received track: ' + e.track.kind, 'success');
          trackReceived = true;
          const video = document.getElementById('video');
          video.srcObject = e.streams[0] || new MediaStream([e.track]);
        };

        // Set remote description (offer)
        setStatus('Processing offer...');
        await pc.setRemoteDescription(new RTCSessionDescription(offer));
        log('Remote description set');

        // Create and send answer
        setStatus('Creating answer...');
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        log('Local description set (answer)');

        // Send answer when ICE gathering completes
        pc.onicecandidate = (e) => {
          if (!e.candidate) {
            const sdp = JSON.stringify(pc.localDescription);
            socket.send(sdp);
            log('Sent answer to Dart');
          }
        };

        setStatus('Waiting for connection...');

        // Wait for connection (timeout after 30 seconds)
        const connected = await new Promise((resolve) => {
          const startWait = Date.now();
          const check = () => {
            if (pc.connectionState === 'connected') {
              resolve(true);
            } else if (Date.now() - startWait > 30000) {
              resolve(false);
            } else {
              setTimeout(check, 100);
            }
          };
          check();
        });

        if (!connected) {
          throw new Error('Connection timeout');
        }

        log('Connection established!', 'success');
        setStatus('Connected, waiting for track...');

        // Wait for track (with timeout)
        await new Promise(r => setTimeout(r, 5000));

        // Report results
        const result = {
          success: trackReceived && pc.connectionState === 'connected',
          trackReceived,
          connectionState: pc.connectionState,
          iceConnectionState: pc.iceConnectionState,
        };

        if (result.success) {
          log('TEST PASSED - Track received!', 'success');
          setStatus('TEST PASSED');
        } else {
          log('TEST FAILED - Track received: ' + trackReceived, 'error');
          setStatus('TEST FAILED');
        }

        console.log('TEST_RESULT:' + JSON.stringify(result));
        window.testResult = result;

      } catch (e) {
        log('Error: ' + e.message, 'error');
        setStatus('ERROR: ' + e.message);
        const result = { success: false, error: e.message, trackReceived };
        console.log('TEST_RESULT:' + JSON.stringify(result));
        window.testResult = result;
      }
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
  final server = RtpForwardTestServer();

  ProcessSignal.sigint.watch().listen((_) async {
    await server.shutdown();
    exit(0);
  });

  await server.start();
  print('[Server] Ready. Press Ctrl+C to stop.');
}
