import 'dart:async';

import 'package:flutter/material.dart';
import 'package:session_recorder_flutter/src/constants/gestures_constants.dart';
import 'package:session_recorder_flutter/src/models/models.dart';
import 'package:session_recorder_flutter/src/utils/recorder_callback.dart';

final class DoubleTapTracker {
  final void Function(ActionEvent event) _recordAction;

  // Completed taps keep frozen gesture and LOM data until they are matched or
  // their double-tap window expires.
  final List<_PendingTap> _pendingTaps = [];

  Timer? _doubleTapTimer;
  int? _scheduledDoubleTapExpiry;
  int _contactOrder = 0;

  DoubleTapTracker({required void Function(ActionEvent event) recordAction})
      : _recordAction = recordAction;

  int registerPointerDown() => ++_contactOrder;

  int registerPointerUp() => ++_contactOrder;

  void completeTap(PointerTrace trace, {required int upOrder}) {
    final current = _PendingTap(
      downTimestamp: trace.firstTimestamp,
      upTimestamp: trace.lastTimestamp,
      downOrder: trace.downOrder,
      upOrder: upOrder,
      actionPosition: trace.firstPosition,
      terminalPosition: trace.lastPosition,
      viewport: trace.first.viewport,
      lomRef: trace.lomRef,
      isLomStateResolved: trace.isLomStateResolved,
    );

    final expired = _takeExpiredPendingTaps(current.upTimestamp);
    final matchIndex = _findBestTapMatch(current);
    _PendingTap? first;

    if (matchIndex == null) {
      _pendingTaps.add(current);
    } else {
      first = _pendingTaps.removeAt(matchIndex);
    }

    _rescheduleDoubleTapExpiry();
    _emitPendingTaps(expired);

    if (first != null) _emitDoubleTap(first, current);
  }

  void resolveRelatedPendingBeforeNonTap(PointerTrace trace) {
    if (trace.isEmpty || _pendingTaps.isEmpty) return;

    final expired = _takeExpiredPendingTaps(trace.lastTimestamp);
    final relatedIndex = _findRelatedPendingForInteraction(trace);
    final related =
        relatedIndex == null ? null : _pendingTaps.removeAt(relatedIndex);

    if (expired.isNotEmpty || related != null) {
      _rescheduleDoubleTapExpiry();
    }

    _emitPendingTaps(expired);
    if (related != null) _emitPendingTap(related);
  }

  void drain() {
    _cancelDoubleTapTimer();
    if (_pendingTaps.isEmpty) return;

    final pending = List<_PendingTap>.of(_pendingTaps);
    _pendingTaps.clear();
    _emitPendingTaps(pending);
  }

  int? _findBestTapMatch(_PendingTap second) {
    return _findBestCompatiblePending(
      downTimestamp: second.downTimestamp,
      downOrder: second.downOrder,
      matchTimestamp: second.upTimestamp,
      comparisonPosition: second.terminalPosition,
      viewport: second.viewport,
      lomRef: second.lomRef,
      isLomStateResolved: second.isLomStateResolved,
    );
  }

  int? _findRelatedPendingForInteraction(PointerTrace trace) {
    // Non-tap invalidation is anchored at the interaction origin.
    return _findBestCompatiblePending(
      downTimestamp: trace.firstTimestamp,
      downOrder: trace.downOrder,
      matchTimestamp: trace.lastTimestamp,
      comparisonPosition: trace.firstPosition,
      viewport: trace.first.viewport,
      lomRef: trace.lomRef,
      isLomStateResolved: trace.isLomStateResolved,
    );
  }

  int? _findBestCompatiblePending({
    required int downTimestamp,
    required int downOrder,
    required int matchTimestamp,
    required Offset comparisonPosition,
    required Rect viewport,
    required String lomRef,
    required bool isLomStateResolved,
  }) {
    int? bestIndex;
    double? bestDistance;
    int? bestUpOrder;

    /// All pending taps remain independent candidates so separate double-tap
    /// streams can coexist; distance and recency choose only one match.
    for (var i = 0; i < _pendingTaps.length; i++) {
      final pending = _pendingTaps[i];

      /// Contact order forbids physically overlapping fingers from masquerading
      /// as sequential taps even when their timestamps are close.
      if (downOrder <= pending.upOrder || downTimestamp < pending.upTimestamp) {
        continue;
      }

      final elapsed = matchTimestamp - pending.upTimestamp;
      if (elapsed < 0 || elapsed > doubleTapTimeout.inMilliseconds) continue;
      if (viewport != pending.viewport ||
          !isLomStateResolved ||
          !pending.isLomStateResolved ||
          lomRef != pending.lomRef) {
        continue;
      }

      final distance = (comparisonPosition - pending.terminalPosition).distance;
      if (distance >= doubleTapSlop) continue;

      if (bestDistance == null ||
          distance < bestDistance ||
          (distance == bestDistance && pending.upOrder > bestUpOrder!)) {
        bestIndex = i;
        bestDistance = distance;
        bestUpOrder = pending.upOrder;
      }
    }

    return bestIndex;
  }

