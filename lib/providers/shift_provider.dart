// providers/shift_provider.dart
import 'package:flutter/foundation.dart';

import '../models/shift_model.dart';
import '../services/supabase_service.dart';

/// The till session of this device: the shift that is open, its live Z-report
/// and the past shifts.
///
/// STAFF open a shift with the float in the drawer and close it with the cash
/// they counted; a MANAGER may close anyone's (the backend enforces the rule —
/// utils/shiftMath.js — this only surfaces what it decides).
class ShiftProvider extends ChangeNotifier {
  Shift? _current;
  ShiftSummary? _summary;
  List<Shift> _history = const [];
  bool _loading = false;
  bool _offline = false;

  /// The open shift of the signed-in user, or null when the till is closed.
  Shift? get current => _current;

  /// Live numbers of the current shift (null while no shift is open).
  ShiftSummary? get summary => _summary;

  /// Past shifts, newest first.
  List<Shift> get history => _history;

  bool get loading => _loading;

  /// True when the last load had to give up (offline / not signed in).
  bool get offline => _offline;

  bool get isOpen => _current != null && _current!.isOpen;

  /// Loads the current shift + history, then the live Z-report of the shift.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    final currentRow = await SupabaseService.getCurrentShift();
    final historyRows = await SupabaseService.getShifts();

    _offline = historyRows == null;
    if (historyRows != null) {
      _history = historyRows.map(Shift.fromJson).toList();
    }
    _current = currentRow == null ? null : Shift.fromJson(currentRow);
    _summary = _current == null ? null : await refreshSummary(_current!.id);

    _loading = false;
    notifyListeners();
  }

  /// The live Z-report of a shift (preview before closing, or the frozen one).
  Future<ShiftSummary?> refreshSummary(int shiftId) async {
    final row = await SupabaseService.getShiftSummary(shiftId);
    return row == null ? null : ShiftSummary.fromJson(row);
  }

  /// Opens a shift with [openingFloat]. False when the server refused (e.g. a
  /// shift is already open for this user).
  Future<bool> open({required double openingFloat}) async {
    final row = await SupabaseService.openShift(openingFloat: openingFloat);
    if (row == null) return false;
    _current = Shift.fromJson(row);
    await load();
    return true;
  }

  /// Closes the current shift and returns its frozen Z-report, or null when the
  /// server refused (already closed, not your shift, offline…).
  Future<ShiftSummary?> close({
    required double cashCounted,
    double? cashPayouts,
    String? notes,
  }) async {
    final shift = _current;
    if (shift == null) return null;

    final result = await SupabaseService.closeShift(
      shift.id,
      cashCounted: cashCounted,
      cashPayouts: cashPayouts,
      notes: notes,
    );
    if (result == null) return null;

    final summaryRow = result['summary'];
    final frozen = summaryRow is Map
        ? ShiftSummary.fromJson(Map<String, dynamic>.from(summaryRow))
        : null;

    // Re-read the state: the current shift is now closed, so the next load
    // returns no open shift and the closed one lands in the history.
    await load();
    return frozen;
  }
}
