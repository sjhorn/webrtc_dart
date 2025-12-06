/// SVC (Scalable Video Coding) Manager for VP9
///
/// Provides layer selection and filtering for VP9 SVC streams.
/// VP9 SVC uses a single SSRC with multiple spatial and temporal layers,
/// unlike simulcast which uses multiple SSRCs.
library;

import 'dart:typed_data';
import '../codec/vp9.dart';

/// Scalability mode parsed from SDP or encoding parameters
///
/// Format: L{spatial}T{temporal}[_KEY]
/// Examples:
/// - "L1T1" - 1 spatial layer, 1 temporal layer (no SVC)
/// - "L1T2" - 1 spatial layer, 2 temporal layers
/// - "L1T3" - 1 spatial layer, 3 temporal layers
/// - "L2T1" - 2 spatial layers, 1 temporal layer
/// - "L2T2" - 2 spatial layers, 2 temporal layers
/// - "L2T3" - 2 spatial layers, 3 temporal layers
/// - "L3T3" - 3 spatial layers, 3 temporal layers
/// - "L2T2_KEY" - With key-frame dependency mode
class ScalabilityMode {
  /// Number of spatial layers (1-8)
  final int spatialLayers;

  /// Number of temporal layers (1-8)
  final int temporalLayers;

  /// Key-frame dependency mode (suffix _KEY)
  final bool keyMode;

  /// Maximum spatial layer index (0-based)
  int get maxSpatialId => spatialLayers - 1;

  /// Maximum temporal layer index (0-based)
  int get maxTemporalId => temporalLayers - 1;

  /// Check if this is a true SVC mode (more than 1 layer)
  bool get isSvc => spatialLayers > 1 || temporalLayers > 1;

  const ScalabilityMode({
    required this.spatialLayers,
    required this.temporalLayers,
    this.keyMode = false,
  });

  /// Parse scalability mode string
  ///
  /// Returns null if format is invalid
  static ScalabilityMode? parse(String mode) {
    final upperMode = mode.toUpperCase();

    // Check for _KEY suffix
    final keyMode = upperMode.endsWith('_KEY');
    final cleanMode =
        keyMode ? upperMode.substring(0, upperMode.length - 4) : upperMode;

    // Parse L{S}T{T} format
    final match = RegExp(r'^L(\d)T(\d)$').firstMatch(cleanMode);
    if (match == null) return null;

    final spatial = int.tryParse(match.group(1)!);
    final temporal = int.tryParse(match.group(2)!);

    if (spatial == null ||
        temporal == null ||
        spatial < 1 ||
        spatial > 8 ||
        temporal < 1 ||
        temporal > 8) {
      return null;
    }

    return ScalabilityMode(
      spatialLayers: spatial,
      temporalLayers: temporal,
      keyMode: keyMode,
    );
  }

  /// Serialize to string format
  String serialize() {
    return 'L${spatialLayers}T$temporalLayers${keyMode ? '_KEY' : ''}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScalabilityMode &&
          spatialLayers == other.spatialLayers &&
          temporalLayers == other.temporalLayers &&
          keyMode == other.keyMode;

  @override
  int get hashCode =>
      spatialLayers.hashCode ^ temporalLayers.hashCode ^ keyMode.hashCode;

  @override
  String toString() => 'ScalabilityMode(${serialize()})';

  /// Common scalability modes
  static const l1t1 = ScalabilityMode(spatialLayers: 1, temporalLayers: 1);
  static const l1t2 = ScalabilityMode(spatialLayers: 1, temporalLayers: 2);
  static const l1t3 = ScalabilityMode(spatialLayers: 1, temporalLayers: 3);
  static const l2t1 = ScalabilityMode(spatialLayers: 2, temporalLayers: 1);
  static const l2t2 = ScalabilityMode(spatialLayers: 2, temporalLayers: 2);
  static const l2t3 = ScalabilityMode(spatialLayers: 2, temporalLayers: 3);
  static const l3t1 = ScalabilityMode(spatialLayers: 3, temporalLayers: 1);
  static const l3t2 = ScalabilityMode(spatialLayers: 3, temporalLayers: 2);
  static const l3t3 = ScalabilityMode(spatialLayers: 3, temporalLayers: 3);
}

/// SVC layer selection criteria
///
/// Specifies which spatial and temporal layers should be forwarded.
class SvcLayerSelection {
  /// Maximum spatial layer to forward (0 = base only, null = all)
  final int? maxSpatialLayer;

  /// Maximum temporal layer to forward (0 = base only, null = all)
  final int? maxTemporalLayer;

  const SvcLayerSelection({
    this.maxSpatialLayer,
    this.maxTemporalLayer,
  });

  /// Accept all layers
  static const all = SvcLayerSelection();

  /// Base layer only (lowest quality, lowest bandwidth)
  static const baseOnly = SvcLayerSelection(
    maxSpatialLayer: 0,
    maxTemporalLayer: 0,
  );

