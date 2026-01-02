import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart' show SimulcastDirection;
import 'package:webrtc_dart/src/media/rtc_rtp_transceiver.dart';
import 'package:webrtc_dart/src/rtc_peer_connection.dart';
import 'package:webrtc_dart/src/rtp/header_extension.dart';
import 'package:webrtc_dart/src/sdp/rtx_sdp.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

/// SDPManager handles SDP building, parsing, and description state management.
///
/// This class matches the architecture of werift-webrtc's sdpManager.ts,
/// providing separation of concerns from the main PeerConnection class.
///
/// Responsibilities:
/// - Building offer/answer SDP from transceiver and SCTP state
/// - Parsing and validating SDP strings
/// - Managing pending/current description state
/// - Allocating unique media IDs (MIDs)
/// - Transport description generation
///
/// Reference: werift-webrtc/packages/webrtc/src/sdpManager.ts
class SdpManager {
  /// Current local description (after negotiation complete)
  RTCSessionDescription? currentLocalDescription;

  /// Current remote description (after negotiation complete)
  RTCSessionDescription? currentRemoteDescription;

  /// Pending local description (during negotiation)
  RTCSessionDescription? pendingLocalDescription;

  /// Pending remote description (during negotiation)
  RTCSessionDescription? pendingRemoteDescription;

  /// Canonical name for RTCP SDES
  final String cname;

  /// Bundle policy from RTCConfiguration
  final BundlePolicy bundlePolicy;

  /// Whether remote SDP uses bundling
  bool remoteIsBundled = false;

  /// Established m-line order (MIDs) after first negotiation.
  /// Used to preserve m-line order in subsequent offers per RFC 3264.
  List<String>? establishedMlineOrder;

  /// Set of allocated MIDs to prevent duplicates
  final Set<String> _seenMid = {};

  /// Next MID counter (starts at 1, 0 reserved for RTCDataChannel)
  int _nextMidCounter = 1;

  SdpManager({
    required this.cname,
    this.bundlePolicy = BundlePolicy.maxCompat,
  });

  /// Get the effective local description (pending takes precedence)
  RTCSessionDescription? get localDescriptionInternal =>
      pendingLocalDescription ?? currentLocalDescription;

  /// Get the effective remote description (pending takes precedence)
  RTCSessionDescription? get remoteDescriptionInternal =>
      pendingRemoteDescription ?? currentRemoteDescription;

  /// Get local description as RTCSessionDescription for public API
  RTCSessionDescription? get localDescription {
    final desc = localDescriptionInternal;
    if (desc == null) return null;
    return RTCSessionDescription(
      type: desc.type,
      sdp: desc.sdp,
    );
  }

  /// Get remote description as RTCSessionDescription for public API
  RTCSessionDescription? get remoteDescription {
    final desc = remoteDescriptionInternal;
    if (desc == null) return null;
    return RTCSessionDescription(
      type: desc.type,
      sdp: desc.sdp,
    );
  }

  /// Allocate a unique MID for a new media section
  /// Matches werift: allocateMid(type)
  String allocateMid({String suffix = ''}) {
    String mid;
    while (true) {
      mid = '${_nextMidCounter++}$suffix';
      if (!_seenMid.contains(mid)) break;
    }
    _seenMid.add(mid);
    return mid;
  }

  /// Register an existing MID (e.g., from remote SDP)
  /// Matches werift: registerMid(mid)
  void registerMid(String mid) {
    _seenMid.add(mid);
  }

  /// Set local description and update pending/current state
  /// Matches werift: setLocalDescription(description)
  void setLocalDescription(RTCSessionDescription description) {
    currentLocalDescription = description;
    if (description.type == 'answer') {
      pendingLocalDescription = null;
    } else {
      pendingLocalDescription = description;
    }
  }

