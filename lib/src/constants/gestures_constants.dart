import 'package:flutter/gestures.dart';

/// The total movement constant
const double touchSlop = 8.0;

/// The total scale constant
const double scaleSlop = touchSlop;

/// The total movement constant
final double doubleTapTouchSlop = kDoubleTapTouchSlop;

/// The maximum duration for a second touch
final Duration doubleTapTimeout = kDoubleTapTimeout;

/// The time before a long press gesture attempts to win.
final Duration longPressTimeout = kLongPressTimeout;

// * SCALE CONSTS

/// Ratio between radial and tangential movement required
/// to consider the gesture a valid zoom.
///
/// If radial movement is smaller than [tangentialRms] * [radialToTang],
/// the gesture is treated as noise or rotation instead.
const double radialToTang = 1.5;

/// Minimum fraction of fingers that must move coherently
/// (in the same radial direction) for the gesture to be consistent.
/// ```
/// Example: 0.6 = at least 60% of the fingers agree.
/// ```
const double consistencyFraction = 0.6;

/// Minimum relative scale change to trigger a zoom event.
///
/// ```
/// Example: 0.05 = 5% zoom in or out.
/// ```
const double scaleThreshold = 0.05;

/// Minimum absolute change in average distance (in pixels)
/// required to trigger a zoom gesture — useful for small or slow movements.
const double scalePxThreshold = 6.0;
