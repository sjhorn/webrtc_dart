/// Pub/Sub Media Channel Example
///
/// Demonstrates a publish/subscribe pattern for multi-peer video routing.
/// Multiple clients can publish streams and subscribe to each other's streams.
///
/// This matches werift's mediachannel/pubsub/offer.ts pattern:
/// - WebSocket signaling server
/// - One PeerConnection per client
/// - Track buffering for cross-client routing
/// - Dynamic transceiver management
///
/// Protocol:
///   publish    -> onPublish (media id)
///   subscribe  -> onSubscribe (media, mid mapping)
///   unpublish  -> onUnPublish
///   unsubscribe
///   answer     <- offer
///
/// Usage: dart run example/mediachannel/pubsub/offer.dart
///        Then open multiple browser tabs to http://localhost:8888
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

/// Global track storage for cross-client routing
/// Key: media ID (mid from publisher's transceiver)
/// Value: MediaStreamTrack from publisher
final Map<String, MediaStreamTrack> globalTracks = {};

/// Track which client published which media
final Map<String, WebSocket> trackOwners = {};

/// Store receiver info for PLI (Picture Loss Indication) requests
/// Key: media ID, Value: (RtpSession, remoteSsrc) for sending PLI
final Map<String, (dynamic rtpSession, int ssrc)> trackReceivers = {};

/// Keyframe cache for new subscribers
/// Key: media ID, Value: list of RTP packets forming the last keyframe
final Map<String, List<RtpPacket>> keyframeCache = {};

/// Pending subscriptions waiting for tracks to be received
/// Key: media ID, Value: list of (client, transceiver) pairs
final Map<String, List<(ClientSession, RTCRtpTransceiver)>>
    pendingSubscriptions = {};

/// All connected clients for broadcast notifications
final List<ClientSession> clients = [];

class ClientSession {
  final WebSocket socket;
  RTCPeerConnection? pc;

  ClientSession(this.socket);

  void send(String type, Map<String, dynamic> payload) {
    final msg = jsonEncode({'type': type, 'payload': payload});
    socket.add(msg);
    print('[Client] Sent: $type');
  }

  Future<void> close() async {
    await pc?.close();
  }
}

class PubSubServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8888}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Pub/Sub Media Server');
    print('=' * 50);
    print('WebSocket: ws://localhost:$port');
    print('HTTP: http://localhost:$port');
    print('');
    print('Open multiple browser tabs to test multi-peer routing');
    print('');

    await for (final request in _httpServer!) {
      // Check WebSocket upgrade FIRST (it also has path '/')
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _handleWebSocket(request);
      } else if (request.uri.path == '/') {
        _serveHtml(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    }
  }

  void _serveHtml(HttpRequest request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_clientHtml);
    request.response.close();
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final client = ClientSession(socket);
    clients.add(client);
    print('[Server] Client connected (${clients.length} total)');

    // Create PeerConnection for this client
    client.pc = RTCPeerConnection(
      RtcConfiguration(
        iceServers: [
          IceServer(urls: ['stun:stun.l.google.com:19302'])
        ],
        codecs: RtcCodecs(
          video: [
            RtpCodecParameters(
              mimeType: 'video/VP8',
              clockRate: 90000,
              payloadType: 96, // Must specify PT for proper packet rewriting
              rtcpFeedback: [
                RtcpFeedback(type: 'nack'),
                RtcpFeedback(type: 'nack', parameter: 'pli'),
              ],
            ),
          ],
        ),
      ),
    );

    // Add dummy sendonly transceiver (matches werift)
    client.pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );

    // Send initial offer
    final offer = await client.pc!.createOffer();
    await client.pc!.setLocalDescription(offer);
    client.send('offer', {'sdp': offer.sdp});

    // Notify new client of existing published tracks
    for (final media in globalTracks.keys) {
      client.send('onPublish', {'media': media});
    }

    // Log connection state for debugging
    client.pc!.onConnectionStateChange.listen((state) {
      print('[Server] Client ${clients.indexOf(client)} connection: $state');
    });

    // Handle messages
    socket.listen(
      (data) => _handleMessage(client, data as String),
      onDone: () => _handleDisconnect(client),
      onError: (e) => print('[Server] WebSocket error: $e'),
    );
  }

  Future<void> _handleMessage(ClientSession client, String data) async {
    final msg = jsonDecode(data) as Map<String, dynamic>;
    final type = msg['type'] as String;
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    print('[Server] Received: $type');

    switch (type) {
      case 'publish':
        await _handlePublish(client, payload);
        break;
      case 'unpublish':
        await _handleUnpublish(client, payload);
        break;
      case 'subscribe':
        await _handleSubscribe(client, payload);
        break;
      case 'unsubscribe':
        await _handleUnsubscribe(client, payload);
        break;
      case 'answer':
        await _handleAnswer(client, payload);
        break;
    }
  }

  Future<void> _handlePublish(
    ClientSession client,
    Map<String, dynamic> payload,
  ) async {
    // Create recvonly transceiver to receive video from this publisher
    final transceiver = client.pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Handle incoming track
    client.pc!.onTrack.listen((t) {
      if (t.mid != transceiver.mid) return;

      final track = t.receiver.track;
      final media = transceiver.mid!;
      print('[Server] Received track for media: $media');

      // Store track globally for cross-client routing
      globalTracks[media] = track;
      trackOwners[media] = client.socket;

      // Store receiver RTP session for PLI requests
      final receiverRtpSession = t.receiver.rtpSession;

      // Capture remote SSRC from first packet for PLI
      var remoteSsrc = 0;
      var firstPacket = true;

      List<RtpPacket> currentKeyframePackets = [];
      bool collectingKeyframe = false;

      track.onReceiveRtp.listen((rtp) {
        // Detect VP8 keyframe START: must have BOTH S=1 (start of partition) AND frame_type=0
        bool isKeyframeStart = false;
        if (rtp.payload.length > 4) {
          // Parse VP8 payload descriptor
          var offset = 0;
          final byte0 = rtp.payload[0];
          offset++; // Skip first byte

          // Check S bit (start of partition) - REQUIRED for keyframe start
          final isStartOfPartition = (byte0 & 0x10) != 0;

          // Check X bit (extension)
          if ((byte0 & 0x80) != 0) {
            // Skip extension byte
            final extByte = rtp.payload[offset];
            offset++;

            // Check I bit (PictureID)
            if ((extByte & 0x80) != 0) {
              // Check M bit for 2-byte PictureID
              if (rtp.payload[offset] & 0x80 != 0) {
                offset += 2;
              } else {
                offset++;
              }
            }
            // Skip L, T, K extensions if present
            if ((extByte & 0x40) != 0) offset++;
            if ((extByte & 0x20) != 0) offset++;
          }

          // Check for keyframe START (S=1 and frame_type=0)
          if (offset < rtp.payload.length && isStartOfPartition) {
            final frameType = rtp.payload[offset] & 0x01;
            isKeyframeStart = frameType == 0;
          }
        }

        // Cache keyframe packets
        if (isKeyframeStart) {
          // Start collecting a new keyframe
          currentKeyframePackets = [rtp];
          collectingKeyframe = true;
        } else if (collectingKeyframe) {
          // Continue collecting keyframe packets
          currentKeyframePackets.add(rtp);
        }

        // When we see marker=true (end of frame), finalize the keyframe cache
        if (collectingKeyframe && rtp.marker) {
          // Store the complete keyframe
          keyframeCache[media] = List.from(currentKeyframePackets);
          collectingKeyframe = false;
        }

        if (firstPacket) {
          remoteSsrc = rtp.ssrc;
          trackReceivers[media] = (receiverRtpSession, remoteSsrc);

          // Start periodic PLI every 1 second (like werift)
          // This ensures subscribers always get keyframes
          Timer.periodic(Duration(seconds: 1), (timer) {
            if (globalTracks[media] == null) {
              timer.cancel();
              return;
            }
            receiverRtpSession.sendPli(remoteSsrc);
          });

          firstPacket = false;
        }
      });

      // Fulfill any pending subscriptions for this media
      final pending = pendingSubscriptions.remove(media);
      if (pending != null) {
        for (final (_, subTransceiver) in pending) {
          print('[Server] Fulfilling pending subscription for $media');
          subTransceiver.sender.registerTrackForForward(track);
          // Request keyframe for the new subscriber
          _requestKeyframe(media);
        }
      }
    });

    // Send updated offer
    final offer = await client.pc!.createOffer();
    await client.pc!.setLocalDescription(offer);
    client.send('offer', {'sdp': offer.sdp});

    // Notify this client of their published media ID
    client.send('onPublish', {'media': transceiver.mid});

    // Notify all OTHER clients of new publisher
    for (final other in clients) {
      if (other != client) {
        other.send('onPublish', {'media': transceiver.mid});
      }
    }
  }

  Future<void> _handleUnpublish(
    ClientSession client,
    Map<String, dynamic> payload,
  ) async {
    final media = payload['media'] as String;

    // Remove track from global storage
    globalTracks.remove(media);
    trackOwners.remove(media);

    // Find and remove the transceiver
    final transceiver = client.pc!.transceivers.firstWhere(
      (t) => t.mid == media,
      orElse: () => throw Exception('Transceiver not found'),
    );
    client.pc!.removeTrack(transceiver.sender);

    // Send updated offer
    final offer = await client.pc!.createOffer();
    await client.pc!.setLocalDescription(offer);
    client.send('offer', {'sdp': offer.sdp});
    client.send('onUnPublish', {'media': media});

    // Notify all other clients
    for (final other in clients) {
      if (other != client) {
        other.send('onUnPublish', {'media': media});
      }
    }
  }

  Future<void> _handleSubscribe(
    ClientSession client,
    Map<String, dynamic> payload,
  ) async {
    final media = payload['media'] as String;

    // Create sendonly transceiver to send video to this subscriber
    final transceiver = client.pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );

    // Send updated offer first
    final offer = await client.pc!.createOffer();
    await client.pc!.setLocalDescription(offer);

    client.send('offer', {'sdp': offer.sdp});
    client.send('onSubscribe', {'media': media, 'mid': transceiver.mid});

    // Route the published track to this subscriber
    final track = globalTracks[media];
    if (track != null) {
      print('[Server] Routing $media to subscriber via mid ${transceiver.mid}');

      // Wait for connection to be connected before forwarding
      // This ensures SRTP is ready so packets won't be dropped
      Future<void> startForwarding() async {
        // Send cached keyframe FIRST so the subscriber can start decoding immediately
        final cachedKeyframe = keyframeCache[media];
        if (cachedKeyframe != null && cachedKeyframe.isNotEmpty) {
          print(
              '[Server] Sending cached keyframe (${cachedKeyframe.length} packets) to new subscriber');
          await transceiver.sender.forwardCachedPackets(cachedKeyframe);
        }

        // Use registerTrackForForward like werift does.
        // This handles offset calculation internally.
        transceiver.sender.registerTrackForForward(track);

        // Request keyframe via PLI (Chrome may ignore this, but we try anyway).
        // The cached keyframe above should allow immediate decoding.
        _requestKeyframe(media);
      }

      // Check if already connected
      if (client.pc!.connectionState == PeerConnectionState.connected) {
        await startForwarding();
      } else {
        // Wait for connection to be established
        late StreamSubscription<PeerConnectionState> subscription;
        subscription = client.pc!.onConnectionStateChange.listen((state) async {
          if (state == PeerConnectionState.connected) {
            await startForwarding();
            subscription.cancel();
          }
        });
      }
    } else {
      // Track not received yet, queue the subscription
      print('[Server] Track $media not yet received, queuing subscription');
      pendingSubscriptions
          .putIfAbsent(media, () => [])
          .add((client, transceiver));
    }
  }

  Future<void> _handleUnsubscribe(
    ClientSession client,
    Map<String, dynamic> payload,
  ) async {
    final mid = payload['mid'] as String;

    // Find and remove the transceiver
    final transceiver = client.pc!.transceivers.firstWhere(
      (t) => t.mid == mid,
      orElse: () => throw Exception('Transceiver not found'),
    );
    client.pc!.removeTrack(transceiver.sender);

    // Send updated offer
    final offer = await client.pc!.createOffer();
    await client.pc!.setLocalDescription(offer);
    client.send('offer', {'sdp': offer.sdp});
  }

  Future<void> _handleAnswer(
    ClientSession client,
    Map<String, dynamic> payload,
  ) async {
    final sdp = payload['sdp'] as String;
    await client.pc!.setRemoteDescription(
      RTCSessionDescription(type: 'answer', sdp: sdp),
    );
  }

  Future<void> _handleDisconnect(ClientSession client) async {
    print('[Server] Client disconnected');

    // Remove any tracks this client published
    final toRemove = <String>[];
    trackOwners.forEach((media, socket) {
      if (socket == client.socket) {
        toRemove.add(media);
      }
    });

    for (final media in toRemove) {
      globalTracks.remove(media);
      trackOwners.remove(media);
      trackReceivers.remove(media);

      // Notify remaining clients
      for (final other in clients) {
        if (other != client) {
          other.send('onUnPublish', {'media': media});
        }
      }
    }

    clients.remove(client);
    await client.close();
    print('[Server] ${clients.length} clients remaining');
  }

  /// Request a keyframe from the publisher for the given media
  void _requestKeyframe(String media) {
    final receiverInfo = trackReceivers[media];
    if (receiverInfo == null) {
      return;
    }

    final (rtpSession, remoteSsrc) = receiverInfo;
    // Send PLI (Picture Loss Indication) to request keyframe from publisher
    rtpSession.sendPli(remoteSsrc);
  }
}

