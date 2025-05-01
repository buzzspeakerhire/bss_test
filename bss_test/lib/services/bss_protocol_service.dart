import '../utils/hex_utils.dart';
import '../utils/logger.dart';

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
    return (dbValue - minDb) / (maxDb - minDb);
  }
  
  // Convert normalized value (0.0 to 1.0) to dB for meter display
  double normalizedToDbValue(double normalizedValue, {double minDb = -80.0, double maxDb = 40.0}) {
    return minDb + normalizedValue * (maxDb - minDb);
  }
  
  // Convert normalized value (0.0 to 1.0) to device value for faders
  int normalizedToFaderValue(double normalizedValue) {
    // Max value = 0x0186A0 (100000), Min value = 0xFFFBB7D7 (-280617)
    final double maxValue = 0x0186A0.toDouble();
    final double minValue = -280617.0; // 0xFFFBB7D7 as signed integer
    return (minValue + normalizedValue * (maxValue - minValue)).toInt();
  }
  
  // Convert device value to normalized value (0.0 to 1.0) for faders
  double faderValueToNormalized(int deviceValue) {
    final double maxValue = 0x0186A0.toDouble(); // 100000
    final double minValue = -280617.0; // 0xFFFBB7D7 as signed integer
    
    // Handle signed values
    double signedValue = deviceValue.toDouble();
    if (deviceValue > 0x7FFFFFFF) {
      signedValue = -(0x100000000 - deviceValue).toDouble();
    }
    
    double normalizedValue = (signedValue - minValue) / (maxValue - minValue);
    return normalizedValue.clamp(0.0, 1.0);
  }
}