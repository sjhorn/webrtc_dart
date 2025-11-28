import 'dart:async';
import 'dart:typed_data';

/// DTLS Flight - a group of messages sent together
/// RFC 6347 Section 4.2.4
///
/// DTLS uses a flight-based retransmission model where related messages
/// are grouped together and retransmitted as a unit if not acknowledged.
abstract class Flight {
  /// Flight number (1-6 for typical DTLS handshake)
  int get flightNumber;

  /// Generate messages for this flight
  /// Returns list of messages to send
  Future<List<Uint8List>> generateMessages();

  /// Process received messages for this flight
  /// Returns true if flight is complete and can proceed to next
  Future<bool> processMessages(List<Uint8List> messages);

  /// Check if this flight expects a response
  bool get expectsResponse;

  /// Get timeout for retransmission (in milliseconds)
  /// Implements exponential backoff: 1s, 2s, 4s, 8s, 16s, ...
  int getTimeout(int retransmitCount) {
    final baseTimeout = 1000; // 1 second
    final maxTimeout = 60000; // 60 seconds

    final timeout = baseTimeout * (1 << retransmitCount);
    return timeout > maxTimeout ? maxTimeout : timeout;
  }
}

/// Flight state for retransmission management
class FlightState {
  final Flight flight;
  final List<Uint8List> messages;
  int retransmitCount;
  DateTime lastSentTime;
  Timer? retransmitTimer;
  bool completed;
  bool sent;

  FlightState({
    required this.flight,
    required this.messages,
    this.retransmitCount = 0,
    DateTime? lastSentTime,
    this.retransmitTimer,
    this.completed = false,
    this.sent = false,
  }) : lastSentTime = lastSentTime ?? DateTime.now();

  /// Check if retransmission is needed
  bool needsRetransmit() {
    if (completed || !flight.expectsResponse) {
      return false;
    }

    final timeout = flight.getTimeout(retransmitCount);
    final elapsed = DateTime.now().difference(lastSentTime).inMilliseconds;

    return elapsed >= timeout;
  }

  /// Mark as sent
  void markSent() {
    sent = true;
    lastSentTime = DateTime.now();
  }

  /// Mark as retransmitted
  void markRetransmitted() {
    retransmitCount++;
    lastSentTime = DateTime.now();
  }

  /// Cancel retransmission timer
  void cancelTimer() {
    retransmitTimer?.cancel();
    retransmitTimer = null;
  }

  /// Mark as completed
  void markCompleted() {
    completed = true;
    cancelTimer();
  }
}

/// Flight manager for handling multiple flights
class FlightManager {
  final List<FlightState> _flights = [];
  FlightState? _currentFlight;

  /// Add a flight to the queue
  void addFlight(Flight flight, List<Uint8List> messages) {
    final state = FlightState(
      flight: flight,
      messages: messages,
    );
    _flights.add(state);

    // Set as current if no current flight
    _currentFlight ??= state;
  }

  /// Get current flight
  FlightState? get currentFlight => _currentFlight;

  /// Move to next flight
  void moveToNextFlight() {
    if (_currentFlight == null) {
      return; // No current flight to move from
    }

    _currentFlight!.markCompleted();

    final currentIndex = _flights.indexOf(_currentFlight!);
    if (currentIndex < _flights.length - 1) {
      _currentFlight = _flights[currentIndex + 1];
    } else {
      _currentFlight = null; // All flights complete
    }
  }

  /// Check if any flight needs retransmission
  FlightState? getFlightNeedingRetransmit() {
    for (final flight in _flights) {
      if (flight.needsRetransmit()) {
        return flight;
      }
    }
    return null;
  }

  /// Clear all flights
  void clear() {
    for (final flight in _flights) {
      flight.cancelTimer();
    }
    _flights.clear();
    _currentFlight = null;
  }

  /// Check if all flights are complete
  bool get isComplete => _currentFlight == null && _flights.isNotEmpty;
}