/// HTML client with publish/subscribe UI (simplified version of werift's React app)
const _clientHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Pub/Sub Media</title>
  <style>
    body { font-family: sans-serif; padding: 20px; }
    .section { margin: 20px 0; padding: 15px; border: 1px solid #ccc; border-radius: 5px; }
    button { margin: 5px; padding: 8px 16px; cursor: pointer; }
    video { width: 200px; margin: 5px; background: #000; }
    .streams { display: flex; flex-wrap: wrap; }
    .stream-item { margin: 10px; text-align: center; }
    .published-item { display: flex; align-items: center; margin: 5px 0; }
    .published-item span { margin-right: 10px; font-family: monospace; }
    #status { color: #666; font-size: 12px; margin-top: 10px; }
    .connected { color: green; }
    .disconnected { color: red; }
  </style>
</head>
<body>
  <h1>Pub/Sub Media Router</h1>

  <div class="section">
    <h3>Local</h3>
    <button id="publishBtn">Publish Camera</button>
    <video id="localVideo" autoplay muted playsinline></video>
  </div>

  <div class="section">
    <h3>Available Streams</h3>
    <div id="published"></div>
  </div>

  <div class="section">
    <h3>Subscribed Streams</h3>
    <div id="subscribed" class="streams"></div>
  </div>

  <div id="status">Connecting...</div>

<script>
const ws = new WebSocket('ws://' + location.host);
const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });

