import 'dart:async';

// A simple global event system for fader communication
class FaderCommunication {
  // Singleton instance
  static final FaderCommunication _instance = FaderCommunication._internal();
  
  factory FaderCommunication() {
    return _instance;
  }
  
  FaderCommunication._internal();
  
  // Stream controllers
  final _faderMovedController = StreamController<Map<String, dynamic>>.broadcast();
  final _faderUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  
  // Public streams
  Stream<Map<String, dynamic>> get onFaderMoved => _faderMovedController.stream;
  Stream<Map<String, dynamic>> get onFaderUpdate => _faderUpdateController.stream;
  Stream<bool> get onConnectionChanged => _connectionStateController.stream;
  
  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // Methods to trigger events
  void reportFaderMoved(String address, String paramId, double value) {
    _faderMovedController.add({
      'address': address,
      'paramId': paramId,
      'value': value,
    });
  }
  
  void updateFaderFromDevice(String address, String paramId, double value) {
    _faderUpdateController.add({
      'address': address,
      'paramId': paramId,
      'value': value,
    });
  }
  
  void setConnectionState(bool connected) {
    _isConnected = connected;
    _connectionStateController.add(connected);
  }
  
  void dispose() {
    _faderMovedController.close();
    _faderUpdateController.close();
    _connectionStateController.close();
  }
}