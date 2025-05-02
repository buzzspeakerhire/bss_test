import '../utils/hex_utils.dart';
import '../utils/logger.dart';
import 'dart:math';

/// Service that handles the BSS London Direct Inject protocol
class BssProtocolService {
  // Singleton instance
  static final BssProtocolService _instance = BssProtocolService._internal();
  factory BssProtocolService() => _instance;
  BssProtocolService._internal();
  
  // Protocol message types
  static const int MSG_TYPE_SET = 0x88;
  static const int MSG_TYPE_SUBSCRIBE = 0x89;
  static const int MSG_TYPE_UNSUBSCRIBE = 0x8A;
  static const int MSG_TYPE_RECALL_PRESET = 0x8C;
  static const int MSG_TYPE_SET_PERCENT = 0x8D;
  static const int MSG_TYPE_SUBSCRIBE_PERCENT = 0x8E;
  static const int MSG_TYPE_UNSUBSCRIBE_PERCENT = 0x8F;
  static const int MSG_TYPE_BUMP_PERCENT = 0x90;
  
  // Special bytes
  static const int START_BYTE = 0x02;
  static const int END_BYTE = 0x03;
  static const int ACK_BYTE = 0x06;
  static const int NAK_BYTE = 0x15;
  static const int ESCAPE_BYTE = 0x1B;

  // BSS Fader value constants (based on docs)
  static const int BSS_MIN_VALUE = -280617;  // -80dB
  static const int BSS_MAX_VALUE = 100000;   // +10dB
  static const int BSS_UNITY_VALUE = 0;      // 0dB
  static const double BSS_UNITY_NORMALIZED = 0.7373; // Point where 0dB occurs on fader
  
  // Parse HiQnet address string to list of bytes
  List<int> parseHiQnetAddress(String addressHex) {
    final hexString = addressHex.replaceAll("0x", "").replaceAll(" ", "");
    final bytes = <int>[];
    
    for (int i = 0; i < hexString.length; i += 2) {
      if (i + 2 <= hexString.length) {
        bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
      }
    }
    
    return bytes;
  }
  
