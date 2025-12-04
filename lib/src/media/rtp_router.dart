/// RTP Router
/// Routes incoming RTP/RTCP packets to the appropriate receiver based on
/// SSRC or RID (for simulcast).
library;

import '../rtp/header_extension.dart';
import '../sdp/sdp.dart' show RtpHeaderExtension;
import '../srtp/rtp_packet.dart';
import 'media_stream_track.dart';
import 'parameters.dart';

/// Callback for handling routed RTP packets
typedef RtpPacketHandler = void Function(
    RtpPacket packet, String? rid, Map<String, dynamic> extensions);

/// Callback for creating a new track for a simulcast layer
typedef TrackFactory = MediaStreamTrack Function(
    String rid, MediaStreamTrackKind kind);

/// RTP Router
/// Routes RTP packets to receivers based on SSRC or RID.
/// Supports simulcast by routing packets to different tracks based on RID.
class RtpRouter {
  /// SSRC to handler mapping
  final Map<int, RtpPacketHandler> _ssrcTable = {};

  /// RID to handler mapping (for simulcast)
  final Map<String, RtpPacketHandler> _ridTable = {};

  /// Extension ID to URI mapping (from SDP negotiation)
  final Map<int, String> _extIdUriMap = {};

  /// Tracks by RID (for simulcast receivers)
  final Map<String, MediaStreamTrack> _tracksByRid = {};

  /// Tracks by SSRC
  final Map<int, MediaStreamTrack> _tracksBySsrc = {};

  /// Callback for new track creation
  void Function(MediaStreamTrack track)? onTrack;

  RtpRouter();

  /// Register extension ID to URI mapping from SDP header extensions
  void registerHeaderExtensions(List<RtpHeaderExtension> extensions) {
    for (final ext in extensions) {
      _extIdUriMap[ext.id] = ext.uri;
    }
  }

  /// Register a handler for a specific SSRC
  void registerBySsrc(int ssrc, RtpPacketHandler handler) {
    _ssrcTable[ssrc] = handler;
  }

  /// Register a handler for a specific RID (simulcast layer)
  void registerByRid(String rid, RtpPacketHandler handler) {
    _ridTable[rid] = handler;
  }

  /// Register a track by SSRC
  void registerTrackBySsrc(int ssrc, MediaStreamTrack track) {
    _tracksBySsrc[ssrc] = track;
  }

  /// Register a track by RID (for simulcast)
  void registerTrackByRid(String rid, MediaStreamTrack track) {
    _tracksByRid[rid] = track;
  }

  /// Get track by RID
  MediaStreamTrack? getTrackByRid(String rid) => _tracksByRid[rid];

  /// Get track by SSRC
  MediaStreamTrack? getTrackBySsrc(int ssrc) => _tracksBySsrc[ssrc];

  /// Get all registered RIDs
  List<String> get registeredRids => _ridTable.keys.toList();

  /// Get all registered SSRCs
  List<int> get registeredSsrcs => _ssrcTable.keys.toList();

  /// Route an incoming RTP packet to the appropriate handler
  void routeRtp(RtpPacket packet) {
    // Parse header extensions
    final extensions = _parseExtensions(packet);

    // Try to find handler by RID first (simulcast)
    final rid = extensions[RtpExtensionUri.sdesRtpStreamId] as String?;
    if (rid != null && _ridTable.containsKey(rid)) {
      final handler = _ridTable[rid]!;
      handler(packet, rid, extensions);

      // Auto-register SSRC to RID mapping for future packets without RID extension
      if (!_ssrcTable.containsKey(packet.ssrc)) {
        _ssrcTable[packet.ssrc] = handler;
      }
      return;
    }

    // Try to find handler by SSRC
    final ssrc = packet.ssrc;
    if (_ssrcTable.containsKey(ssrc)) {
      final handler = _ssrcTable[ssrc]!;
      handler(packet, null, extensions);
      return;
    }

    // Packet from unknown source - could be a new simulcast stream
    // Try to find a matching RID handler that already knows this SSRC
    for (final entry in _ridTable.entries) {
      final ridHandler = entry.value;
      // If we have a track registered for this RID that matches SSRC
      final track = _tracksByRid[entry.key];
      if (track != null) {
        // Register for future lookups and route
        _ssrcTable[ssrc] = ridHandler;
        ridHandler(packet, entry.key, extensions);
        return;
      }
    }

    // Unknown packet - drop or log
  }

