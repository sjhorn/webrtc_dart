/// Sender Bandwidth Estimation (BWE)
/// Based on TWCC feedback to estimate available bandwidth and detect congestion.
/// Reference: mediasoup implementation
library;

import 'dart:math';

import '../../rtcp/rtpfb/twcc.dart';

const int _counterMax = 20;
const int _scoreMax = 10;

/// Cumulative result for bitrate calculation.
/// Tracks sent/received timing to compute send and receive bitrates.
class CumulativeResult {
  int numPackets = 0;

  /// Total size in bytes
  int totalSize = 0;

  int firstPacketSentAtMs = 0;
  int lastPacketSentAtMs = 0;
  int firstPacketReceivedAtMs = 0;
  int lastPacketReceivedAtMs = 0;

  /// Add a packet to the cumulative result.
  ///
  /// [size] - packet size in bytes
  /// [sentAtMs] - time packet was sent (ms)
  /// [receivedAtMs] - time packet was received (ms)
  void addPacket(int size, int sentAtMs, int receivedAtMs) {
    if (numPackets == 0) {
      firstPacketSentAtMs = sentAtMs;
      firstPacketReceivedAtMs = receivedAtMs;
      lastPacketSentAtMs = sentAtMs;
      lastPacketReceivedAtMs = receivedAtMs;
    } else {
      if (sentAtMs < firstPacketSentAtMs) {
        firstPacketSentAtMs = sentAtMs;
      }
      if (receivedAtMs < firstPacketReceivedAtMs) {
        firstPacketReceivedAtMs = receivedAtMs;
      }
      if (sentAtMs > lastPacketSentAtMs) {
        lastPacketSentAtMs = sentAtMs;
      }
      if (receivedAtMs > lastPacketReceivedAtMs) {
        lastPacketReceivedAtMs = receivedAtMs;
      }
    }

    numPackets++;
    totalSize += size;
  }

  void reset() {
    numPackets = 0;
    totalSize = 0;
    firstPacketSentAtMs = 0;
    lastPacketSentAtMs = 0;
    firstPacketReceivedAtMs = 0;
    lastPacketReceivedAtMs = 0;
  }

  /// Receive bitrate in bits per second.
  int get receiveBitrate {
    final recvIntervalMs = lastPacketReceivedAtMs - firstPacketReceivedAtMs;
    if (recvIntervalMs <= 0) return 0;
    final bitrate = (totalSize / recvIntervalMs) * 8 * 1000;
    return bitrate.toInt();
  }

  /// Send bitrate in bits per second.
  int get sendBitrate {
    final sendIntervalMs = lastPacketSentAtMs - firstPacketSentAtMs;
    if (sendIntervalMs <= 0) return 0;
    final bitrate = (totalSize / sendIntervalMs) * 8 * 1000;
    return bitrate.toInt();
  }
}

/// Information about a sent RTP packet.
class SentInfo {
  /// Transport-wide sequence number
  final int wideSeq;

  /// Packet size in bytes
  final int size;

  /// Whether this is a probation packet
  final bool isProbation;

  /// Time when sending started (ms)
  final int sendingAtMs;

  /// Time when packet was actually sent (ms)
  final int sentAtMs;

  const SentInfo({
    required this.wideSeq,
    required this.size,
    this.isProbation = false,
    required this.sendingAtMs,
    required this.sentAtMs,
  });
}

/// Callback for available bitrate updates.
typedef OnAvailableBitrate = void Function(int bitrate);

/// Callback for congestion state changes.
typedef OnCongestion = void Function(bool congested);

/// Callback for congestion score updates.
typedef OnCongestionScore = void Function(int score);

/// Sender Bandwidth Estimator.
///
/// Uses TWCC feedback to estimate available bandwidth and detect network congestion.
/// Congestion is tracked with a counter and score system:
/// - Counter increases when feedback is delayed (>1000ms)
/// - Counter decreases when feedback is timely with sufficient packets
/// - Score (1-10) increases during extended congestion, decreases during good conditions
class SenderBandwidthEstimator {
  bool _congestion = false;

  /// Whether network is currently congested.
  bool get congestion => _congestion;

  /// Callback when available bitrate is updated.
  OnAvailableBitrate? onAvailableBitrate;

  /// Callback when congestion state changes.
  OnCongestion? onCongestion;

  /// Callback when congestion score changes.
  OnCongestionScore? onCongestionScore;

  int _congestionCounter = 0;
  final CumulativeResult _cumulativeResult = CumulativeResult();
  final Map<int, SentInfo> _sentInfos = {};

  int _congestionScore = 1;

  /// Congestion score (1-10). Higher values indicate worse network conditions.
  int get congestionScore => _congestionScore;

  set congestionScore(int v) {
    _congestionScore = v;
    onCongestionScore?.call(v);
  }

  int _availableBitrate = 0;

  /// Estimated available bitrate in bits per second.
  int get availableBitrate => _availableBitrate;

  set availableBitrate(int v) {
    _availableBitrate = v;
    onAvailableBitrate?.call(v);
  }

  SenderBandwidthEstimator();

  /// Get current time in milliseconds.
  /// Can be overridden for testing.
  int Function() milliTime = () => DateTime.now().millisecondsSinceEpoch;

  /// Process TWCC feedback packet.
  void receiveTWCC(TransportWideCC feedback) {
    final nowMs = milliTime();
    final elapsedMs = nowMs - _cumulativeResult.firstPacketSentAtMs;

    if (elapsedMs > 1000) {
      _cumulativeResult.reset();

      // Congestion may be occurring.
      if (_congestionCounter < _counterMax) {
        _congestionCounter++;
      } else if (_congestionScore < _scoreMax) {
        congestionScore = _congestionScore + 1;
      }

      if (_congestionCounter >= _counterMax && !_congestion) {
        _congestion = true;
        onCongestion?.call(_congestion);
      }
    }

    for (final result in feedback.packetResults) {
      if (!result.received) continue;

      final wideSeq = result.sequenceNumber;
      final info = _sentInfos[wideSeq];
      if (info == null) continue;

      _cumulativeResult.addPacket(
        info.size,
        info.sendingAtMs,
        result.receivedAtMs,
      );
    }

    if (elapsedMs >= 100 && _cumulativeResult.numPackets >= 20) {
      availableBitrate = min(
        _cumulativeResult.sendBitrate,
        _cumulativeResult.receiveBitrate,
      );
      _cumulativeResult.reset();

      if (_congestionCounter > -_counterMax) {
        final maxBonus = (_counterMax ~/ 2) + 1;
        final minBonus = (_counterMax ~/ 4) + 1;
        final bonus =
            maxBonus - ((maxBonus - minBonus) / 10) * _congestionScore;

        _congestionCounter = _congestionCounter - bonus.toInt();
      }

      if (_congestionCounter <= -_counterMax) {
        if (_congestionScore > 1) {
          congestionScore = _congestionScore - 1;
          onCongestion?.call(false);
        }
        _congestionCounter = 0;
      }

      if (_congestionCounter <= 0 && _congestion) {
        _congestion = false;
        onCongestion?.call(_congestion);
      }
    }
  }

  /// Record a sent RTP packet.
  void rtpPacketSent(SentInfo sentInfo) {
    // NOTE: TypeScript original has a bug using Object.keys(sentInfo) instead of
    // Object.keys(this.sentInfos). We keep sent infos until they're processed
    // by feedback rather than cleaning up aggressively.
    _sentInfos[sentInfo.wideSeq] = sentInfo;
  }
}
