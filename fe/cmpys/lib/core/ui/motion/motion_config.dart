import 'package:flutter/widgets.dart';

/// Central reduced-motion switch for the CMPYS motion kit.
///
/// Reads the platform "disable animations" accessibility setting. Kit
/// widgets collapse to plain fades (or render statically) when motion is
/// off — screens never check this themselves.
abstract final class MotionConfig {
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);
}