  /// Parse RTP header extensions from packet
  Map<String, dynamic> _parseExtensions(RtpPacket packet) {
    if (!packet.extension || packet.extensionHeader == null) {
      return {};
    }

    // Convert extension ID map to use RtpExtensionUri
    final idToUri = <int, String>{};
    for (final entry in _extIdUriMap.entries) {
      idToUri[entry.key] = entry.value;
    }

    return parseRtpExtensions(packet.extensionHeader!.data, idToUri);
  }

  /// Clear all registrations
  void clear() {
    _ssrcTable.clear();
    _ridTable.clear();
    _tracksByRid.clear();
    _tracksBySsrc.clear();
  }

  @override
  String toString() {
    return 'RtpRouter(ssrcs=${_ssrcTable.keys.length}, rids=${_ridTable.keys.length})';
  }
}

/// Simulcast layer configuration
class SimulcastLayer {
  /// Restriction Identifier
  final String rid;

  /// Direction (send or recv)
  final SimulcastDirection direction;

  /// Associated SSRC (may be learned dynamically)
  int? ssrc;

  /// Associated track
  MediaStreamTrack? track;

  /// Whether this layer is active
  bool active;

  SimulcastLayer({
    required this.rid,
    required this.direction,
    this.ssrc,
    this.track,
    this.active = true,
  });

  @override
  String toString() {
    return 'SimulcastLayer(rid=$rid, direction=$direction, ssrc=$ssrc, active=$active)';
  }
}

/// Simulcast stream manager
/// Manages multiple simulcast layers for a single transceiver
class SimulcastManager {
  /// Layers by RID
  final Map<String, SimulcastLayer> _layers = {};

  /// RTP router for packet routing
  final RtpRouter router;

  /// Track kind (audio/video)
  final MediaStreamTrackKind kind;

  /// Callback when a new track is created for a layer
  void Function(MediaStreamTrack track, String rid)? onTrack;

  SimulcastManager({
    required this.router,
    required this.kind,
  });

  /// Add a simulcast layer
  void addLayer(RTCRtpSimulcastParameters params) {
    final layer = SimulcastLayer(
      rid: params.rid,
      direction: params.direction,
    );
    _layers[params.rid] = layer;

    // Register with router for receiving
    if (params.direction == SimulcastDirection.recv) {
      router.registerByRid(params.rid, _handleRtpPacket);
    }
  }

  /// Get layer by RID
  SimulcastLayer? getLayer(String rid) => _layers[rid];

  /// Get all layers
  List<SimulcastLayer> get layers => _layers.values.toList();

  /// Get active layers
  List<SimulcastLayer> get activeLayers =>
      _layers.values.where((l) => l.active).toList();

  /// Handle incoming RTP packet for a simulcast layer
  void _handleRtpPacket(
      RtpPacket packet, String? rid, Map<String, dynamic> extensions) {
    if (rid == null) return;

    final layer = _layers[rid];
    if (layer == null) return;

    // Learn SSRC from first packet
    layer.ssrc ??= packet.ssrc;

    // Create track if needed
    if (layer.track == null) {
      layer.track = _createTrack(rid);
      router.registerTrackByRid(rid, layer.track!);
      onTrack?.call(layer.track!, rid);
    }

    // Forward to track (track handlers will process the packet)
  }

  /// Create a track for a simulcast layer
  MediaStreamTrack _createTrack(String rid) {
    if (kind == MediaStreamTrackKind.audio) {
      return AudioStreamTrack(
        id: 'audio_$rid',
        label: 'Audio ($rid)',
        rid: rid,
      );
    } else {
      return VideoStreamTrack(
        id: 'video_$rid',
        label: 'Video ($rid)',
        rid: rid,
      );
    }
  }

  /// Set layer active state
  void setLayerActive(String rid, bool active) {
    final layer = _layers[rid];
    if (layer != null) {
      layer.active = active;
    }
  }

  /// Select a single layer (deactivate others)
  void selectLayer(String rid) {
    for (final entry in _layers.entries) {
      entry.value.active = entry.key == rid;
    }
  }

  @override
  String toString() {
    return 'SimulcastManager(layers=${_layers.length}, kind=$kind)';
  }
}
