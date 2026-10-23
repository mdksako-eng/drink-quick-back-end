// test/order_totals_test.dart
// The new-order notification said "1 item" for a sale of 24 crates, because it
// counted cart LINES. The cart merges a repeated drink into one line with a
// quantity, so a line count is not a drink count. These tests pin the unit total.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/utils/order_totals.dart';

class _Line {
  final int quantity;
  _Line(this.quantity);
}

class _NoQuantity {}

class _NumLine {
  final num quantity;
  _NumLine(this.quantity);
}

void main() {
  test('an empty cart is zero units', () {
    expect(totalUnits(const []), 0);
  });

  test('one line of 24 crates is 24 units, not 1 line', () {
    expect(totalUnits([_Line(24)]), 24);
  });

  test('a mixed cart sums every line', () {
    expect(totalUnits([_Line(2), _Line(24), _Line(1)]), 27);
  });

  test('two lines of the same drink still add up', () {
    expect(totalUnits([_Line(12), _Line(12)]), 24);
  });

  test('a zero or negative quantity contributes nothing', () {
    expect(totalUnits([_Line(0), _Line(5), _Line(-3)]), 5);
  });

  test('a line with no usable quantity counts as one unit', () {
    expect(totalUnits([_NoQuantity()]), 1);
  });

  test('null entries are skipped', () {
    expect(totalUnits([null, _Line(3), null]), 3);
  });

  test('a num quantity is accepted and truncated', () {
    expect(totalUnits([_Line(2), _NumLine(2.5)]), 4);
  });
}
