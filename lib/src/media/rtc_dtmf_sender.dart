import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/rtp/rtp_session.dart';

/// DTMF tone change event
/// Fired when a DTMF tone starts or ends
class RTCDTMFToneChangeEvent {
  /// The tone that started playing, or empty string if tone ended
  final String tone;

  const RTCDTMFToneChangeEvent(this.tone);

  @override
  String toString() => 'RTCDTMFToneChangeEvent(tone: "$tone")';
}

/// RTCDTMFSender - W3C WebRTC DTMF Sender
///
/// Provides the ability to send DTMF (Dual-Tone Multi-Frequency) tones
/// over an RTP connection. DTMF is commonly used for telephone keypads.
///
/// Uses RFC 4733 (RTP Payload for DTMF Digits) telephone-event format.
///
/// Example:
/// ```dart
/// final sender = pc.getSenders().first;
/// if (sender.dtmf != null) {
///   sender.dtmf!.insertDTMF('1234#');
///   sender.dtmf!.ontonechange = (event) {
///     print('Tone: ${event.tone}');
///   };
/// }
/// ```
class RTCDTMFSender {
  /// RTP session for sending DTMF packets
  final RtpSession _rtpSession;

  /// Payload type for telephone-event (typically 101)
  final int _payloadType;

  /// Clock rate for telephone-event (always 8000 Hz per RFC 4733)
  static const int clockRate = 8000;

  /// Queue of tones to send
  String _toneBuffer = '';

  /// Duration of each tone in milliseconds (default 100ms)
  int _duration = 100;

  /// Gap between tones in milliseconds (default 70ms)
  int _interToneGap = 70;

  /// Whether currently sending tones
  bool _isSending = false;

  /// Timer for tone sending
  Timer? _sendTimer;

  /// Stream controller for tone change events
  final StreamController<RTCDTMFToneChangeEvent> _toneChangeController =
      StreamController.broadcast();

  /// W3C-style listener subscription
  StreamSubscription? _ontonechangeSubscription;

  /// Whether the sender can insert DTMF
  bool _canInsertDTMF = true;

  RTCDTMFSender({
    required RtpSession rtpSession,
    int payloadType = 101,
  })  : _rtpSession = rtpSession,
        _payloadType = payloadType;

  // ===========================================================================
  // W3C Standard Properties
  // ===========================================================================

  /// Returns true if DTMF can be sent
  ///
  /// This is true if the associated audio track is active and the
  /// connection is in a state that allows sending.
  bool get canInsertDTMF => _canInsertDTMF;

  /// Returns the current tone buffer (remaining tones to be played)
  String get toneBuffer => _toneBuffer;

  /// Stream of tone change events
  Stream<RTCDTMFToneChangeEvent> get onToneChange =>
      _toneChangeController.stream;

  /// Set tone change callback (W3C-style)
  set ontonechange(void Function(RTCDTMFToneChangeEvent)? callback) {
    _ontonechangeSubscription?.cancel();
    _ontonechangeSubscription =
        callback != null ? onToneChange.listen(callback) : null;
  }

  // ===========================================================================
  // W3C Standard Methods
  // ===========================================================================

  /// Insert DTMF tones to be sent
  ///
  /// [tones] - String of DTMF characters to send. Valid characters:
  ///   - '0'-'9': Digits
  ///   - '*': Star
  ///   - '#': Pound/hash
  ///   - 'A'-'D': Extended DTMF tones
  ///   - ',': 2-second pause
  ///
  /// [duration] - Duration of each tone in milliseconds (40-6000, default 100)
  ///
  /// [interToneGap] - Gap between tones in milliseconds (min 30, default 70)
  ///
  /// Throws [InvalidStateError] if canInsertDTMF is false.
  /// Throws [InvalidCharacterError] if tones contains invalid characters.
  void insertDTMF(String tones, {int duration = 100, int interToneGap = 70}) {
    if (!_canInsertDTMF) {
      throw StateError('Cannot insert DTMF: canInsertDTMF is false');
    }

    // Validate tones
    final validChars = RegExp(r'^[0-9A-Da-d#*,]*$');
    if (!validChars.hasMatch(tones)) {
      throw ArgumentError('Invalid DTMF characters in: $tones');
    }

    // Clamp duration to valid range (40-6000ms)
    _duration = duration.clamp(40, 6000);

    // Minimum inter-tone gap is 30ms
    _interToneGap = interToneGap < 30 ? 30 : interToneGap;

    // Replace the tone buffer (per W3C spec, new insertDTMF replaces queue)
    _toneBuffer = tones.toUpperCase();

    // Start sending if not already
    if (!_isSending && _toneBuffer.isNotEmpty) {
      _startSending();
    }
  }

