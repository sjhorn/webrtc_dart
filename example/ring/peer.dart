/// Custom Peer Connection for Ring cameras
///
/// Dart port of werift-webrtc/examples/ring/peer.ts
///
/// This class implements the BasicPeerConnection interface from ring_client_api
/// and exposes RTP/RTCP streams for forwarding video to browser clients.
library;

import 'dart:async';
import 'dart:io';

import 'package:ring_client_api/ring_client_api.dart' as ring;
import 'package:rxdart/rxdart.dart';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

/// Debug flag - set RING_DEBUG=1 to enable verbose logging
final bool _debug = Platform.environment['RING_DEBUG'] == '1';
void _log(String msg) {
  if (_debug) print(msg);
}

/// ICE server URLs used by Ring cameras
const ringIceServers = [
  'stun:stun.kinesisvideo.us-east-1.amazonaws.com:443',
  'stun:stun.kinesisvideo.us-east-2.amazonaws.com:443',
  'stun:stun.kinesisvideo.us-west-2.amazonaws.com:443',
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:stun2.l.google.com:19302',
  'stun:stun3.l.google.com:19302',
  'stun:stun4.l.google.com:19302',
];

/// Custom peer connection for Ring cameras that exposes RTP streams
///
/// This matches the TypeScript werift CustomPeerConnection in peer.ts:
/// ```typescript
/// export class CustomPeerConnection implements BasicPeerConnection {
///   onAudioRtp = new Subject<RtpPacket>();
///   onVideoRtp = new Subject<RtpPacket>();
///   // ...
/// }
/// ```
class CustomPeerConnection implements ring.BasicPeerConnection {
  // RTP/RTCP streams (like TypeScript Subject<RtpPacket>)
  final onAudioRtp = PublishSubject<RtpPacket>();
  final onAudioRtcp = PublishSubject<dynamic>();
  final onVideoRtp = PublishSubject<RtpPacket>();
  final onVideoRtcp = PublishSubject<dynamic>();

  // BasicPeerConnection interface streams
  final _onIceCandidateController = PublishSubject<ring.RTCIceCandidate>();
  final _onConnectionStateController = ReplaySubject<ring.ConnectionState>(
    maxSize: 1,
  );

  @override
  Stream<ring.RTCIceCandidate> get onIceCandidate =>
      _onIceCandidateController.stream;

  @override
  Stream<ring.ConnectionState> get onConnectionState =>
      _onConnectionStateController.stream;

  /// The underlying webrtc_dart peer connection
  late final RtcPeerConnection _pc;

  /// Video transceiver (stored for PLI requests)
  RtpTransceiver? _videoTransceiver;

  /// Video media SSRC (Ring's video stream SSRC, captured from first RTP packet)
  int? _videoMediaSsrc;

  /// Return audio track for two-way communication
  final returnAudioTrack = nonstandard.MediaStreamTrack(
    kind: nonstandard.MediaKind.audio,
    id: 'return_audio',
  );

  /// Subscriptions to clean up
  final _subscriptions = <StreamSubscription>[];

  /// Whether peer connection is closed
  bool _closed = false;

