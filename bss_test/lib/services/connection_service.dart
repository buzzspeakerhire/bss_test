// lib/services/connection_service.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../utils/logger.dart';

class ConnectionService {
  // Singleton instance
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();
  
  // Connection state
  bool isConnecting = false;
  bool isConnected = false;
  Socket? socket;
  StreamSubscription<Uint8List>? socketSubscription;
  
  // Connection parameters
  String ipAddress = "192.168.0.20";
  int port = 1023;
  
  // Stream controllers for event notification
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _dataReceivedController = StreamController<Uint8List>.broadcast();
  final _messageProcessorController = StreamController<List<int>>.broadcast();
  
  // Public stream getters
  Stream<bool> get onConnectionStatusChanged => _connectionStatusController.stream;
  Stream<Uint8List> get onDataReceived => _dataReceivedController.stream;
  Stream<List<int>> get onMessageExtracted => _messageProcessorController.stream;
  
  // Buffer for incoming data
  final List<int> _buffer = [];
  
  // Connect to the BSS device
  Future<bool> connect({String? ip, int? portNum}) async {
    if (isConnected || isConnecting) {
      Logger().log('Already connected or connecting');
      return false;
    }
    
    ipAddress = ip ?? ipAddress;
    port = portNum ?? port;
    
    isConnecting = true;
    _notifyConnectionStatus();
    
    try {
      Logger().log('Attempting to connect to $ipAddress:$port...');
      
      // Set a connection timeout
      socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 5))
          .catchError((error) {
        Logger().log('Connection error details: $error');
        throw error; // Rethrow to be caught by outer try-catch
      });
      
      isConnected = true;
      isConnecting = false;
      _buffer.clear();
      
      _notifyConnectionStatus();
      Logger().log('Connected to $ipAddress:$port');
      
      // Configure socket for better throughput
      socket!.setOption(SocketOption.tcpNoDelay, true);
      
      // Listen for responses from the device
      socketSubscription = socket!.listen(
        (Uint8List data) {
          try {
            Logger().log('Received ${data.length} bytes from socket');
            // Add data to buffer
            _buffer.addAll(data);
            
            // Notify listeners of raw data
            _safeAddToStream(_dataReceivedController, data);
            
            // Process complete messages
            _processBuffer();
          } catch (e) {
            Logger().log('Error handling socket data: $e');
          }
        },
        onError: (error) {
          Logger().log('Socket error: $error');
          disconnect();
        },
        onDone: () {
          Logger().log('Socket closed');
          disconnect();
        },
        cancelOnError: false,
      );
      
      return true;
    } catch (e) {
      isConnecting = false;
      _notifyConnectionStatus();
      Logger().log('Failed to connect: $e');
      return false;
    }
  }
  
  // Disconnect from the device
  void disconnect() {
    if (!isConnected && !isConnecting) return;
    
    socketSubscription?.cancel();
    socketSubscription = null;
    
    try {
      socket?.close();
    } catch (e) {
      Logger().log('Error closing socket: $e');
    }
    
    socket = null;
    
    isConnected = false;
    isConnecting = false;
    
    _notifyConnectionStatus();
    Logger().log('Disconnected from device');
  }
  
  // Send data to the device
  Future<bool> sendData(List<int> data) async {
    if (!isConnected || socket == null) {
      Logger().log('Not connected to device: isConnected=$isConnected, socket=${socket != null}');
      return false;
    }
    
    try {
      // Log outgoing data
      final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      Logger().log('Sending data: $hexData');
      
      try {
        Logger().log('Socket stats: localAddress=${socket!.address.address}, localPort=${socket!.port}, remoteAddress=${socket!.remoteAddress.address}, remotePort=${socket!.remotePort}');
      } catch (e) {
        Logger().log('Could not get socket stats: $e');
      }
      
      socket!.add(Uint8List.fromList(data));
      try {
        await socket!.flush(); // Ensure data is sent immediately
        Logger().log('Data sent to socket and flushed');
      } catch (e) {
        Logger().log('Could not flush socket: $e');
      }
      
      return true;
    } catch (e) {
      Logger().log('Failed to send data: $e');
      return false;
    }
  }
  
  // Process the buffer to extract complete messages
  void _processBuffer() {
    try {
      // Process complete messages
      while (_buffer.isNotEmpty) {
        // Look for start byte
        int startIndex = _buffer.indexOf(0x02);
        if (startIndex == -1) {
          Logger().log('No start byte found in buffer, clearing buffer');
          _buffer.clear();
          return;
        }
        
        // Remove data before start byte
        if (startIndex > 0) {
          Logger().log('Removing ${startIndex} bytes before start byte');
          _buffer.removeRange(0, startIndex);
        }
        
        // Look for end byte
        int endIndex = _buffer.indexOf(0x03);
        if (endIndex == -1 || _buffer.length < endIndex + 1) {
          // Not a complete message yet, but keep buffer
          // Set a reasonable buffer size limit to prevent memory issues
          if (_buffer.length > 4096) {
            _buffer.removeRange(0, _buffer.length - 2048);
            Logger().log('Buffer size limited to prevent overflow');
          }
          Logger().log('No end byte found or incomplete message, keeping buffer (${_buffer.length} bytes)');
          return;
        }
        
        // Extract the message (including start and end bytes)
        List<int> message = _buffer.sublist(0, endIndex + 1);
        _buffer.removeRange(0, endIndex + 1);
        
        // Log extracted message
        final hexMessage = message.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        Logger().log('Extracted complete message: $hexMessage (${message.length} bytes)');
        
        // Forward the message for processing - critical for two-way communication
        _safeAddToStream(_messageProcessorController, message);
      }
    } catch (e) {
      Logger().log('Error processing buffer: $e');
      // Clear buffer on error to prevent repeated crashes
      _buffer.clear();
    }
  }
  
  // Helper method to safely add data to a stream without blocking
  void _safeAddToStream<T>(StreamController<T> controller, T data) {
    if (!controller.isClosed) {
      try {
        controller.add(data);
      } catch (e) {
        Logger().log('Error adding to stream: $e');
      }
    }
  }
  
  // Notify connection status changes
  void _notifyConnectionStatus() {
    _safeAddToStream(_connectionStatusController, isConnected);
  }
  
  // Check if the socket is actually working by sending a ping
  Future<bool> pingSocket() async {
    if (!isConnected || socket == null) {
      Logger().log('Cannot ping - not connected or socket is null');
      return false;
    }
    
    try {
      // Create a simple BSS protocol ping (subscribe to a non-existent parameter)
      final pingData = [0x02, 0x89, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x8C, 0x03];
      socket!.add(Uint8List.fromList(pingData));
      Logger().log('Ping sent to socket');
      return true;
    } catch (e) {
      Logger().log('Ping failed: $e');
      return false;
    }
  }
  
  // Force reconnect to refresh the connection
  Future<bool> reconnect() async {
    Logger().log('Forcing reconnection...');
    disconnect();
    
    // Wait a moment for socket to fully close
    await Future.delayed(const Duration(milliseconds: 500));
    
    return connect(ip: ipAddress, portNum: port);
  }
  
  // Clean up resources
  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _dataReceivedController.close();
    _messageProcessorController.close();
  }
}