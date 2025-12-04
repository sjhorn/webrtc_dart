import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/svc_manager.dart';
import 'package:webrtc_dart/src/codec/vp9.dart';

void main() {
  group('ScalabilityMode', () {
    test('parses L1T1', () {
      final mode = ScalabilityMode.parse('L1T1');
      expect(mode, isNotNull);
      expect(mode!.spatialLayers, equals(1));
      expect(mode.temporalLayers, equals(1));
      expect(mode.keyMode, isFalse);
      expect(mode.isSvc, isFalse);
    });

    test('parses L1T2', () {
      final mode = ScalabilityMode.parse('L1T2');
      expect(mode, isNotNull);
      expect(mode!.spatialLayers, equals(1));
      expect(mode.temporalLayers, equals(2));
      expect(mode.keyMode, isFalse);
      expect(mode.isSvc, isTrue);
    });

    test('parses L2T3', () {
      final mode = ScalabilityMode.parse('L2T3');
      expect(mode, isNotNull);
      expect(mode!.spatialLayers, equals(2));
      expect(mode.temporalLayers, equals(3));
      expect(mode.maxSpatialId, equals(1));
      expect(mode.maxTemporalId, equals(2));
    });

    test('parses L3T3_KEY', () {
      final mode = ScalabilityMode.parse('L3T3_KEY');
      expect(mode, isNotNull);
      expect(mode!.spatialLayers, equals(3));
      expect(mode.temporalLayers, equals(3));
      expect(mode.keyMode, isTrue);
    });

    test('parses lowercase', () {
      final mode = ScalabilityMode.parse('l2t2');
      expect(mode, isNotNull);
      expect(mode!.spatialLayers, equals(2));
      expect(mode.temporalLayers, equals(2));
    });

    test('parses mixed case with _key', () {
      final mode = ScalabilityMode.parse('L2T3_key');
      expect(mode, isNotNull);
      expect(mode!.keyMode, isTrue);
    });

    test('returns null for invalid format', () {
      expect(ScalabilityMode.parse('invalid'), isNull);
      expect(ScalabilityMode.parse('L0T1'), isNull); // 0 not allowed
      expect(ScalabilityMode.parse('L9T1'), isNull); // 9 not allowed
      expect(ScalabilityMode.parse('L1T0'), isNull); // 0 not allowed
      expect(ScalabilityMode.parse('L1T9'), isNull); // 9 not allowed
      expect(ScalabilityMode.parse(''), isNull);
      expect(ScalabilityMode.parse('L1'), isNull);
      expect(ScalabilityMode.parse('T1'), isNull);
    });

    test('serializes correctly', () {
      expect(ScalabilityMode.l1t1.serialize(), equals('L1T1'));
      expect(ScalabilityMode.l2t3.serialize(), equals('L2T3'));
      expect(
        const ScalabilityMode(spatialLayers: 2, temporalLayers: 2, keyMode: true)
            .serialize(),
        equals('L2T2_KEY'),
      );
    });

    test('equality works', () {
      final mode1 = ScalabilityMode.parse('L2T2');
      final mode2 = ScalabilityMode.parse('L2T2');
      final mode3 = ScalabilityMode.parse('L2T3');

      expect(mode1, equals(mode2));
      expect(mode1, isNot(equals(mode3)));
    });

    test('predefined constants are correct', () {
      expect(ScalabilityMode.l1t1.spatialLayers, equals(1));
      expect(ScalabilityMode.l1t1.temporalLayers, equals(1));

      expect(ScalabilityMode.l2t2.spatialLayers, equals(2));
      expect(ScalabilityMode.l2t2.temporalLayers, equals(2));

      expect(ScalabilityMode.l3t3.spatialLayers, equals(3));
      expect(ScalabilityMode.l3t3.temporalLayers, equals(3));
    });
  });

  group('SvcLayerSelection', () {
    test('all selection forwards everything', () {
      final selection = SvcLayerSelection.all;
      expect(selection.shouldForward(0, 0), isTrue);
      expect(selection.shouldForward(2, 2), isTrue);
      expect(selection.shouldForward(7, 7), isTrue);
      expect(selection.shouldForward(null, null), isTrue);
    });

    test('baseOnly selection forwards only base layer', () {
      final selection = SvcLayerSelection.baseOnly;
      expect(selection.shouldForward(0, 0), isTrue);
      expect(selection.shouldForward(0, 1), isFalse);
      expect(selection.shouldForward(1, 0), isFalse);
      expect(selection.shouldForward(1, 1), isFalse);
    });

    test('baseSpatialAllTemporal forwards correctly', () {
      final selection = SvcLayerSelection.baseSpatialAllTemporal;
      expect(selection.shouldForward(0, 0), isTrue);
      expect(selection.shouldForward(0, 1), isTrue);
      expect(selection.shouldForward(0, 2), isTrue);
      expect(selection.shouldForward(1, 0), isFalse);
      expect(selection.shouldForward(1, 1), isFalse);
    });

    test('allSpatialBaseTemporal forwards correctly', () {
      final selection = SvcLayerSelection.allSpatialBaseTemporal;
      expect(selection.shouldForward(0, 0), isTrue);
      expect(selection.shouldForward(1, 0), isTrue);
      expect(selection.shouldForward(2, 0), isTrue);
      expect(selection.shouldForward(0, 1), isFalse);
      expect(selection.shouldForward(1, 1), isFalse);
    });

    test('limit factory creates correct selection', () {
      final selection = SvcLayerSelection.limit(spatial: 1, temporal: 2);
      expect(selection.shouldForward(0, 0), isTrue);
      expect(selection.shouldForward(1, 2), isTrue);
      expect(selection.shouldForward(2, 0), isFalse);
      expect(selection.shouldForward(0, 3), isFalse);
    });

    test('null layer indices are forwarded', () {
      final selection = SvcLayerSelection.limit(spatial: 1, temporal: 1);
      expect(selection.shouldForward(null, null), isTrue);
      expect(selection.shouldForward(0, null), isTrue);
      expect(selection.shouldForward(null, 0), isTrue);
    });

    test('equality works', () {
      final sel1 = SvcLayerSelection.limit(spatial: 1, temporal: 2);
      final sel2 = SvcLayerSelection.limit(spatial: 1, temporal: 2);
      final sel3 = SvcLayerSelection.limit(spatial: 2, temporal: 2);

      expect(sel1, equals(sel2));
      expect(sel1, isNot(equals(sel3)));
    });
  });

  group('Vp9SvcFilter', () {
    late Vp9SvcFilter filter;

    setUp(() {
      filter = Vp9SvcFilter();
    });

    Vp9RtpPayload createMockPayload({
      int? sid,
      int? tid,
      bool isKeyframe = false,
      int? pictureId,
    }) {
      final payload = Vp9RtpPayload();
      // Set lBit to 1 when we have layer info
      payload.lBit = (sid != null || tid != null) ? 1 : 0;
      payload.sid = sid;
      payload.tid = tid;
      // For keyframe: pBit=0, bBit=1, and sid must be 0 (or no layer info)
      payload.pBit = isKeyframe ? 0 : 1;
      payload.bBit = 1;
      // For keyframe detection with layer info, sid must be 0
      // So we adjust: if keyframe requested but sid != 0, it won't be detected
      payload.pictureId = pictureId;
      payload.payload = Uint8List(10);
      return payload;
    }

    test('defaults to forwarding all layers', () {
      expect(filter.selection, equals(SvcLayerSelection.all));

      expect(filter.filter(createMockPayload(sid: 0, tid: 0)), isTrue);
      expect(filter.filter(createMockPayload(sid: 2, tid: 2)), isTrue);
    });

    test('filters by spatial layer', () {
      // Use immediate to bypass keyframe wait when reducing from all layers
      filter.selectSpatialLayer(0, immediate: true);

      expect(filter.filter(createMockPayload(sid: 0, tid: 0)), isTrue);
      expect(filter.filter(createMockPayload(sid: 0, tid: 1)), isTrue);
      expect(filter.filter(createMockPayload(sid: 1, tid: 0)), isFalse);
    });

    test('filters by temporal layer', () {
      // Temporal layer changes don't require keyframe wait
      filter.selectTemporalLayer(1);

      expect(filter.filter(createMockPayload(sid: 0, tid: 0)), isTrue);
      expect(filter.filter(createMockPayload(sid: 0, tid: 1)), isTrue);
      expect(filter.filter(createMockPayload(sid: 0, tid: 2)), isFalse);
      expect(filter.filter(createMockPayload(sid: 1, tid: 0)), isTrue);
    });

    test('reducing spatial layer waits for keyframe', () {
      // Start with all layers
      filter.setSelection(SvcLayerSelection.all);

      // Request reduction to spatial layer 0
      filter.setSelection(SvcLayerSelection(maxSpatialLayer: 0));

      // Selection should be pending
      expect(filter.isWaitingForKeyframe, isTrue);
      expect(filter.pendingSelection, isNotNull);

      // Still forwards spatial layer 1 (old selection)
      expect(filter.filter(createMockPayload(sid: 1, tid: 0)), isTrue);

      // Keyframe arrives, switch happens
      expect(
          filter.filter(createMockPayload(sid: 0, tid: 0, isKeyframe: true)),
          isTrue);
      expect(filter.isWaitingForKeyframe, isFalse);

      // Now spatial layer 1 is blocked
      expect(filter.filter(createMockPayload(sid: 1, tid: 0)), isFalse);
    });

    test('increasing spatial layer switches immediately', () {
      // Start with spatial layer 0 - use immediate to establish baseline
      filter.setSelection(SvcLayerSelection(maxSpatialLayer: 0), immediate: true);
      expect(filter.isWaitingForKeyframe, isFalse);

      // Request increase to spatial layer 1
      filter.setSelection(SvcLayerSelection(maxSpatialLayer: 1));

      // Should switch immediately (increasing doesn't require keyframe)
      expect(filter.isWaitingForKeyframe, isFalse);
      expect(filter.filter(createMockPayload(sid: 1, tid: 0)), isTrue);
    });

    test('changing only temporal layer switches immediately', () {
      // Use immediate to establish baseline
      filter.setSelection(
          SvcLayerSelection(maxSpatialLayer: 1, maxTemporalLayer: 1),
          immediate: true);

      // Reduce temporal layer
      filter.setSelection(
          SvcLayerSelection(maxSpatialLayer: 1, maxTemporalLayer: 0));

      // Should switch immediately (temporal changes don't require keyframe)
      expect(filter.isWaitingForKeyframe, isFalse);
      expect(filter.filter(createMockPayload(sid: 0, tid: 1)), isFalse);
    });

    test('immediate flag forces switch without keyframe', () {
      filter.setSelection(SvcLayerSelection.all);
      filter.setSelection(
        SvcLayerSelection(maxSpatialLayer: 0),
        immediate: true,
      );

      expect(filter.isWaitingForKeyframe, isFalse);
      expect(filter.filter(createMockPayload(sid: 1, tid: 0)), isFalse);
    });

    test('tracks statistics', () {
      // Use immediate: true to bypass keyframe wait
      filter.setSelection(SvcLayerSelection(maxSpatialLayer: 0), immediate: true);

      filter.filter(createMockPayload(sid: 0, tid: 0));
      filter.filter(createMockPayload(sid: 0, tid: 1));
      filter.filter(createMockPayload(sid: 1, tid: 0)); // Dropped
      filter.filter(createMockPayload(sid: 1, tid: 1)); // Dropped

      final stats = filter.stats;
      expect(stats.packetsReceived, equals(4));
      expect(stats.packetsForwarded, equals(2));
      expect(stats.packetsDropped, equals(2));
      expect(stats.dropRate, equals(50.0));
    });

    test('resetStats clears counters', () {
      filter.filter(createMockPayload(sid: 0, tid: 0));
      filter.filter(createMockPayload(sid: 0, tid: 0));

      filter.resetStats();

      expect(filter.stats.packetsReceived, equals(0));
      expect(filter.stats.packetsForwarded, equals(0));
    });

    test('reset clears all state', () {
      filter.setSelection(SvcLayerSelection(maxSpatialLayer: 0));
      filter.filter(createMockPayload(sid: 0, tid: 0));

      // Queue a pending selection
      filter.setSelection(SvcLayerSelection.baseOnly);

      filter.reset();

      expect(filter.stats.packetsReceived, equals(0));
      expect(filter.pendingSelection, isNull);
      expect(filter.isWaitingForKeyframe, isFalse);
    });

    test('selectByBitrate selects appropriate layers', () {
      final mode = ScalabilityMode.l2t3;

      // Very low bitrate: base only (use immediate to bypass keyframe wait)
      filter.selectByBitrate(100000, mode, immediate: true);
      expect(filter.selection.maxSpatialLayer, equals(0));
      expect(filter.selection.maxTemporalLayer, equals(0));

      // Medium-low bitrate: base spatial, limited temporal
      filter.reset();
      filter.selectByBitrate(200000, mode, immediate: true);
      expect(filter.selection.maxSpatialLayer, equals(0));
      expect(filter.selection.maxTemporalLayer, equals(1));

      // Higher bitrate: all layers
      filter.reset();
      filter.selectByBitrate(1000000, mode, immediate: true);
      expect(filter.selection.maxSpatialLayer, isNull);
      expect(filter.selection.maxTemporalLayer, isNull);
    });
  });

  group('SvcLayerInfo', () {
    test('extracts info from VP9 payload with layer indices', () {
      final payload = Vp9RtpPayload();
      payload.lBit = 1;
      payload.sid = 1;
      payload.tid = 2;
      payload.u = 1;
      payload.d = 0;
      payload.pictureId = 12345;
      payload.payload = Uint8List(10);

      final info = SvcLayerInfo.fromPayload(payload);

      expect(info, isNotNull);
      expect(info!.spatialId, equals(1));
      expect(info.temporalId, equals(2));
      expect(info.isSwitchingPoint, isTrue);
      expect(info.hasInterLayerDependency, isFalse);
      expect(info.pictureId, equals(12345));
    });

    test('returns null for payload without layer indices', () {
      final payload = Vp9RtpPayload();
      payload.lBit = 0;
      payload.payload = Uint8List(10);

      final info = SvcLayerInfo.fromPayload(payload);
      expect(info, isNull);
    });

    test('handles null values in payload', () {
      final payload = Vp9RtpPayload();
      payload.lBit = 1;
      payload.sid = null;
      payload.tid = null;
      payload.u = 0;
      payload.d = 1;
      payload.payload = Uint8List(10);

      final info = SvcLayerInfo.fromPayload(payload);

      expect(info, isNotNull);
      expect(info!.spatialId, equals(0));
      expect(info.temporalId, equals(0));
      expect(info.isSwitchingPoint, isFalse);
      expect(info.hasInterLayerDependency, isTrue);
    });
  });

  group('SvcFilterStats', () {
    test('calculates drop rate correctly', () {
      final stats = SvcFilterStats(
        packetsReceived: 100,
        packetsForwarded: 75,
        packetsDropped: 25,
        currentSelection: SvcLayerSelection.all,
        waitingForKeyframe: false,
      );

      expect(stats.dropRate, equals(25.0));
    });

    test('handles zero packets', () {
      final stats = SvcFilterStats(
        packetsReceived: 0,
        packetsForwarded: 0,
        packetsDropped: 0,
        currentSelection: SvcLayerSelection.all,
        waitingForKeyframe: false,
      );

      expect(stats.dropRate, equals(0.0));
    });
  });
}