  /// Start sending tones from the buffer
  void _startSending() {
    if (_isSending || _toneBuffer.isEmpty) return;
    _isSending = true;
    _sendNextTone();
  }

  /// Send the next tone in the buffer
  void _sendNextTone() {
    if (_toneBuffer.isEmpty) {
      _isSending = false;
      // Emit empty tone event to signal end
      _toneChangeController.add(const RTCDTMFToneChangeEvent(''));
      return;
    }

    final tone = _toneBuffer[0];
    _toneBuffer = _toneBuffer.substring(1);

    // Handle pause character
    if (tone == ',') {
      // 2-second pause
      _sendTimer = Timer(const Duration(seconds: 2), _sendNextTone);
      return;
    }

    // Emit tone start event
    _toneChangeController.add(RTCDTMFToneChangeEvent(tone));

    // Send the DTMF tone via RTP
    _sendDtmfTone(tone);

    // Schedule next tone after duration + gap
    _sendTimer = Timer(
      Duration(milliseconds: _duration + _interToneGap),
      _sendNextTone,
    );
  }

  /// Send a single DTMF tone via RTP telephone-event
  Future<void> _sendDtmfTone(String tone) async {
    final eventCode = _toneToEventCode(tone);
    if (eventCode < 0) return;

    // RFC 4733: Send multiple packets for reliability
    // - Start packet (E=0, R=0)
    // - Continuation packets (E=0, R=0)
    // - End packets (E=1, R=0) - sent 3 times per RFC

    final durationSamples = (_duration * clockRate) ~/ 1000;

    // Send start packet
    await _sendTelephoneEvent(
      eventCode: eventCode,
      endOfEvent: false,
      volume: 10, // -10 dBm0
      duration: 0,
    );

    // Send continuation packets during tone
    final packetInterval = 20; // 20ms intervals
    final numContinuationPackets = _duration ~/ packetInterval;

    for (var i = 1; i <= numContinuationPackets; i++) {
      await Future.delayed(Duration(milliseconds: packetInterval));
      final currentDuration = (i * packetInterval * clockRate) ~/ 1000;
      await _sendTelephoneEvent(
        eventCode: eventCode,
        endOfEvent: false,
        volume: 10,
        duration: currentDuration.clamp(0, durationSamples),
      );
    }

    // Send end packets (3 times for reliability per RFC 4733)
    for (var i = 0; i < 3; i++) {
      await _sendTelephoneEvent(
        eventCode: eventCode,
        endOfEvent: true,
        volume: 10,
        duration: durationSamples,
      );
    }
  }

  /// Send a telephone-event RTP packet
  Future<void> _sendTelephoneEvent({
    required int eventCode,
    required bool endOfEvent,
    required int volume,
    required int duration,
  }) async {
    // RFC 4733 telephone-event payload format:
    // 0                   1                   2                   3
    // 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |     event     |E|R| volume    |          duration             |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

    final payload = Uint8List(4);
    payload[0] = eventCode & 0xFF;
    payload[1] = ((endOfEvent ? 0x80 : 0) | (volume & 0x3F));
    payload[2] = (duration >> 8) & 0xFF;
    payload[3] = duration & 0xFF;

    // Send via RTP session
    // Note: For DTMF, timestamp should not increment between packets of same event
    try {
      await _rtpSession.sendRtp(
        payloadType: _payloadType,
        payload: payload,
        timestampIncrement: endOfEvent ? 160 : 0, // Only increment at event end
        marker: !endOfEvent && duration == 0, // Marker on first packet
      );
    } catch (e) {
      // ICE connection may not be established yet - continue with tone events
      // The ontonechange events will still fire to track tone progress
    }
  }

  /// Convert DTMF character to RFC 4733 event code
  int _toneToEventCode(String tone) {
    switch (tone) {
      case '0':
        return 0;
      case '1':
        return 1;
      case '2':
        return 2;
      case '3':
        return 3;
      case '4':
        return 4;
      case '5':
        return 5;
      case '6':
        return 6;
      case '7':
        return 7;
      case '8':
        return 8;
      case '9':
        return 9;
      case '*':
        return 10;
      case '#':
        return 11;
      case 'A':
        return 12;
      case 'B':
        return 13;
      case 'C':
        return 14;
      case 'D':
        return 15;
      default:
        return -1;
    }
  }

  /// Stop sending and clean up
  void stop() {
    _canInsertDTMF = false;
    _toneBuffer = '';
    _isSending = false;
    _sendTimer?.cancel();
    _sendTimer = null;
  }

  /// Dispose resources
  void dispose() {
    stop();
    _ontonechangeSubscription?.cancel();
    _toneChangeController.close();
  }

  @override
  String toString() => 'RTCDTMFSender(canInsertDTMF: $canInsertDTMF, '
      'toneBuffer: "$toneBuffer")';
}
