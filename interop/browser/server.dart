/// WebSocket Signaling Server and Dart WebRTC Peer
///
/// This server:
/// 1. Serves the browser test page
/// 2. Acts as a WebSocket signaling server
/// 3. Hosts a Dart WebRTC peer that answers offers from the browser
///
/// Usage:
///   dart run interop/browser/server.dart
///   Then open http://localhost:8080 in Chrome

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('[Server] Listening on http://localhost:8080');
  print('[Server] Open this URL in Chrome to test browser interop\n');

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      // WebSocket connection for signaling
      final socket = await WebSocketTransformer.upgrade(request);
      print('[Server] WebSocket connected');
      handleWebSocket(socket);
    } else if (request.uri.path == '/' || request.uri.path == '/index.html') {
      // Serve the auto-signaling HTML page
      request.response
        ..headers.contentType = ContentType.html
        ..write(autoSignalingHtml)
        ..close();
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
    }
  }
}

void handleWebSocket(WebSocket socket) async {
  RtcPeerConnection? pc;
  DataChannel? dataChannel;

  socket.listen((message) async {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String;

      print('[Server] Received: $type');

      if (type == 'offer') {
        // Create peer connection
        pc = RtcPeerConnection();
        print('[Dart] PeerConnection created');

        await Future.delayed(Duration(milliseconds: 200));

        // Set up event handlers
        pc!.onIceCandidate.listen((candidate) {
          print('[Dart] ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
          // Send candidate to browser
          socket.add(jsonEncode({
            'type': 'candidate',
            'candidate': 'candidate:${candidate.toSdp()}',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          }));
        });

        pc!.onIceConnectionStateChange.listen((state) {
          print('[Dart] ICE state: $state');
          if (state == IceConnectionState.connected || state == IceConnectionState.completed) {
            print('[Dart] ICE CONNECTED - ready for DTLS');
          }
        });

        pc!.onConnectionStateChange.listen((state) {
          print('[Dart] Connection state: $state');
        });

        pc!.onDataChannel.listen((channel) {
          print('[Dart] DataChannel received: ${channel.label}');
          dataChannel = channel;

          channel.onStateChange.listen((state) {
            print('[Dart] DataChannel state: $state');
            if (state == DataChannelState.open) {
              print('[Dart] Sending greeting...');
              channel.sendString('Hello from Dart!');
            }
          });

          channel.onMessage.listen((msg) {
            print('[Dart] Received: $msg');
            // Echo back
            channel.sendString('Echo: $msg');
          });
        });

        // Set remote description (offer)
        final offer = SessionDescription(
          type: 'offer',
          sdp: data['sdp'] as String,
        );
        await pc!.setRemoteDescription(offer);
        print('[Dart] Remote description set');

        // Create and send answer
        final answer = await pc!.createAnswer();
        await pc!.setLocalDescription(answer);
        print('[Dart] Answer created');

        socket.add(jsonEncode({
          'type': 'answer',
          'sdp': answer.sdp,
        }));
        print('[Dart] Answer sent');

      } else if (type == 'candidate' && pc != null) {
        // Add ICE candidate from browser
        final candidateStr = data['candidate'] as String;
        if (candidateStr.isNotEmpty) {
          var sdp = candidateStr;
          if (sdp.startsWith('candidate:')) {
            sdp = sdp.substring('candidate:'.length);
          }
          final candidate = Candidate.fromSdp(sdp);
          await pc!.addIceCandidate(candidate);
          print('[Dart] Added remote ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
        }

      } else if (type == 'message' && dataChannel != null) {
        final text = data['text'] as String;
        dataChannel!.sendString(text);
        print('[Dart] Sent: $text');
      }

    } catch (e, st) {
      print('[Server] Error: $e');
      print(st);
    }
  }, onDone: () async {
    print('[Server] WebSocket disconnected');
    await pc?.close();
  });
}

const autoSignalingHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Browser Interop Test (Auto-Signaling)</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 400px; overflow-y: auto; border: 1px solid #333; margin-top: 10px; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .send { color: #ff8; }
        .receive { color: #f8f; }
        button { padding: 10px 20px; margin: 5px; background: #444; color: #fff; border: none; cursor: pointer; }
        button:hover { background: #666; }
        button:disabled { background: #222; cursor: not-allowed; }
        input { padding: 10px; width: 300px; background: #333; color: #fff; border: 1px solid #555; }
        #controls { margin-bottom: 20px; }
        h1 { color: #8af; }
        #status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .status-connecting { background: #444; }
        .status-connected { background: #284; }
        .status-error { background: #844; }
    </style>
</head>
<body>
    <h1>WebRTC Browser Interop Test</h1>
    <div id="status" class="status-connecting">Status: Connecting to signaling server...</div>
    <div id="controls">
        <button id="connectBtn" onclick="connect()" disabled>Connect to Dart Peer</button>
        <button id="sendBtn" onclick="sendMessage()" disabled>Send Message</button>
        <input type="text" id="messageInput" placeholder="Message to send..." value="Hello from Chrome!">
    </div>
    <h3>Log</h3>
    <div id="log"></div>

    <script>
        let ws = null;
        let pc = null;
        let dc = null;
        let pendingCandidates = [];
        let remoteDescriptionSet = false;

        function setStatus(msg, className) {
            const status = document.getElementById('status');
            status.textContent = 'Status: ' + msg;
            status.className = className;
        }

        function log(msg, className = 'info') {
            const logDiv = document.getElementById('log');
            const line = document.createElement('div');
            line.className = className;
            line.textContent = '[' + new Date().toISOString().substr(11, 12) + '] ' + msg;
            logDiv.appendChild(line);
            logDiv.scrollTop = logDiv.scrollHeight;
            console.log(msg);
        }

        async function addPendingCandidates() {
            for (const candidate of pendingCandidates) {
                try {
                    await pc.addIceCandidate(candidate);
                    log('Added buffered ICE candidate');
                } catch (e) {
                    log('Error adding buffered ICE candidate: ' + e, 'error');
                }
            }
            pendingCandidates = [];
        }

        function initWebSocket() {
            ws = new WebSocket('ws://' + location.host);

            ws.onopen = () => {
                log('WebSocket connected to signaling server', 'success');
                setStatus('Connected to signaling server', 'status-connected');
                document.getElementById('connectBtn').disabled = false;
            };

            ws.onmessage = async (e) => {
                const data = JSON.parse(e.data);
                log('Received: ' + data.type);

                if (data.type === 'answer') {
                    log('Setting remote description (answer)...');
                    await pc.setRemoteDescription(new RTCSessionDescription({
                        type: 'answer',
                        sdp: data.sdp
                    }));
                    remoteDescriptionSet = true;
                    log('Remote description set!', 'success');
                    // Add any buffered candidates
                    await addPendingCandidates();

                } else if (data.type === 'candidate' && data.candidate) {
                    const candidate = new RTCIceCandidate({
                        candidate: data.candidate,
                        sdpMid: data.sdpMid,
                        sdpMLineIndex: data.sdpMLineIndex
                    });

                    if (!remoteDescriptionSet) {
                        log('Buffering ICE candidate (waiting for answer)...');
                        pendingCandidates.push(candidate);
                        return;
                    }

                    log('Adding remote ICE candidate...');
                    try {
                        await pc.addIceCandidate(candidate);
                    } catch (e) {
                        log('Error adding ICE candidate: ' + e, 'error');
                    }
                }
            };

            ws.onerror = (e) => {
                log('WebSocket error', 'error');
                setStatus('WebSocket error', 'status-error');
            };

            ws.onclose = () => {
                log('WebSocket closed');
                setStatus('Disconnected', 'status-error');
                document.getElementById('connectBtn').disabled = true;
                document.getElementById('sendBtn').disabled = true;
            };
        }

        async function connect() {
            try {
                document.getElementById('connectBtn').disabled = true;
                log('Creating RTCPeerConnection...');

                pc = new RTCPeerConnection({
                    iceServers: []  // Use host candidates only for local testing
                });

                pc.onicecandidate = (e) => {
                    if (e.candidate) {
                        log('ICE candidate: ' + (e.candidate.type || 'unknown') + ' ' + e.candidate.address + ':' + e.candidate.port);
                        ws.send(JSON.stringify({
                            type: 'candidate',
                            candidate: e.candidate.candidate,
                            sdpMid: e.candidate.sdpMid,
                            sdpMLineIndex: e.candidate.sdpMLineIndex
                        }));
                    } else {
                        log('ICE gathering complete', 'success');
                    }
                };

                pc.oniceconnectionstatechange = () => {
                    log('ICE connection state: ' + pc.iceConnectionState,
                        pc.iceConnectionState === 'connected' || pc.iceConnectionState === 'completed' ? 'success' : 'info');
                };

                pc.onconnectionstatechange = () => {
                    log('Connection state: ' + pc.connectionState,
                        pc.connectionState === 'connected' ? 'success' : 'info');

                    if (pc.connectionState === 'connected') {
                        setStatus('Connected to Dart peer!', 'status-connected');
                    }
                };

                // Create data channel
                log('Creating DataChannel "chat"...');
                dc = pc.createDataChannel('chat', { ordered: true });

                dc.onopen = () => {
                    log('DataChannel OPEN!', 'success');
                    document.getElementById('sendBtn').disabled = false;
                };

                dc.onclose = () => {
                    log('DataChannel closed');
                    document.getElementById('sendBtn').disabled = true;
                };

                dc.onmessage = (e) => {
                    log('Received: ' + e.data, 'receive');
                };

                dc.onerror = (e) => {
                    log('DataChannel error: ' + e.error, 'error');
                };

                // Create offer
                log('Creating offer...');
                const offer = await pc.createOffer();
                log('Setting local description...');
                await pc.setLocalDescription(offer);

                // Send offer to Dart via signaling
                ws.send(JSON.stringify({
                    type: 'offer',
                    sdp: offer.sdp
                }));
                log('Offer sent to Dart peer', 'success');

            } catch (e) {
                log('Error: ' + e.message, 'error');
                document.getElementById('connectBtn').disabled = false;
            }
        }

        function sendMessage() {
            const msg = document.getElementById('messageInput').value;
            if (!dc || dc.readyState !== 'open') {
                log('DataChannel not open', 'error');
                return;
            }
            dc.send(msg);
            log('Sent: ' + msg, 'send');
        }

        // Initialize
        log('Initializing...');
        initWebSocket();
    </script>
</body>
</html>
''';
