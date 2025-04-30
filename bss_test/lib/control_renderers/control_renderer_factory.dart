import 'package:flutter/material.dart';
import '../models/control_model.dart';
import '../models/control_types.dart';
import 'button_renderer.dart';
import 'bare_fader_renderer.dart';
import 'label_renderer.dart';
import 'meter_renderer.dart';
import 'rectangle_renderer.dart';
import 'selector_renderer.dart';

class ControlRendererFactory {
  static Widget createRenderer(ControlModel control) {
    switch (control.controlType) {
      case ControlType.button:
        return ButtonRenderer(control: control);
      case ControlType.fader:
        return BareFaderRenderer(control: control);
      case ControlType.meter:
        return MeterRenderer(control: control);
      case ControlType.selector:
        return SelectorRenderer(control: control);
      case ControlType.label:
        return LabelRenderer(control: control);
      case ControlType.rectangle:
        return RectangleRenderer(control: control);
      case ControlType.unknown:
        return Text(
          control.name,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        );
    }
  }
}