  List<_PendingTap> _takeExpiredPendingTaps(int now) {
    final expired = <_PendingTap>[];
    _pendingTaps.removeWhere((pending) {
      /// Equality remains eligible for matching; expiry begins just beyond the
      /// inclusive double-tap timeout boundary.
      final isExpired = now > pending.lastEligibleTimestamp;
      if (isExpired) expired.add(pending);
      return isExpired;
    });
    return expired;
  }

  void _emitExpiredPendingTaps(int now) {
    final expired = _takeExpiredPendingTaps(now);
    _rescheduleDoubleTapExpiry();
    _emitPendingTaps(expired);
  }

  void _rescheduleDoubleTapExpiry() {
    if (_pendingTaps.isEmpty) {
      _cancelDoubleTapTimer();
      return;
    }

    var nextExpiry = _pendingTaps.first.expiryDeadline;
    for (var i = 1; i < _pendingTaps.length; i++) {
      final expiry = _pendingTaps[i].expiryDeadline;
      if (expiry < nextExpiry) nextExpiry = expiry;
    }

    if ((_doubleTapTimer?.isActive ?? false) &&
        _scheduledDoubleTapExpiry == nextExpiry) {
      return;
    }

    _cancelDoubleTapTimer();
    final now = DateTime.now().millisecondsSinceEpoch;
    final delay = nextExpiry > now ? nextExpiry - now : 0;
    _scheduledDoubleTapExpiry = nextExpiry;

    // One timer owns the next expiry across all pending taps.
    late final Timer timer;
    timer = Timer(Duration(milliseconds: delay), () {
      if (!identical(_doubleTapTimer, timer)) return;
      _doubleTapTimer = null;
      _scheduledDoubleTapExpiry = null;
      runRecorderCallback('double tap expiry', () {
        _emitExpiredPendingTaps(DateTime.now().millisecondsSinceEpoch);
      });
    });
    _doubleTapTimer = timer;
  }

  void _cancelDoubleTapTimer() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _scheduledDoubleTapExpiry = null;
  }

  void _emitPendingTaps(Iterable<_PendingTap> pendingTaps) {
    for (final pending in pendingTaps) {
      // A failed delivery must not discard the other independent pending taps.
      runRecorderCallback(
          'pending tap delivery', () => _emitPendingTap(pending));
    }
  }

  void _emitPendingTap(_PendingTap pending) {
    _recordAction(
      TapActionEvent(
        timestampRelative: pending.downTimestamp,
        viewport: pending.viewport,
        position: pending.actionPosition,
        lomRef: pending.lomRef,
      ),
    );
  }

  void _emitDoubleTap(_PendingTap first, _PendingTap second) {
    _recordAction(
      DoubleTapActionEvent(
        timestampRelative: first.downTimestamp,
        secondTimestamp: second.downTimestamp,
        viewport: first.viewport,
        positions: [first.actionPosition, second.actionPosition],
        lomRef: first.lomRef,
      ),
    );
  }
}

final class _PendingTap {
  final int downTimestamp;
  final int upTimestamp;
  final int downOrder;
  final int upOrder;
  final Offset actionPosition;
  final Offset terminalPosition;
  final Rect viewport;
  final String lomRef;
  final bool isLomStateResolved;

  const _PendingTap({
    required this.downTimestamp,
    required this.upTimestamp,
    required this.downOrder,
    required this.upOrder,
    required this.actionPosition,
    required this.terminalPosition,
    required this.viewport,
    required this.lomRef,
    required this.isLomStateResolved,
  });

  int get lastEligibleTimestamp =>
      upTimestamp + doubleTapTimeout.inMilliseconds;

  int get expiryDeadline => lastEligibleTimestamp + 1;
}
