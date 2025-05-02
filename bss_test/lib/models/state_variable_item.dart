import 'package:xml/xml.dart';

class StateVariableItem {
  final bool isSVFromAppNode;
  final int nodeID;
  final int vdIndex;
  final int objID;
  final int svID;
  final int nubIdx;
  final int nodeClassID;
  final int svClassID;
  final int objectClassID;

  StateVariableItem({
    required this.isSVFromAppNode,
    required this.nodeID,
    required this.vdIndex,
    required this.objID,
    required this.svID,
    required this.nubIdx,
    required this.nodeClassID,
    required this.svClassID,
    required this.objectClassID,
  });

  factory StateVariableItem.fromXmlElement(XmlElement element) {
    return StateVariableItem(
      isSVFromAppNode: element.getAttribute('IsSVFromAppNode') == 'True',
      nodeID: int.tryParse(element.getAttribute('NodeID') ?? '0') ?? 0,
      vdIndex: int.tryParse(element.getAttribute('VdIndex') ?? '0') ?? 0,
      objID: int.tryParse(element.getAttribute('ObjID') ?? '0') ?? 0,
      svID: int.tryParse(element.getAttribute('svID') ?? '0') ?? 0,
      nubIdx: int.tryParse(element.getAttribute('nubIdx') ?? '0') ?? 0,
      nodeClassID: int.tryParse(element.getAttribute('NodeClassID') ?? '0') ?? 0,
      svClassID: int.tryParse(element.getAttribute('SVClassID') ?? '0') ?? 0,
      objectClassID: int.tryParse(element.getAttribute('ObjectClassID') ?? '0') ?? 0,
    );
  }

  // Helper method to get a HiQnet address from the state variable
  String get hiQnetAddress {
    // Format to match the exact format used in our test components (fixed-width format)
    return '0x${nodeID.toRadixString(16).padLeft(2, '0')}${vdIndex.toRadixString(16).padLeft(2, '0')}${objID.toRadixString(16).padLeft(6, '0')}';
  }

  // Helper method to get the parameter ID
  String get parameterID {
    return '0x${svID.toRadixString(16)}';
  }
  
  // Helper method to get a unique key for this state variable
  String get uniqueKey {
    return '${hiQnetAddress.toLowerCase()}:${parameterID.toLowerCase()}';
  }

  @override
  String toString() {
    return 'StateVar(NodeID: $nodeID, ObjID: $objID, svID: $svID)';
  }
}