  /// Base spatial layer with all temporal layers (low resolution, smooth motion)
  static const baseSpatialAllTemporal = SvcLayerSelection(
    maxSpatialLayer: 0,
  );

  /// All spatial layers with base temporal layer (high resolution, choppy motion)
  static const allSpatialBaseTemporal = SvcLayerSelection(
    maxTemporalLayer: 0,
  );

  /// Create selection for specific layer limits
  factory SvcLayerSelection.limit({int? spatial, int? temporal}) {
    return SvcLayerSelection(
      maxSpatialLayer: spatial,
      maxTemporalLayer: temporal,
    );
  }

  /// Check if a packet with given layer indices should be forwarded
  bool shouldForward(int? spatialId, int? temporalId) {
    // If no layer info, forward by default
    if (spatialId == null && temporalId == null) return true;

    // Check spatial layer
    if (maxSpatialLayer != null && spatialId != null) {
      if (spatialId > maxSpatialLayer!) return false;
    }

    // Check temporal layer
    if (maxTemporalLayer != null && temporalId != null) {
      if (temporalId > maxTemporalLayer!) return false;
    }

    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SvcLayerSelection &&
          maxSpatialLayer == other.maxSpatialLayer &&
          maxTemporalLayer == other.maxTemporalLayer;

  @override
  int get hashCode => maxSpatialLayer.hashCode ^ maxTemporalLayer.hashCode;

  @override
  String toString() =>
      'SvcLayerSelection(spatial: ${maxSpatialLayer ?? "all"}, temporal: ${maxTemporalLayer ?? "all"})';
}

/// VP9 SVC layer filter
///
/// Filters VP9 RTP packets based on SVC layer selection criteria.
/// Tracks keyframes and ensures layer switches happen at safe points.
class Vp9SvcFilter {
  /// Current layer selection
  SvcLayerSelection _selection;

  /// Pending selection (waiting for keyframe to switch)
  SvcLayerSelection? _pendingSelection;

  /// Last forwarded picture ID per spatial layer
  final Map<int, int> _lastPictureId = {};

  /// Whether we're waiting for a keyframe to complete a layer switch
  bool _waitingForKeyframe = false;

  /// Statistics
  int _packetsReceived = 0;
  int _packetsForwarded = 0;
  int _packetsDropped = 0;

  Vp9SvcFilter({SvcLayerSelection selection = SvcLayerSelection.all})
      : _selection = selection;

  /// Get current layer selection
  SvcLayerSelection get selection => _selection;

  /// Get pending selection (if waiting for keyframe)
  SvcLayerSelection? get pendingSelection => _pendingSelection;

  /// Check if waiting for keyframe to complete layer switch
  bool get isWaitingForKeyframe => _waitingForKeyframe;

  /// Set new layer selection
  ///
  /// If [immediate] is true, switches immediately (may cause artifacts).
  /// If [immediate] is false (default), waits for next keyframe to switch.
  void setSelection(SvcLayerSelection newSelection, {bool immediate = false}) {
    if (newSelection == _selection) {
      _pendingSelection = null;
      _waitingForKeyframe = false;
      return;
    }

    if (immediate) {
      _selection = newSelection;
      _pendingSelection = null;
      _waitingForKeyframe = false;
    } else {
      // Check if we're reducing layers (requires keyframe)
      final reducingSpatial = newSelection.maxSpatialLayer != null &&
          (_selection.maxSpatialLayer == null ||
              newSelection.maxSpatialLayer! < _selection.maxSpatialLayer!);

      if (reducingSpatial) {
        _pendingSelection = newSelection;
        _waitingForKeyframe = true;
      } else {
        // Increasing layers or only changing temporal can be done immediately
        _selection = newSelection;
        _pendingSelection = null;
        _waitingForKeyframe = false;
      }
    }
  }

  /// Select maximum spatial layer (0-based index)
  void selectSpatialLayer(int maxSid, {bool immediate = false}) {
    setSelection(
      SvcLayerSelection(
        maxSpatialLayer: maxSid,
        maxTemporalLayer: _selection.maxTemporalLayer,
      ),
      immediate: immediate,
    );
  }

  /// Select maximum temporal layer (0-based index)
  void selectTemporalLayer(int maxTid, {bool immediate = false}) {
    setSelection(
      SvcLayerSelection(
        maxSpatialLayer: _selection.maxSpatialLayer,
        maxTemporalLayer: maxTid,
      ),
      immediate: immediate,
    );
  }