  /// Set remote description and update pending/current state
  /// Returns the parsed RTCSessionDescription
  /// Matches werift: setRemoteDescription(sessionDescription, signalingState)
  RTCSessionDescription setRemoteDescription(
    RTCSessionDescription sessionDescription,
    SignalingState signalingState,
  ) {
    // Create and validate
    final remoteSdp = createDescription(
      sdp: sessionDescription.sdp,
      isLocal: false,
      signalingState: signalingState,
      type: sessionDescription.type,
    );

    if (remoteSdp.type == 'answer') {
      currentRemoteDescription = remoteSdp;
      pendingRemoteDescription = null;
    } else {
      pendingRemoteDescription = remoteSdp;
    }

    return remoteSdp;
  }

  /// Create and validate a RTCSessionDescription
  /// Matches werift: parseSdp({sdp, isLocal, signalingState, type})
  RTCSessionDescription createDescription({
    required String sdp,
    required bool isLocal,
    required SignalingState signalingState,
    required String type,
  }) {
    final description = RTCSessionDescription(type: type, sdp: sdp);
    validateDescription(
      description: description,
      isLocal: isLocal,
      signalingState: signalingState,
    );
    return description;
  }

  /// Validate description against signaling state machine
  /// Matches werift: validateDescription({description, isLocal, signalingState})
  void validateDescription({
    required RTCSessionDescription description,
    required bool isLocal,
    required SignalingState signalingState,
  }) {
    if (isLocal) {
      if (description.type == 'offer') {
        if (signalingState != SignalingState.stable &&
            signalingState != SignalingState.haveLocalOffer) {
          throw StateError(
              'Cannot handle offer in signaling state: $signalingState');
        }
      } else if (description.type == 'answer') {
        if (signalingState != SignalingState.haveRemoteOffer &&
            signalingState != SignalingState.haveLocalPranswer) {
          throw StateError(
              'Cannot handle answer in signaling state: $signalingState');
        }
      }
    } else {
      if (description.type == 'offer') {
        if (signalingState != SignalingState.stable &&
            signalingState != SignalingState.haveRemoteOffer) {
          throw StateError(
              'Cannot handle offer in signaling state: $signalingState');
        }
      } else if (description.type == 'answer') {
        if (signalingState != SignalingState.haveLocalOffer &&
            signalingState != SignalingState.haveRemotePranswer) {
          throw StateError(
              'Cannot handle answer in signaling state: $signalingState');
        }
      }
    }
  }