const published = new Map();  // media -> {isOwn: bool}
const subscribed = new Map(); // mid -> media
let trackBuffer = null;
let localStream = null;
let myPublishedMedia = null;

const log = msg => {
  console.log('[Client]', msg);
  document.getElementById('status').textContent = msg;
};

const send = (type, payload = {}) => {
  console.log('Sending:', type, payload);
  ws.send(JSON.stringify({ type, payload }));
};

ws.onopen = () => {
  log('Connected');
  document.getElementById('status').className = 'connected';
};

ws.onclose = () => {
  log('Disconnected');
  document.getElementById('status').className = 'disconnected';
};

ws.onmessage = async (ev) => {
  const { type, payload } = JSON.parse(ev.data);
  console.log('Received:', type, payload);

  try {
    switch (type) {
      case 'offer': {
        console.log('Processing offer...');
        await pc.setRemoteDescription({ type: 'offer', sdp: payload.sdp });
        console.log('Remote description set');

        // Set dummy transceiver to recvonly
        const transceivers = pc.getTransceivers();
        console.log('Transceivers:', transceivers.length);
        if (transceivers[0]) {
          transceivers[0].direction = 'recvonly';
        }

        // If we have a pending track to publish, attach it
        if (trackBuffer) {
          console.log('Attaching track to transceiver');
          const lastTransceiver = transceivers[transceivers.length - 1];
          if (lastTransceiver && lastTransceiver.sender) {
            await lastTransceiver.sender.replaceTrack(trackBuffer);
            lastTransceiver.direction = 'sendonly';
            console.log('Track attached, direction set to sendonly');
          }
          trackBuffer = null;
        }

        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        console.log('Created and set local answer');
        send('answer', { sdp: answer.sdp });
        break;
      }

    case 'onPublish': {
      const { media } = payload;
      const isOwn = (myPublishedMedia === null && trackBuffer === null && localStream);
      if (isOwn) myPublishedMedia = media;
      published.set(media, { isOwn: media === myPublishedMedia });
      updatePublishedUI();
      break;
    }

    case 'onUnPublish': {
      const { media } = payload;
      published.delete(media);
      if (media === myPublishedMedia) myPublishedMedia = null;
      updatePublishedUI();
      // Remove any subscribed streams for this media
      for (const [mid, m] of subscribed) {
        if (m === media) {
          subscribed.delete(mid);
          document.getElementById('stream-' + mid)?.remove();
        }
      }
      break;
    }

    case 'onSubscribe': {
      const { media, mid } = payload;
      subscribed.set(mid, media);
      break;
    }
  }
  } catch (err) {
    console.error('Error handling message:', type, err);
  }
};