  CustomPeerConnection() {
    // const pc = new RTCPeerConnection({
    //   codecs: { video: [...] },
    //   iceTransportPolicy: "all",
    //   bundlePolicy: "disable",
    // });
    _pc = RtcPeerConnection(
      RtcConfiguration(
        iceServers:
            ringIceServers.map((server) => IceServer(urls: [server])).toList(),
        codecs: RtcCodecs(
          audio: [
            createPcmuCodec(), // PCMU (G.711 μ-law) 8kHz mono - Ring audio codec
          ],
          video: [
            createH264Codec(
              payloadType: 96,
              parameters:
                  'packetization-mode=1;profile-level-id=640029;level-asymmetry-allowed=1',
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
        iceTransportPolicy: IceTransportPolicy.all,
        bundlePolicy: BundlePolicy.disable,
      ),
    );

    // audioTransceiver = pc.addTransceiver(this.returnAudioTrack, { direction: "sendrecv" });
    _pc.addTransceiver(
      returnAudioTrack,
      direction: RtpTransceiverDirection.sendrecv,
    );

    // videoTransceiver = pc.addTransceiver("video", { direction: "recvonly" });
    _videoTransceiver = _pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Subscribe to ICE candidates
    // this.pc.onIceCandidate.subscribe((iceCandidate) => { ... });
    _subscriptions.add(
      _pc.onIceCandidate.listen((candidate) {
        if (!_closed) {
          _onIceCandidateController.add(
            ring.RTCIceCandidate(
              candidate: candidate.toSdp(),
              // Use the sdpMLineIndex from the candidate (set by peer_connection for bundlePolicy:disable)
              sdpMLineIndex: candidate.sdpMLineIndex ?? 0,
            ),
          );
        }
      }),
    );

    // Subscribe to connection state changes
    // pc.connectionStateChange.subscribe(() => { ... });
    _subscriptions.add(
      _pc.onConnectionStateChange.listen((state) {
        if (_closed) return;
        _onConnectionStateController.add(_mapConnectionState(state));
      }),
    );

    // pc.iceConnectionStateChange.subscribe(() => { ... });
    _subscriptions.add(
      _pc.onIceConnectionStateChange.listen((state) {
        if (_closed) return;
        if (state == IceConnectionState.closed) {
          _onConnectionStateController.add(ring.ConnectionState.closed);
        }
      }),
    );

    // Subscribe to track events
    // videoTransceiver.onTrack.subscribe((track) => { ... });
    _subscriptions.add(
      _pc.onTrack.listen((transceiver) {
        final receiver = transceiver.receiver;
        final track = receiver.track;
        _log(
            '[CustomPC] onTrack: kind=${transceiver.kind}, mid=${transceiver.mid}');

        if (transceiver.kind == MediaStreamTrackKind.audio) {
          _log('[CustomPC] Setting up audio track listener');
          // audioTransceiver.onTrack.subscribe((track) => {
          //   track.onReceiveRtp.subscribe((rtp) => this.onAudioRtp.next(rtp));
          //   track.onReceiveRtcp.subscribe((rtcp) => this.onAudioRtcp.next(rtcp));
          // });
          _subscriptions.add(
            track.onReceiveRtp.listen((rtp) {
              if (!_closed) onAudioRtp.add(rtp);
            }),
          );
          _subscriptions.add(
            track.onReceiveRtcp.listen((rtcp) {
              if (!_closed) onAudioRtcp.add(rtcp);
            }),
          );
        } else if (transceiver.kind == MediaStreamTrackKind.video) {
          // videoTransceiver.onTrack.subscribe((track) => {
          //   track.onReceiveRtp.subscribe((rtp) => this.onVideoRtp.next(rtp));
          //   track.onReceiveRtcp.subscribe((rtcp) => this.onVideoRtcp.next(rtcp));
          // });
          _subscriptions.add(
            track.onReceiveRtp.listen((rtp) {
              if (!_closed) onVideoRtp.add(rtp);
            }),
          );
          _subscriptions.add(
            track.onReceiveRtcp.listen((rtcp) {
              if (!_closed) onVideoRtcp.add(rtcp);
            }),
          );

          // track.onReceiveRtp.once(() => {
          //   setInterval(() => videoTransceiver.receiver.sendRtcpPLI(track.ssrc!), 2000);
          // });
          Timer? pliTimer;
          _subscriptions.add(
            track.onReceiveRtp.listen((rtp) {
              if (_videoMediaSsrc == null) {
                _videoMediaSsrc = rtp.ssrc;
                // Send PLI every 2 seconds (matching TypeScript werift)
                pliTimer =
                    Timer.periodic(const Duration(seconds: 2), (_) async {
                  if (!_closed && _videoMediaSsrc != null) {
                    try {
                      await _videoTransceiver?.receiver.rtpSession
                          .sendPli(_videoMediaSsrc!);
                    } catch (e) {
                      // Ignore PLI send failures - video still works without PLI
                    }
                  }
                });
              }
            }),
          );

          // Clean up timer on close
          _subscriptions.add(
            _onConnectionStateController.stream
                .where((state) => state == ring.ConnectionState.closed)
                .listen((_) => pliTimer?.cancel()),
          );
        }
      }),
    );
  }

  /// Map webrtc_dart PeerConnectionState to ring ConnectionState
  ring.ConnectionState _mapConnectionState(PeerConnectionState state) {
    switch (state) {
      case PeerConnectionState.new_:
        return ring.ConnectionState.new_;
      case PeerConnectionState.connecting:
        return ring.ConnectionState.connecting;
      case PeerConnectionState.connected:
        return ring.ConnectionState.connected;
      case PeerConnectionState.disconnected:
        return ring.ConnectionState.disconnected;
      case PeerConnectionState.failed:
        return ring.ConnectionState.failed;
      case PeerConnectionState.closed:
        return ring.ConnectionState.closed;
    }
  }

  // async createOffer() {
  //   const offer = await this.pc.createOffer();
  //   await this.pc.setLocalDescription(offer);
  //   return offer;
  // }
  @override
  Future<ring.SessionDescription> createOffer() async {
    final offer = await _pc.createOffer();
    await _pc.setLocalDescription(offer);
    return ring.SessionDescription(type: 'offer', sdp: offer.sdp);
  }

  // async createAnswer(offer: { type: "offer"; sdp: string }) {
  //   await this.pc.setRemoteDescription(offer);
  //   const answer = await this.pc.createAnswer();
  //   await this.pc.setLocalDescription(answer);
  //   return answer;
  // }
  Future<ring.SessionDescription> createAnswer(
    ring.SessionDescription offer,
  ) async {
    await _pc.setRemoteDescription(
      SessionDescription(type: 'offer', sdp: offer.sdp),
    );
    final answer = await _pc.createAnswer();
    await _pc.setLocalDescription(answer);
    return ring.SessionDescription(type: 'answer', sdp: answer.sdp);
  }

  // async acceptAnswer(answer: { type: "answer"; sdp: string }) {
  //   await this.pc.setRemoteDescription(answer);
  // }
  @override
  Future<void> acceptAnswer(ring.SessionDescription answer) async {
    await _pc.setRemoteDescription(
      SessionDescription(type: 'answer', sdp: answer.sdp),
    );
  }

  // addIceCandidate(candidate: RTCIceCandidate) {
  //   return this.pc.addIceCandidate(candidate);
  // }
  @override
  Future<void> addIceCandidate(ring.RTCIceCandidate candidate) async {
    final parsedCandidate = Candidate.fromSdp(candidate.candidate);
    await _pc.addIceCandidate(parsedCandidate);
  }

  @override
  void requestKeyFrame() {
    // Send PLI to Ring to request a keyframe immediately
    if (_closed || _videoMediaSsrc == null || _videoTransceiver == null) {
      return;
    }
    try {
      _videoTransceiver!.receiver.rtpSession.sendPli(_videoMediaSsrc!);
      _log('[CustomPC] Sent PLI to Ring');
    } catch (e) {
      _log('[CustomPC] Error sending PLI: $e');
    }
  }

  // close() {
  //   this.pc.close().catch(() => {});
  // }
  @override
  void close() {
    if (_closed) return;
    _closed = true;

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    _pc.close();
    _onIceCandidateController.close();
    _onConnectionStateController.close();
    onAudioRtp.close();
    onAudioRtcp.close();
    onVideoRtp.close();
    onVideoRtcp.close();
  }
}