  /// Validate local description can be set in current signaling state
  /// Returns true if valid, throws if invalid
  void validateSetLocalDescription(
    String type,
    SignalingState signalingState,
  ) {
    // Rollback is always allowed
    if (type == 'rollback') {
      return;
    }

    switch (signalingState) {
      case SignalingState.stable:
        if (type != 'offer') {
          throw StateError('Can only set offer in stable state');
        }
        break;
      case SignalingState.haveLocalOffer:
        if (type != 'offer') {
          throw StateError('Can only set offer in have-local-offer state');
        }
        break;
      case SignalingState.haveRemoteOffer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-remote-offer state',
          );
        }
        break;
      case SignalingState.haveLocalPranswer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-local-pranswer state',
          );
        }
        break;
      case SignalingState.haveRemotePranswer:
        throw StateError(
          'Cannot set local description in have-remote-pranswer state',
        );
      case SignalingState.closed:
        throw StateError('PeerConnection is closed');
    }
  }

  /// Validate remote description can be set in current signaling state
  /// Returns true if valid, throws if invalid
  void validateSetRemoteDescription(
    String type,
    SignalingState signalingState,
  ) {
    // Rollback is always allowed
    if (type == 'rollback') {
      return;
    }

    switch (signalingState) {
      case SignalingState.stable:
        if (type != 'offer') {
          throw StateError('Can only set offer in stable state');
        }
        break;
      case SignalingState.haveLocalOffer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-local-offer state',
          );
        }
        break;
      case SignalingState.haveRemoteOffer:
        if (type != 'offer') {
          throw StateError('Can only set offer in have-remote-offer state');
        }
        break;
      case SignalingState.haveLocalPranswer:
        throw StateError(
          'Cannot set remote description in have-local-pranswer state',
        );
      case SignalingState.haveRemotePranswer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-remote-pranswer state',
          );
        }
        break;
      case SignalingState.closed:
        throw StateError('PeerConnection is closed');
    }
  }

  /// Build offer SDP from transceivers and transport state
  /// Matches werift: buildOfferSdp({transceivers, sctpTransport, iceCredentials, fingerprint})
  ///
  /// Parameters:
  /// - [transceivers]: List of RTP transceivers to include in the offer
  /// - [iceUfrag]: ICE username fragment
  /// - [icePwd]: ICE password
  /// - [dtlsFingerprint]: DTLS certificate fingerprint
  /// - [rtxSsrcByMid]: Map of MID -> RTX SSRC (will be updated with new entries)
  /// - [generateSsrc]: Callback to generate new SSRC values
  /// - [midExtensionId]: Extension ID for sdes:mid header extension
  /// - [perMidCredentials]: Optional per-MID ICE credentials for bundlePolicy:disable
  ///   If provided, each m-line uses its own iceUfrag/icePwd
  RTCSessionDescription buildOfferSdp({
    required List<RTCRtpTransceiver> transceivers,
    required String iceUfrag,
    required String icePwd,
    required String dtlsFingerprint,
    required Map<String, int> rtxSsrcByMid,
    required int Function() generateSsrc,
    int midExtensionId = 1,
    Map<String, ({String ufrag, String pwd})>? perMidCredentials,
  }) {
    final mediaDescriptions = <SdpMedia>[];
    final bundleMids = <String>[];

    // Add media lines for transceivers (audio/video)
    for (final transceiver in transceivers) {
      // Assign MID if not yet assigned (matches werift behavior)
      transceiver.mid ??= allocateMid();
      final mid = transceiver.mid!;
      bundleMids.add(mid);

      // Get all codecs for SDP (fallback to single primary codec)
      final allCodecs = transceiver.codecs.isNotEmpty
          ? transceiver.codecs
          : [transceiver.sender.codec];
      final primaryCodec = transceiver.sender.codec;
      final payloadType = primaryCodec.payloadType ?? 96;
      final ssrc = transceiver.sender.rtpSession.localSsrc;

      // Build format list with ALL payload types
      final formats = allCodecs.map((c) => '${c.payloadType ?? 96}').toList();

      // Build attributes list
      final directionStr = transceiver.direction.name;
      // Use per-MID credentials if available (for bundlePolicy:disable)
      final midUfrag = perMidCredentials?[mid]?.ufrag ?? iceUfrag;
      final midPwd = perMidCredentials?[mid]?.pwd ?? icePwd;
      final attributes = <SdpAttribute>[
        SdpAttribute(key: 'ice-ufrag', value: midUfrag),
        SdpAttribute(key: 'ice-pwd', value: midPwd),
        SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
        SdpAttribute(key: 'setup', value: 'actpass'),
        SdpAttribute(key: 'mid', value: mid),
        SdpAttribute(key: directionStr),
        SdpAttribute(key: 'rtcp-mux'),
        // Add sdes:mid header extension for media identification
        SdpAttribute(
          key: 'extmap',
          value: '$midExtensionId ${RtpExtensionUri.sdesMid}',
        ),
      ];

      // Add rtpmap, fmtp, and rtcp-fb for each codec
      for (final codec in allCodecs) {
        final pt = codec.payloadType ?? 96;
        attributes.add(SdpAttribute(
          key: 'rtpmap',
          value:
              '$pt ${codec.codecName}/${codec.clockRate}${codec.channels != null && codec.channels! > 1 ? '/${codec.channels}' : ''}',
        ));
        if (codec.parameters != null) {
          attributes
              .add(SdpAttribute(key: 'fmtp', value: '$pt ${codec.parameters}'));
        }
        for (final fb in codec.rtcpFeedback) {
          attributes.add(SdpAttribute(
            key: 'rtcp-fb',
            value: fb.parameter != null
                ? '$pt ${fb.type} ${fb.parameter}'
                : '$pt ${fb.type}',
          ));
        }
      }

      // Add RTX for video only (if not already configured by user)
      final hasUserRtx =
          allCodecs.any((c) => c.codecName.toLowerCase() == 'rtx');
      if (transceiver.kind == MediaStreamTrackKind.video && !hasUserRtx) {
        // Generate or retrieve RTX SSRC
        final rtxSsrc = rtxSsrcByMid[mid] ?? generateSsrc();
        rtxSsrcByMid[mid] = rtxSsrc;

        // RTX payload type must be unique - use max(all codec PTs) + 1
        final maxPt = allCodecs
            .map((c) => c.payloadType ?? 96)
            .reduce((a, b) => a > b ? a : b);
        final rtxPayloadType = maxPt + 1;
        formats.add('$rtxPayloadType');

        // Add RTX attributes using RtxSdpBuilder
        attributes.addAll([
          RtxSdpBuilder.createRtxRtpMap(
            rtxPayloadType,
            clockRate: primaryCodec.clockRate,
          ),
          RtxSdpBuilder.createRtxFmtp(rtxPayloadType, payloadType),
          RtxSdpBuilder.createSsrcGroupFid(ssrc, rtxSsrc),
        ]);

        // Add SSRC attributes for original
        attributes.add(SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'));

        // Add SSRC attributes for RTX
        attributes.add(RtxSdpBuilder.createSsrcCname(rtxSsrc, cname));
      } else if (transceiver.kind == MediaStreamTrackKind.video && hasUserRtx) {
        // User provided RTX, just add SSRC cname (RTX is already in codec list)
        final rtxSsrc = rtxSsrcByMid[mid] ?? generateSsrc();
        rtxSsrcByMid[mid] = rtxSsrc;
        attributes.add(SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'));
        attributes.add(RtxSdpBuilder.createSsrcGroupFid(ssrc, rtxSsrc));
        attributes.add(RtxSdpBuilder.createSsrcCname(rtxSsrc, cname));
      } else {
        // Audio: just add SSRC cname
        attributes.add(SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'));
      }

      // Add simulcast attributes if layers are configured
      final simulcastLayers = transceiver.simulcast;
      if (simulcastLayers.isNotEmpty) {
        // Add RID header extension (required for simulcast)
        const ridExtensionId = 10;
        attributes.add(SdpAttribute(
          key: 'extmap',
          value: '$ridExtensionId ${RtpExtensionUri.sdesRtpStreamId}',
        ));

        // Add a=rid:<rid> <direction> for each layer
        for (final layer in simulcastLayers) {
          final dirStr =
              layer.direction == SimulcastDirection.send ? 'send' : 'recv';
          attributes
              .add(SdpAttribute(key: 'rid', value: '${layer.rid} $dirStr'));
        }

        // Build a=simulcast: line
        final recvRids = simulcastLayers
            .where((l) => l.direction == SimulcastDirection.recv)
            .map((l) => l.rid)
            .toList();
        final sendRids = simulcastLayers
            .where((l) => l.direction == SimulcastDirection.send)
            .map((l) => l.rid)
            .toList();

        final simulcastParts = <String>[];
        if (recvRids.isNotEmpty) {
          simulcastParts.add('recv ${recvRids.join(";")}');
        }
        if (sendRids.isNotEmpty) {
          simulcastParts.add('send ${sendRids.join(";")}');
        }
        if (simulcastParts.isNotEmpty) {
          attributes.add(
              SdpAttribute(key: 'simulcast', value: simulcastParts.join(' ')));
        }
      }

      mediaDescriptions.add(
        SdpMedia(
          type: transceiver.kind == MediaStreamTrackKind.audio
              ? 'audio'
              : 'video',
          port: 9,
          protocol: 'UDP/TLS/RTP/SAVPF',
          formats: formats,
          connection: const SdpConnection(connectionAddress: '0.0.0.0'),
          attributes: attributes,
        ),
      );
    }

    // Add application media for data channel
    // Skip for bundlePolicy:disable unless explicit data channel support is needed
    // Each m-line would need its own transport for bundlePolicy:disable
    if (bundlePolicy != BundlePolicy.disable) {
      const dataChannelMid = '0';
      if (!bundleMids.contains(dataChannelMid)) {
        bundleMids.add(dataChannelMid);
      }
      mediaDescriptions.add(
        SdpMedia(
          type: 'application',
          port: 9,
          protocol: 'UDP/DTLS/SCTP',
          formats: ['webrtc-datachannel'],
          connection: const SdpConnection(connectionAddress: '0.0.0.0'),
          attributes: [
            SdpAttribute(key: 'ice-ufrag', value: iceUfrag),
            SdpAttribute(key: 'ice-pwd', value: icePwd),
            SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
            SdpAttribute(key: 'setup', value: 'actpass'),
            SdpAttribute(key: 'mid', value: dataChannelMid),
            SdpAttribute(key: 'sctp-port', value: '5000'),
          ],
        ),
      );
    }

    // Preserve m-line order from first negotiation (RFC 3264 requirement)
    if (establishedMlineOrder != null && establishedMlineOrder!.isNotEmpty) {
      final orderedDescriptions = <SdpMedia>[];
      final usedMids = <String>{};

      // First, add m-lines in their established order
      for (final mid in establishedMlineOrder!) {
        final desc = mediaDescriptions.firstWhere(
          (m) => m.getAttributeValue('mid') == mid,
          orElse: () => SdpMedia(
            type: 'video',
            port: 0,
            protocol: 'UDP/TLS/RTP/SAVPF',
            formats: ['0'],
            attributes: [SdpAttribute(key: 'mid', value: mid)],
          ),
        );
        orderedDescriptions.add(desc);
        usedMids.add(mid);
      }

      // Then, append any new m-lines not in the established order
      for (final desc in mediaDescriptions) {
        final mid = desc.getAttributeValue('mid') ?? '';
        if (!usedMids.contains(mid)) {
          orderedDescriptions.add(desc);
        }
      }

      // Replace with reordered list
      mediaDescriptions
        ..clear()
        ..addAll(orderedDescriptions);
    }

    // Build session-level attributes
    final sessionAttributes = <SdpAttribute>[
      SdpAttribute(key: 'ice-options', value: 'trickle'),
    ];

    // Add BUNDLE group unless bundlePolicy is disable
    if (bundlePolicy != BundlePolicy.disable && bundleMids.isNotEmpty) {
      sessionAttributes.insert(
        0,
        SdpAttribute(key: 'group', value: 'BUNDLE ${bundleMids.join(' ')}'),
      );
    }

    // Build SDP message
    final sdpMessage = SdpMessage(
      version: 0,
      origin: SdpOrigin(
        username: '-',
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionVersion: '2',
        unicastAddress: '0.0.0.0',
      ),
      sessionName: '-',
      connection: const SdpConnection(connectionAddress: '0.0.0.0'),
      timing: [SdpTiming(startTime: 0, stopTime: 0)],
      attributes: sessionAttributes,
      mediaDescriptions: mediaDescriptions,
    );

    final sdp = sdpMessage.serialize();
    return RTCSessionDescription(type: 'offer', sdp: sdp);
  }

  /// Build answer SDP matching remote offer
  /// Matches werift: buildAnswerSdp({remoteSdp, transceivers, iceCredentials, fingerprint})
  ///
  /// Parameters:
  /// - [remoteSdp]: Parsed remote SDP message (from offer)
  /// - [transceivers]: List of RTP transceivers for SSRC lookup
  /// - [iceUfrag]: ICE username fragment
  /// - [icePwd]: ICE password
  /// - [dtlsFingerprint]: DTLS certificate fingerprint
  /// - [rtxSsrcByMid]: Map of MID -> RTX SSRC (will be updated with new entries)
  /// - [generateSsrc]: Callback to generate new SSRC values
  RTCSessionDescription buildAnswerSdp({
    required SdpMessage remoteSdp,
    required List<RTCRtpTransceiver> transceivers,
    required String iceUfrag,
    required String icePwd,
    required String dtlsFingerprint,
    required Map<String, int> rtxSsrcByMid,
    required int Function() generateSsrc,
  }) {
    final mediaDescriptions = <SdpMedia>[];
    final bundleMids = <String>[];

    for (final remoteMedia in remoteSdp.mediaDescriptions) {
      final mid = remoteMedia.getAttributeValue('mid') ?? '0';
      bundleMids.add(mid);

      // Build attributes based on media type
      final attributes = <SdpAttribute>[
        SdpAttribute(key: 'ice-ufrag', value: iceUfrag),
        SdpAttribute(key: 'ice-pwd', value: icePwd),
        SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
        SdpAttribute(key: 'setup', value: 'active'),
        SdpAttribute(key: 'mid', value: mid),
      ];

      if (remoteMedia.type == 'application') {
        // RTCDataChannel media line
        attributes.add(SdpAttribute(key: 'sctp-port', value: '5000'));
      } else if (remoteMedia.type == 'audio' || remoteMedia.type == 'video') {
        // Audio/video media line
        attributes.addAll([
          SdpAttribute(key: 'sendrecv'),
          SdpAttribute(key: 'rtcp-mux'),
        ]);

        // Copy rtpmap and fmtp from remote offer
        for (final attr in remoteMedia.getAttributes('rtpmap')) {
          attributes.add(attr);
        }
        for (final attr in remoteMedia.getAttributes('fmtp')) {
          attributes.add(attr);
        }

        // Copy extmap (header extensions) from remote offer
        for (final attr in remoteMedia.getAttributes('extmap')) {
          attributes.add(attr);
        }

        // Copy rtcp-fb (RTCP feedback) from remote offer
        for (final attr in remoteMedia.getAttributes('rtcp-fb')) {
          attributes.add(attr);
        }

        // Add local SSRC if we have a transceiver for this media
        final transceiver = transceivers.where((t) => t.mid == mid).firstOrNull;
        if (transceiver != null) {
          final ssrc = transceiver.sender.rtpSession.localSsrc;

          // Check if remote offer includes RTX for video
          if (remoteMedia.type == 'video') {
            final rtxCodecs = remoteMedia.getRtxCodecs();
            if (rtxCodecs.isNotEmpty) {
              // Remote supports RTX, generate our RTX SSRC
              final rtxSsrc = rtxSsrcByMid[mid] ?? generateSsrc();
              rtxSsrcByMid[mid] = rtxSsrc;

              // Add ssrc-group FID (original, rtx)
              attributes.add(RtxSdpBuilder.createSsrcGroupFid(ssrc, rtxSsrc));

              // Add SSRC cname for original
              attributes.add(
                SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'),
              );

              // Add SSRC cname for RTX
              attributes.add(RtxSdpBuilder.createSsrcCname(rtxSsrc, cname));
            } else {
              // No RTX, just add SSRC cname
              attributes.add(
                SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'),
              );
            }
          } else {
            // Audio: just add SSRC cname
            attributes.add(
              SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'),
            );
          }
        }
      }

      mediaDescriptions.add(
        SdpMedia(
          type: remoteMedia.type,
          port: 9,
          protocol: remoteMedia.protocol,
          formats: remoteMedia.formats,
          connection: const SdpConnection(connectionAddress: '0.0.0.0'),
          attributes: attributes,
        ),
      );
    }

    // Build session-level attributes
    final sessionAttributes = <SdpAttribute>[
      SdpAttribute(key: 'ice-options', value: 'trickle'),
    ];

    // Add BUNDLE group unless bundlePolicy is disable
    if (bundlePolicy != BundlePolicy.disable && bundleMids.isNotEmpty) {
      sessionAttributes.insert(
        0,
        SdpAttribute(key: 'group', value: 'BUNDLE ${bundleMids.join(' ')}'),
      );
    }

    final sdpMessage = SdpMessage(
      version: 0,
      origin: SdpOrigin(
        username: '-',
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionVersion: '2',
        unicastAddress: '0.0.0.0',
      ),
      sessionName: '-',
      connection: const SdpConnection(connectionAddress: '0.0.0.0'),
      timing: [SdpTiming(startTime: 0, stopTime: 0)],
      attributes: sessionAttributes,
      mediaDescriptions: mediaDescriptions,
    );

    final sdp = sdpMessage.serialize();
    return RTCSessionDescription(type: 'answer', sdp: sdp);
  }
}