  // Generate a command with checksum and byte substitution
  List<int> generateCommand(int commandType, List<int> addressBytes, int paramId, [int value = 0, int meterRate = 0]) {
    // Command structure:
    // 0x02 (start) + commandType + Address + ParamID + Value (optional) + Checksum + 0x03 (end)
    
    final command = <int>[commandType]; // Command type (SET, SUBSCRIBE, etc.)
    
    // Add address bytes
    command.addAll(addressBytes);
    
    // Add parameter ID (2 bytes)
    command.add((paramId >> 8) & 0xFF); // High byte
    command.add(paramId & 0xFF);        // Low byte
    
    // Add value (4 bytes) - only for SET commands
    if (commandType == MSG_TYPE_SET || commandType == MSG_TYPE_SET_PERCENT || commandType == MSG_TYPE_BUMP_PERCENT) {
      command.add((value >> 24) & 0xFF); // Byte 1 (MSB)
      command.add((value >> 16) & 0xFF); // Byte 2
      command.add((value >> 8) & 0xFF);  // Byte 3
      command.add(value & 0xFF);         // Byte 4 (LSB)
    } 
    // For meter parameter subscription, add meter rate
    else if ((commandType == MSG_TYPE_SUBSCRIBE || commandType == MSG_TYPE_SUBSCRIBE_PERCENT) && meterRate > 0) {
      command.add(0x00);                    // Byte 1 (MSB)
      command.add(0x00);                    // Byte 2
      command.add((meterRate >> 8) & 0xFF); // Byte 3
      command.add(meterRate & 0xFF);        // Byte 4 (LSB)
    }
    // For other commands that need data payload
    else if (commandType == MSG_TYPE_SUBSCRIBE || commandType == MSG_TYPE_UNSUBSCRIBE || 
             commandType == MSG_TYPE_SUBSCRIBE_PERCENT || commandType == MSG_TYPE_UNSUBSCRIBE_PERCENT) {
      command.add(0x00); // Byte 1 (MSB)
      command.add(0x00); // Byte 2
      command.add(0x00); // Byte 3
      command.add(0x00); // Byte 4 (LSB)
    }
    
    // Calculate checksum (XOR of all bytes in the command)
    int checksum = 0;
    for (int byte in command) {
      checksum ^= byte;
    }
    command.add(checksum);
    
    // Perform byte substitution
    final substitutedCommand = <int>[];
    for (int byte in command) {
      if (byte == START_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x82]);
      } else if (byte == END_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x83]);
      } else if (byte == ACK_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x86]);
      } else if (byte == NAK_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x95]);
      } else if (byte == ESCAPE_BYTE) {
        substitutedCommand.addAll([ESCAPE_BYTE, 0x9B]);
      } else {
        substitutedCommand.add(byte);
      }
    }
    
    // Add start and end bytes
    return [START_BYTE, ...substitutedCommand, END_BYTE];
  }
  
  // Generate a SET command (0x88)
  List<int> generateSetCommand(List<int> addressBytes, int paramId, int value) {
    return generateCommand(MSG_TYPE_SET, addressBytes, paramId, value);
  }
  
  // Generate a SET command from string address
  List<int> generateSetCommandFromString(String addressHex, String paramIdHex, int value) {
    final address = parseHiQnetAddress(addressHex);
    final paramId = int.parse(paramIdHex.replaceAll("0x", ""), radix: 16);
    return generateSetCommand(address, paramId, value);
  }
  
  // Generate a SET_PERCENT command (0x8D)
  List<int> generateSetPercentCommand(List<int> addressBytes, int paramId, int percentValue) {
    return generateCommand(MSG_TYPE_SET_PERCENT, addressBytes, paramId, percentValue);
  }
  
  // Generate a SUBSCRIBE command (0x89) with meter rate option
  List<int> generateSubscribeCommand(List<int> addressBytes, int paramId, [int meterRate = 0]) {
    return generateCommand(MSG_TYPE_SUBSCRIBE, addressBytes, paramId, 0, meterRate);
  }
  
  // Generate a SUBSCRIBE_PERCENT command (0x8E) with meter rate option
  List<int> generateSubscribePercentCommand(List<int> addressBytes, int paramId, [int meterRate = 0]) {
    return generateCommand(MSG_TYPE_SUBSCRIBE_PERCENT, addressBytes, paramId, 0, meterRate);
  }
  
  // Generate an UNSUBSCRIBE command (0x8A)
  List<int> generateUnsubscribeCommand(List<int> addressBytes, int paramId) {
    return generateCommand(MSG_TYPE_UNSUBSCRIBE, addressBytes, paramId);
  }
  
  // Generate an UNSUBSCRIBE_PERCENT command (0x8F)
  List<int> generateUnsubscribePercentCommand(List<int> addressBytes, int paramId) {
    return generateCommand(MSG_TYPE_UNSUBSCRIBE_PERCENT, addressBytes, paramId);
  }
  
  // Convert dB value to normalized range for meter display (0.0 to 1.0)
  double dbToNormalizedValue(double dbValue, {double minDb = -80.0, double maxDb = 40.0}) {
    final normalizedValue = (dbValue - minDb) / (maxDb - minDb);
    return normalizedValue.clamp(0.0, 1.0);
  }
  
  // Convert normalized value (0.0 to 1.0) to dB for meter display
  double normalizedToDbValue(double normalizedValue, {double minDb = -80.0, double maxDb = 40.0}) {
    return minDb + normalizedValue * (maxDb - minDb);
  }
  
  // Convert normalized value (0.0 to 1.0) to device value for faders
  int normalizedToFaderValue(double normalizedValue) {
    Logger().log('Converting normalized fader value: $normalizedValue');
    
    int deviceValue;
    
    // Handle edge cases
    if (normalizedValue <= 0.0) {
      deviceValue = BSS_MIN_VALUE;  // Minimum (-80dB)
      Logger().log('Minimum value detected, using -80dB: $deviceValue');
    } 
    else if (normalizedValue >= 1.0) {
      deviceValue = BSS_MAX_VALUE;  // Maximum (+10dB)
      Logger().log('Maximum value detected, using +10dB: $deviceValue');
    }
    // Unity gain (0dB) point
    else if ((normalizedValue - BSS_UNITY_NORMALIZED).abs() < 0.001) {
      deviceValue = BSS_UNITY_VALUE;  // Unity (0dB)
      Logger().log('Unity gain point detected, using 0dB: $deviceValue');
    }
    // Below unity gain
    else if (normalizedValue < BSS_UNITY_NORMALIZED) {
      // BSS faders use a logarithmic curve below unity gain
      // Linear interpolation of normalized values fails badly
      // Instead convert to dB first, then to device value
      
      // Calculate dB value (log scale): 
      // Map 0.0 -> -80dB, BSS_UNITY_NORMALIZED -> 0dB
      double normalizedBelow = normalizedValue / BSS_UNITY_NORMALIZED;
      
      // Use a special corrected formula based on analysis of BSS protocol values
      // This maps -80dB to MIN_VALUE and 0dB to UNITY_VALUE
      double dbValue = -80.0 * (1.0 - normalizedBelow);
      
      // Convert dB to device value directly using BSS fixed-point integer representation
      if (dbValue <= -60.0) {
        // Special scaling for very low values to avoid going to -infinity
        double attenFactor = (dbValue + 80.0) / 20.0;  // 0.0 to 1.0 range
        deviceValue = (BSS_MIN_VALUE * (1.0 - attenFactor)).round();
      } else {
        // More precise scaling for higher values
        // BSS uses a power of 10 calculation for dB
        double gain = pow(10, dbValue / 20.0);
        
        // Scale gain to device units
        deviceValue = ((gain - 1.0) * 100000).round();
        
        // For negative dB, device value is negative
        if (dbValue < 0) {
          // Apply additional scaling factor for better matching
          deviceValue = (deviceValue * 1.015).round();
        }
      }
      
      Logger().log('Below unity calculation: $normalizedValue -> $normalizedBelow -> ${dbValue}dB -> $deviceValue');
    }
    // Above unity gain
    else {
      // Linear scaling from UNITY to MAX
      double normalizedAbove = (normalizedValue - BSS_UNITY_NORMALIZED) / (1.0 - BSS_UNITY_NORMALIZED);
      deviceValue = (BSS_UNITY_VALUE + (BSS_MAX_VALUE - BSS_UNITY_VALUE) * normalizedAbove).round();
      
      Logger().log('Above unity calculation: $normalizedValue -> $normalizedAbove -> $deviceValue');
    }
    
    // Ensure value is in valid range
    deviceValue = deviceValue.clamp(BSS_MIN_VALUE, BSS_MAX_VALUE);
    
    Logger().log('Final calculated device value: $deviceValue');
    return deviceValue;
  }
  
  // Convert device value to normalized value (0.0 to 1.0) for faders
  double faderValueToNormalized(int deviceValue) {
    // Handle unsigned/signed conversion
    double signedValue = deviceValue.toDouble();
    bool isUnsigned = false;
    
    if ((deviceValue & 0x80000000) != 0) {
      signedValue = deviceValue - 0x100000000;
      isUnsigned = true;
      Logger().log('Device fader value to convert: $deviceValue (0x${deviceValue.toRadixString(16).toUpperCase()})');
      Logger().log('Converted unsigned value to signed: $signedValue');
    } else {
      Logger().log('Device fader value to convert: $deviceValue (0x${deviceValue.toRadixString(16).toUpperCase()})');
    }
    
    double normalizedValue;
    
    // Handle edge cases
    if (signedValue <= BSS_MIN_VALUE) {
      normalizedValue = 0.0;
      Logger().log('Minimum value detected, using normalized 0.0');
    }
    else if (signedValue >= BSS_MAX_VALUE) {
      normalizedValue = 1.0;
      Logger().log('Maximum value detected, using normalized 1.0');
    }
    // Unity gain (0dB) exact point
    else if (signedValue == BSS_UNITY_VALUE) {
      normalizedValue = BSS_UNITY_NORMALIZED;
      Logger().log('Unity gain value detected, using exact normalized value: $normalizedValue');
    }
    // Below unity gain (negative values in BSS)
    else if (signedValue < BSS_UNITY_VALUE) {
      // Convert to dB scale first
      // For values close to minimum, special handling to avoid extreme values
      if (signedValue <= -250000) {
        // Near minimum, use linear scaling for the tail end
        double fraction = (signedValue - BSS_MIN_VALUE) / (-250000 - BSS_MIN_VALUE);
        normalizedValue = fraction * 0.1; // Scale to 0.0-0.1 range
      } else {
        // Convert to dB and use logarithmic mapping
        // This is the approximate inverse of the sending formula
        
        // Calculate dB attenuation from device value
        // Map device value to dB, then to normalized value
        double fraction = (signedValue - BSS_MIN_VALUE) / (BSS_UNITY_VALUE - BSS_MIN_VALUE);
        double dbValue = -80.0 * (1.0 - fraction);
        
        // Map dB value to normalized range
        normalizedValue = (dbValue + 80.0) / 80.0 * BSS_UNITY_NORMALIZED;
      }
      
      Logger().log('Below unity calculation: $signedValue -> $normalizedValue');
    }
    // Above unity gain (positive values in BSS)
    else {
      // Linear scaling for above unity
      double fraction = (signedValue - BSS_UNITY_VALUE) / (BSS_MAX_VALUE - BSS_UNITY_VALUE);
      normalizedValue = BSS_UNITY_NORMALIZED + (1.0 - BSS_UNITY_NORMALIZED) * fraction;
      
      Logger().log('Above unity calculation: $signedValue -> $fraction -> $normalizedValue');
    }
    
    // Ensure value is within valid range
    normalizedValue = normalizedValue.clamp(0.0, 1.0);
    
    Logger().log('Final normalized value: ${normalizedValue.toStringAsFixed(4)}');
    return normalizedValue;
  }
}