  /// Select layers by target bitrate
  ///
  /// Maps bitrate to appropriate layer combination:
  /// - Very low: base only
  /// - Low: base spatial, limited temporal
  /// - Medium: some spatial, most temporal
  /// - High: all layers
  ///
  /// If [immediate] is true, switches immediately without waiting for keyframe.
  void selectByBitrate(int targetBitrateBps, ScalabilityMode mode,
      {bool immediate = false}) {
    // Rough bitrate thresholds (these should be tuned for actual content)
    const baseRate = 150000; // 150 kbps for base layer

    if (targetBitrateBps < baseRate) {
      // Very low bandwidth: base only
      setSelection(SvcLayerSelection.baseOnly, immediate: immediate);
    } else if (targetBitrateBps < baseRate * 2) {
      // Low bandwidth: base spatial, half temporal
      setSelection(
          SvcLayerSelection(
            maxSpatialLayer: 0,
            maxTemporalLayer: mode.maxTemporalId ~/ 2,
          ),
          immediate: immediate);
    } else if (targetBitrateBps < baseRate * 4) {
      // Medium bandwidth: half spatial, all temporal
      setSelection(
          SvcLayerSelection(
            maxSpatialLayer: mode.maxSpatialId ~/ 2,
            maxTemporalLayer: null,
          ),
          immediate: immediate);
    } else {
      // High bandwidth: all layers
      setSelection(SvcLayerSelection.all, immediate: immediate);
    }
  }

  /// Filter a VP9 RTP packet
  ///
  /// Returns true if the packet should be forwarded, false if it should be dropped.
  bool filter(Vp9RtpPayload payload) {
    _packetsReceived++;

    // Handle pending layer switch on keyframe
    if (_waitingForKeyframe &&
        _pendingSelection != null &&
        payload.isKeyframe) {
      _selection = _pendingSelection!;
      _pendingSelection = null;
      _waitingForKeyframe = false;
    }

    // Get layer indices (default to 0 if not present)
    final sid = payload.sid ?? 0;
    final tid = payload.tid ?? 0;

    // Check if packet should be forwarded
    if (!_selection.shouldForward(sid, tid)) {
      _packetsDropped++;
      return false;
    }

    // Track picture ID for this spatial layer
    if (payload.pictureId != null) {
      _lastPictureId[sid] = payload.pictureId!;
    }

    _packetsForwarded++;
    return true;
  }

  /// Filter raw RTP payload bytes
  ///
  /// Convenience method that deserializes, filters, and returns result.
  bool filterBytes(Uint8List rtpPayload) {
    if (rtpPayload.isEmpty) return false;
    final vp9 = Vp9RtpPayload.deserialize(rtpPayload);
    return filter(vp9);
  }

  /// Get filtering statistics
  SvcFilterStats get stats => SvcFilterStats(
        packetsReceived: _packetsReceived,
        packetsForwarded: _packetsForwarded,
        packetsDropped: _packetsDropped,
        currentSelection: _selection,
        pendingSelection: _pendingSelection,
        waitingForKeyframe: _waitingForKeyframe,
      );

  /// Reset statistics
  void resetStats() {
    _packetsReceived = 0;
    _packetsForwarded = 0;
    _packetsDropped = 0;
  }

  /// Reset all state including pending selections
  void reset() {
    resetStats();
    _lastPictureId.clear();
    _pendingSelection = null;
    _waitingForKeyframe = false;
  }
}

/// Statistics from SVC filter
class SvcFilterStats {
  final int packetsReceived;
  final int packetsForwarded;
  final int packetsDropped;
  final SvcLayerSelection currentSelection;
  final SvcLayerSelection? pendingSelection;
  final bool waitingForKeyframe;

  const SvcFilterStats({
    required this.packetsReceived,
    required this.packetsForwarded,
    required this.packetsDropped,
    required this.currentSelection,
    this.pendingSelection,
    required this.waitingForKeyframe,
  });

  /// Drop rate as percentage (0-100)
  double get dropRate =>
      packetsReceived > 0 ? (packetsDropped / packetsReceived) * 100 : 0;

  @override
  String toString() =>
      'SvcFilterStats(received: $packetsReceived, forwarded: $packetsForwarded, dropped: $packetsDropped, dropRate: ${dropRate.toStringAsFixed(1)}%)';
}

/// SVC layer info extracted from VP9 payload
///
/// Helper class for reporting layer information.
class SvcLayerInfo {
  /// Spatial layer ID (0-7)
  final int spatialId;

  /// Temporal layer ID (0-7)
  final int temporalId;

  /// Whether this is a switching point (can switch temporal layers here)
  final bool isSwitchingPoint;

  /// Whether this layer depends on lower spatial layer
  final bool hasInterLayerDependency;

  /// Picture ID (if present)
  final int? pictureId;

  const SvcLayerInfo({
    required this.spatialId,
    required this.temporalId,
    required this.isSwitchingPoint,
    required this.hasInterLayerDependency,
    this.pictureId,
  });

  /// Extract layer info from VP9 payload
  static SvcLayerInfo? fromPayload(Vp9RtpPayload payload) {
    // Only return info if layer indices are present
    if (payload.lBit != 1) return null;

    return SvcLayerInfo(
      spatialId: payload.sid ?? 0,
      temporalId: payload.tid ?? 0,
      isSwitchingPoint: payload.u == 1,
      hasInterLayerDependency: payload.d == 1,
      pictureId: payload.pictureId,
    );
  }

  @override
  String toString() =>
      'SvcLayerInfo(S$spatialId T$temporalId, switch=$isSwitchingPoint, interLayer=$hasInterLayerDependency)';
}
