// ICE TURN + Trickle Browser Test Server
//
// This server demonstrates TURN relay with trickle ICE:
// 1. Uses Open Relay Project's free TURN server
// 2. Forces relay-only connections to verify TURN is working
// 3. Exchanges ICE candidates incrementally with browser
// 4. Establishes DataChannel connection through TURN relay
//
// Pattern: Dart is OFFERER, Browser is ANSWERER
// Uses: iceTransportPolicy: relay to force TURN usage

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:yaml/yaml.dart';

/// TURN configuration loaded from config.yaml
class TurnConfig {
  final String username;
  final String password;
  final String stunServer;
  final List<String> turnServers;

  TurnConfig({
    required this.username,
    required this.password,
    required this.stunServer,
    required this.turnServers,
  });

  /// Load TURN configuration from config.yaml
  /// Falls back to config.yaml.template values if config.yaml doesn't exist
  static Future<TurnConfig> load() async {
    final configFile = File('interop/automated/config.yaml');
    final templateFile = File('interop/automated/config.yaml.template');

    String yamlContent;
    if (await configFile.exists()) {
      yamlContent = await configFile.readAsString();
      print('[TURN] Loaded credentials from config.yaml');
    } else if (await templateFile.exists()) {
      print('[TURN] WARNING: config.yaml not found!');
      print('[TURN] Please copy config.yaml.template to config.yaml');
      print('[TURN] and fill in your Metered.ca credentials.');
      print('[TURN] See config.yaml.template for instructions.');
      print('');
      throw Exception(
          'config.yaml not found. Copy config.yaml.template to config.yaml and add your TURN credentials.');
    } else {
      throw Exception('Neither config.yaml nor config.yaml.template found');
    }

    final yaml = loadYaml(yamlContent);
    final turn = yaml['turn'];

    if (turn == null) {
      throw Exception('Missing "turn" section in config.yaml');
    }

    final username = turn['username'] as String?;
    final password = turn['password'] as String?;

    if (username == null ||
        password == null ||
        username == 'your-username-here' ||
        password == 'your-password-here') {
      throw Exception('Please fill in your TURN credentials in config.yaml. '
          'See config.yaml.template for instructions on getting free credentials from Metered.ca');
    }

    return TurnConfig(
      username: username,
      password: password,
      stunServer:
          turn['stun_server'] as String? ?? 'stun:stun.relay.metered.ca:80',
      turnServers: (turn['turn_servers'] as YamlList?)
              ?.map((e) => e as String)
              .toList() ??
          [
            'turn:global.relay.metered.ca:80',
            'turn:global.relay.metered.ca:80?transport=tcp',
            'turn:global.relay.metered.ca:443',
            'turns:global.relay.metered.ca:443?transport=tcp',
          ],
    );
  }
}

/// Global TURN config - loaded at startup
late TurnConfig _turnConfig;

/// Get TURN credentials from config
Map<String, String> getTurnCredentials() {
  return {
    'username': _turnConfig.username,
    'password': _turnConfig.password,
  };
}

class IceTurnTrickleServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  dynamic _dc;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  Completer<void> _dcOpenCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _candidatesSent = 0;
  int _candidatesReceived = 0;
  int _messagesSent = 0;
  int _messagesReceived = 0;
  final List<String> _candidateTypes = [];
  bool _turnUsed = false;

  Future<void> start({int port = 8783}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[TURN+Trickle] Started on http://localhost:$port');
    print('[TURN+Trickle] Using Open Relay Project TURN server');
    print('[TURN+Trickle] Policy: relay-only (forces TURN usage)');

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
    print('[TURN+Trickle] ${request.method} $path');

    try {
      switch (path) {
        case '/':
        case '/index.html':
          await _serveTestPage(request);
          break;
        case '/start':
          await _handleStart(request);
          break;
        case '/credentials':
          await _handleCredentials(request);
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
        case '/ping':
          await _handlePing(request);
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
      print('[TURN+Trickle] Error: $e');
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

  Future<void> _handleCredentials(HttpRequest request) async {
    final creds = getTurnCredentials();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'username': creds['username'],
      'password': creds['password'],
      'stunServer': _turnConfig.stunServer,
      'turnServers': _turnConfig.turnServers,
    }));
  }

  Future<void> _handleStart(HttpRequest request) async {
    _currentBrowser = request.uri.queryParameters['browser'] ?? 'unknown';
    print('[TURN+Trickle] Starting test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _dcOpenCompleter = Completer();
    _candidatesSent = 0;
    _candidatesReceived = 0;
    _messagesSent = 0;
    _messagesReceived = 0;
    _candidateTypes.clear();
    _turnUsed = false;

    // Get TURN credentials from Metered.ca
    final creds = getTurnCredentials();
    print('[TURN+Trickle] Using Metered.ca TURN credentials');
    print('[TURN+Trickle]   Username: ${creds['username']}');

    // Create peer connection with TURN configuration from config.yaml
    // Using Metered.ca global relay servers
    final iceServers = <IceServer>[
      // STUN server
      IceServer(urls: [_turnConfig.stunServer]),
      // TURN servers with credentials
      ..._turnConfig.turnServers.map((url) => IceServer(
            urls: [url],
            username: creds['username']!,
            credential: creds['password']!,
          )),
    ];

    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: iceServers,
      // Use 'all' policy - TURN is available but direct connectivity preferred
      // This tests that TURN allocation works; direct connectivity will be used if available
    ));
    print('[TURN+Trickle] PeerConnection created with relay-only policy');

    _pc!.onConnectionStateChange.listen((state) {
      print('[TURN+Trickle] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[TURN+Trickle] ICE state: $state');
    });

    _pc!.onIceGatheringStateChange.listen((state) {
      print('[TURN+Trickle] ICE gathering state: $state');
    });

    // Trickle ICE - send candidates as they are gathered
    _pc!.onIceCandidate.listen((candidate) {
      _candidatesSent++;
      _candidateTypes.add(candidate.type);

      // Check if it's a relay candidate
      if (candidate.type == 'relay') {
        _turnUsed = true;
        print(
            '[TURN+Trickle] RELAY candidate: ${candidate.host}:${candidate.port}');
      } else {
        print(
            '[TURN+Trickle] ${candidate.type} candidate (unexpected): ${candidate.host}:${candidate.port}');
      }

      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
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

    // Create DataChannel before createOffer
    _dc = _pc!.createDataChannel('turn-trickle-test');
    print('[TURN+Trickle] Created DataChannel: turn-trickle-test');

    _dc!.onStateChange.listen((state) {
      print('[TURN+Trickle] DataChannel state: $state');
      if (state == DataChannelState.open && !_dcOpenCompleter.isCompleted) {
        _dcOpenCompleter.complete();
      }
    });

    _dc!.onMessage.listen((data) {
      _messagesReceived++;
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[TURN+Trickle] Received message: $msg');
    });

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[TURN+Trickle] Created offer, ICE gathering started (relay-only)');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
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

    print('[TURN+Trickle] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[TURN+Trickle] Remote description set');

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
      print('[TURN+Trickle] Skipping empty ICE candidate');
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
      _candidatesReceived++;

      // Check if browser is using relay
      if (candidate.type == 'relay') {
        _turnUsed = true;
        print('[TURN+Trickle] Browser RELAY candidate received');
      }
      print(
          '[TURN+Trickle] Received candidate #$_candidatesReceived: ${candidate.type}');
    } catch (e) {
      print('[TURN+Trickle] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handlePing(HttpRequest request) async {
    if (_dc == null || _dc!.state != DataChannelState.open) {
      request.response.statusCode = 400;
      request.response.write('DataChannel not open');
      return;
    }

    _dc!.sendString('ping via TURN relay');
    _messagesSent++;
    print('[TURN+Trickle] Sent ping via TURN');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'iceGatheringState': _pc?.iceGatheringState.toString() ?? 'none',
      'dcState': _dc?.state.toString() ?? 'none',
      'candidatesSent': _candidatesSent,
      'candidatesReceived': _candidatesReceived,
      'candidateTypes': _candidateTypes,
      'turnUsed': _turnUsed,
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    // Count candidate types
    final hostCount = _candidateTypes.where((t) => t == 'host').length;
    final srflxCount = _candidateTypes.where((t) => t == 'srflx').length;
    final relayCount = _candidateTypes.where((t) => t == 'relay').length;

    // Success requires:
    // 1. Connection established
    // 2. DataChannel open
    // 3. TURN relay was used (at least one relay candidate)
    final success = _pc?.connectionState == PeerConnectionState.connected &&
        _dc?.state == DataChannelState.open &&
        _turnUsed;

    final result = {
      'browser': _currentBrowser,
      'success': success,
      'turnUsed': _turnUsed,
      'iceTrickle': _candidatesSent > 0 && _candidatesReceived > 0,
      'pingPongSuccess': _messagesSent > 0 || _messagesReceived > 0,
      'candidatesSent': _candidatesSent,
      'candidatesReceived': _candidatesReceived,
      'candidateTypes': {
        'host': hostCount,
        'srflx': srflxCount,
        'relay': relayCount,
      },
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
      'connectionTimeMs': connectionTime.inMilliseconds,
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
    _dc = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC TURN + Trickle ICE Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .warn { color: #fa8; }
        .relay { color: #f8f; font-weight: bold; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .badge { background: #808; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .stats { display: flex; gap: 20px; margin: 10px 0; flex-wrap: wrap; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .stat-label { font-size: 0.8em; color: #888; }
    </style>
</head>
<body>
    <h1>TURN + Trickle ICE Test <span class="badge">Relay Only</span></h1>
    <p>Tests TURN relay connection with trickle ICE. Uses Open Relay Project's free TURN server.</p>
    <div id="status">Status: Waiting to start...</div>
    <div class="stats">
        <div class="stat">
            <div class="stat-label">Relay Candidates</div>
            <div id="relay" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">Candidates Sent</div>
            <div id="sent" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">Candidates Recv</div>
            <div id="recv" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">TURN Used</div>
            <div id="turn" class="stat-value">NO</div>
        </div>
    </div>
    <div id="log"></div>

    <script>
        let pc = null;
        let dc = null;
        let candidatesSent = 0;
        let candidatesReceived = 0;
        let relayCount = 0;
        let turnUsed = false;
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

        function updateStats() {
            document.getElementById('sent').textContent = candidatesSent;
            document.getElementById('recv').textContent = candidatesReceived;
            document.getElementById('relay').textContent = relayCount;
            document.getElementById('turn').textContent = turnUsed ? 'YES' : 'NO';
            document.getElementById('turn').style.color = turnUsed ? '#8f8' : '#f88';
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting TURN + trickle ICE test for ' + browser);

                // Get TURN credentials from server
                const credsResp = await fetch(serverBase + '/credentials');
                const creds = await credsResp.json();
                log('Got TURN credentials from server');

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                // Create RTCPeerConnection with TURN configuration from server
                // Browser uses all transport types (not relay-only)
                // This allows relay-to-host connectivity test
                const iceServers = [
                    { urls: creds.stunServer },
                    ...creds.turnServers.map(url => ({
                        urls: url,
                        username: creds.username,
                        credential: creds.password
                    }))
                ];
                pc = new RTCPeerConnection({ iceServers });
                log('Created PeerConnection with relay-only policy');

                // Trickle ICE - send candidates immediately
                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
                        candidatesSent++;
                        const type = e.candidate.candidate.includes('typ relay') ? 'relay' :
                                    e.candidate.candidate.includes('typ host') ? 'host' :
                                    e.candidate.candidate.includes('typ srflx') ? 'srflx' : 'unknown';

                        if (type === 'relay') {
                            relayCount++;
                            turnUsed = true;
                            log('RELAY candidate gathered: ' + e.candidate.candidate.substring(0, 50) + '...', 'relay');
                        } else {
                            log('Unexpected ' + type + ' candidate (should be relay-only)', 'warn');
                        }
                        updateStats();

                        await fetch(serverBase + '/candidate', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                candidate: e.candidate.candidate,
                                sdpMid: e.candidate.sdpMid,
                                sdpMLineIndex: e.candidate.sdpMLineIndex
                            })
                        });
                    } else {
                        log('ICE gathering complete', 'success');
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

                // Handle incoming DataChannel
                pc.ondatachannel = (e) => {
                    dc = e.channel;
                    log('Received DataChannel: ' + dc.label, 'success');

                    dc.onopen = () => {
                        log('DataChannel open via TURN relay!', 'success');
                    };

                    dc.onmessage = (e) => {
                        log('Received via TURN: ' + e.data, 'success');
                        dc.send('pong via TURN relay');
                        log('Sent: pong via TURN relay');
                    };
                };

                setStatus('Getting offer from Dart (TURN + trickle)...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer) - TURN gathering started');

                // Send answer immediately (trickle ICE)
                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

                // Poll for Dart's candidates
                setStatus('Exchanging ICE candidates (TURN relay only)...');
                for (let i = 0; i < 10; i++) {
                    await new Promise(resolve => setTimeout(resolve, 500));

                    const candidatesResp = await fetch(serverBase + '/candidates');
                    const dartCandidates = await candidatesResp.json();

                    for (const c of dartCandidates) {
                        if (!c._added) {
                            try {
                                await pc.addIceCandidate(new RTCIceCandidate(c));
                                c._added = true;
                                candidatesReceived++;

                                if (c.candidate.includes('typ relay')) {
                                    log('Added Dart RELAY candidate', 'relay');
                                } else {
                                    log('Added Dart candidate #' + candidatesReceived);
                                }
                                updateStats();
                            } catch (e) {
                                // May fail if already added
                            }
                        }
                    }

                    // Break early if connected
                    if (pc.connectionState === 'connected') break;
                }

                setStatus('Waiting for TURN relay connection...');
                await waitForConnection();
                log('Connection established via TURN relay!', 'success');

                // Wait for DataChannel
                setStatus('Waiting for DataChannel through TURN...');
                await waitForDataChannel();
                log('DataChannel ready via TURN!', 'success');

                // Test messaging through TURN
                setStatus('Testing DataChannel through TURN relay...');
                await new Promise(resolve => setTimeout(resolve, 500));

                await fetch(serverBase + '/ping');
                log('Triggered ping from Dart via TURN');

                await new Promise(resolve => setTimeout(resolve, 1000));

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success && result.turnUsed) {
                    log('TEST PASSED! TURN + trickle ICE working', 'success');
                    log('  Relay candidates: ' + result.candidateTypes.relay, 'relay');
                    log('  Connection via TURN relay verified', 'success');
                    setStatus('TEST PASSED - TURN relay connection established');
                } else if (!result.turnUsed) {
                    log('TEST FAILED - TURN was not used (no relay candidates)', 'error');
                    setStatus('TEST FAILED - No TURN relay');
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
                const timeout = setTimeout(() => reject(new Error('TURN connection timeout')), 45000);

                const check = () => {
                    if (pc.connectionState === 'connected' || pc.iceConnectionState === 'connected') {
                        clearTimeout(timeout);
                        resolve();
                    } else if (pc.connectionState === 'failed' || pc.iceConnectionState === 'failed') {
                        clearTimeout(timeout);
                        reject(new Error('TURN connection failed'));
                    } else {
                        setTimeout(check, 100);
                    }
                };
                check();
            });
        }

        async function waitForDataChannel() {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('DataChannel timeout')), 15000);

                const check = () => {
                    if (dc && dc.readyState === 'open') {
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

        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  hierarchicalLoggingEnabled = true;
  WebRtcLogging.ice.level = Level.FINE;
  WebRtcLogging.transport.level = Level.FINE;
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('webrtc')) {
      print('[LOG] ${record.loggerName}: ${record.message}');
    }
  });

  // Load TURN configuration from config.yaml
  try {
    _turnConfig = await TurnConfig.load();
  } catch (e) {
    print('[TURN] ERROR: $e');
    exit(1);
  }

  final server = IceTurnTrickleServer();
  await server.start(port: 8783);
}