pc.ontrack = (ev) => {
  const mid = ev.transceiver.mid;
  // Skip dummy transceivers (mid:0 is datachannel, mid:1 is initial sendonly video)
  if (mid === '0' || mid === '1') return;

  console.log('Received track:', mid);

  const media = subscribed.get(mid);
  const container = document.getElementById('subscribed');

  const div = document.createElement('div');
  div.id = 'stream-' + mid;
  div.className = 'stream-item';

  const video = document.createElement('video');
  video.autoplay = true;
  video.playsInline = true;
  video.muted = true; // Required for autoplay in most browsers
  video.srcObject = new MediaStream([ev.track]);

  // Debug video events
  video.onloadedmetadata = () => {
    console.log('Video loadedmetadata:', video.videoWidth, 'x', video.videoHeight);
    // Ensure video plays after metadata is loaded
    video.play().catch(e => console.error('Play failed:', e));
  };
  video.onloadeddata = () => console.log('Video loadeddata');
  video.onplay = () => console.log('Video play');
  video.ontimeupdate = () => console.log('Video timeupdate:', video.currentTime);
  video.onerror = (e) => console.error('Video error:', e);
  video.onstalled = () => console.log('Video stalled');
  video.onwaiting = () => console.log('Video waiting');

  // Also check track state
  console.log('Track readyState:', ev.track.readyState);
  console.log('Track enabled:', ev.track.enabled);
  console.log('Track muted:', ev.track.muted);

  const label = document.createElement('div');
  label.textContent = 'Media: ' + (media || mid);

  const btn = document.createElement('button');
  btn.textContent = 'Unsubscribe';
  btn.onclick = () => {
    send('unsubscribe', { mid });
    subscribed.delete(mid);
    div.remove();
  };

  div.appendChild(video);
  div.appendChild(label);
  div.appendChild(btn);
  container.appendChild(div);
};

pc.onconnectionstatechange = () => {
  log('Connection: ' + pc.connectionState);
};

document.getElementById('publishBtn').onclick = async () => {
  try {
    localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
    document.getElementById('localVideo').srcObject = localStream;

    const track = localStream.getVideoTracks()[0];
    trackBuffer = track;
    pc.addTrack(track);

    send('publish', { id: track.id });
    document.getElementById('publishBtn').disabled = true;
    document.getElementById('publishBtn').textContent = 'Publishing...';
  } catch (e) {
    log('Camera error: ' + e.message);
  }
};

function updatePublishedUI() {
  const container = document.getElementById('published');
  container.innerHTML = '';

  for (const [media, info] of published) {
    const div = document.createElement('div');
    div.className = 'published-item';

    const span = document.createElement('span');
    span.textContent = media + (info.isOwn ? ' (yours)' : '');
    div.appendChild(span);

    if (!info.isOwn) {
      const subBtn = document.createElement('button');
      subBtn.textContent = 'Subscribe';
      subBtn.onclick = () => send('subscribe', { media });
      div.appendChild(subBtn);
    } else {
      const unpubBtn = document.createElement('button');
      unpubBtn.textContent = 'Unpublish';
      unpubBtn.onclick = () => {
        send('unpublish', { media });
        if (localStream) {
          localStream.getTracks().forEach(t => t.stop());
          localStream = null;
        }
        document.getElementById('localVideo').srcObject = null;
        document.getElementById('publishBtn').disabled = false;
        document.getElementById('publishBtn').textContent = 'Publish Camera';
      };
      div.appendChild(unpubBtn);
    }

    container.appendChild(div);
  }

  if (published.size === 0) {
    container.innerHTML = '<em>No streams published yet</em>';
  }
}

updatePublishedUI();
</script>
</body>
</html>
''';

void main() async {
  final server = PubSubServer();
  await server.start(port: 8888);
}
