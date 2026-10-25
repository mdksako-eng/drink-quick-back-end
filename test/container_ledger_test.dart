// test/container_ledger_test.dart
// Returnable containers: the same rules the backend enforces
// (drinks-calculator-backend/utils/containerLedger.js), mirrored so the app
// hides what the server would refuse anyway.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/models/container_model.dart';
import 'package:drinks_calculator_fixed/utils/container_ledger_helper.dart';

ContainerMovement move({
  int id = 1,
  int customerId = 1,
  int containerTypeId = 1,
  String kind = 'out',
  int quantity = 1,
}) =>
    ContainerMovement(
      id: id,
      customerId: customerId,
      containerTypeId: containerTypeId,
      kind: kind,
      quantity: quantity,
    );

void main() {
  group('who may record what', () {
    test('staff hand out and take back at the counter', () {
      expect(ContainerLedgerHelper.canRecord('Staff'), isTrue);
      expect(ContainerLedgerHelper.canRecord('Manager'), isTrue);
    });

    test('a write-off is stock disappearing, so a manager alone may do it', () {
      expect(ContainerLedgerHelper.canWriteOff('Staff'), isFalse);
      expect(ContainerLedgerHelper.canWriteOff('Manager'), isTrue);
      expect(ContainerLedgerHelper.canWriteOff('Administrator'), isTrue);
    });

    test('a customer records nothing, and the list is shop setup', () {
      expect(ContainerLedgerHelper.canRecord('Customer'), isFalse);
      expect(ContainerLedgerHelper.canRecord(null), isFalse);
      expect(ContainerLedgerHelper.canManageTypes('Staff'), isFalse);
      expect(ContainerLedgerHelper.canManageTypes('Manager'), isTrue);
    });
  });

  group('the balance is summed, never stored', () {
    final movements = [
      move(id: 1, containerTypeId: 1, kind: 'out', quantity: 5),
      move(id: 2, containerTypeId: 1, kind: 'back', quantity: 2),
      move(id: 3, containerTypeId: 1, kind: 'writeoff', quantity: 1),
      move(id: 4, containerTypeId: 2, kind: 'out', quantity: 3),
    ];

    test('out - back - writeoff', () {
      final totals = ContainerLedgerHelper.totalsFor(movements);
      expect(totals.out, 8);
      expect(totals.back, 2);
      expect(totals.writtenOff, 1);
      expect(totals.outstanding, 5);
      expect(totals.holdsAny, isTrue);
    });

    test('an empty ledger holds nothing, and unknown kinds are ignored', () {
      expect(ContainerLedgerHelper.totalsFor([]).outstanding, 0);
      expect(ContainerLedgerHelper.totalsFor([]).holdsAny, isFalse);
      expect(
        ContainerLedgerHelper.totalsFor([move(kind: 'lost', quantity: 9)])
            .outstanding,
        0,
      );
    });

    test('per container type, and per customer', () {
      expect(ContainerLedgerHelper.outstandingFor(movements, 1), 2);
      expect(ContainerLedgerHelper.outstandingFor(movements, 2), 3);
      expect(ContainerLedgerHelper.outstandingFor(movements, 99), 0);
      expect(
        ContainerLedgerHelper.totalsForCustomer(1, movements).outstanding,
        5,
      );
      expect(
        ContainerLedgerHelper.totalsForCustomer(2, movements).outstanding,
        0,
      );
    });

    test('types with nothing outstanding are dropped, biggest pile first', () {
      final types = [
        const ContainerType(id: 1, name: 'Crate 33cl', depositValue: 1000),
        const ContainerType(id: 2, name: 'Bottle 65cl', depositValue: 100),
        const ContainerType(id: 3, name: 'Pallet', depositValue: 0),
      ];
      final rows = ContainerLedgerHelper.outstandingByType(types, movements);
      expect(rows.map((r) => r.containerTypeId).toList(), [2, 1]);
      expect(rows.first.outstanding, 3);
      expect(rows.first.value, 300); // deposit is informational only
      expect(rows.last.value, 2000);
    });
  });

  group('a movement is refused when the pile cannot cover it', () {
    test('handing out is always allowed', () {
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Staff',
          kind: 'out',
          quantity: 24,
          outstanding: 0,
        ),
        isNull,
      );
    });

    test('taking back exactly what is out is allowed', () {
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Staff',
          kind: 'back',
          quantity: 5,
          outstanding: 5,
        ),
        isNull,
      );
    });

    test('more than is out is refused, back or write-off', () {
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Staff',
          kind: 'back',
          quantity: 6,
          outstanding: 5,
        ),
        'exceedsOutstanding',
      );
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Manager',
          kind: 'writeoff',
          quantity: 6,
          outstanding: 5,
        ),
        'exceedsOutstanding',
      );
    });

    test('staff cannot write off, and a zero quantity never lands', () {
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Staff',
          kind: 'writeoff',
          quantity: 1,
          outstanding: 5,
        ),
        'writeOffNeedsManager',
      );
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Staff',
          kind: 'out',
          quantity: 0,
          outstanding: 0,
        ),
        'quantityPositive',
      );
      expect(
        ContainerLedgerHelper.movementProblem(
          role: 'Manager',
          kind: 'gone',
          quantity: 1,
          outstanding: 5,
        ),
        'unknownKind',
      );
    });
  });

  group('labels and order', () {
    test('movements come back newest first', () {
      final rows = ContainerLedgerHelper.newestFirst([
        ContainerMovement(
          id: 1,
          customerId: 1,
          containerTypeId: 1,
          kind: 'out',
          quantity: 1,
          createdAt: DateTime(2026, 1, 1),
        ),
        ContainerMovement(
          id: 2,
          customerId: 1,
          containerTypeId: 1,
          kind: 'back',
          quantity: 1,
          createdAt: DateTime(2026, 5, 1),
        ),
      ]);
      expect(rows.first.id, 2);
    });

    test('every kind and refusal maps to an i18n key, never to text', () {
      expect(ContainerLedgerHelper.kindKey('out'), 'contKindOut');
      expect(ContainerLedgerHelper.kindKey('back'), 'contKindBack');
      expect(ContainerLedgerHelper.kindKey('writeoff'), 'contKindWriteoff');
      expect(
        ContainerLedgerHelper.problemKey('exceedsOutstanding'),
        'contErrTooMany',
      );
      expect(
        ContainerLedgerHelper.problemKey('writeOffNeedsManager'),
        'contErrWriteOffManager',
      );
      expect(ContainerLedgerHelper.problemKey(null), 'contErrGeneric');
    });
  });
}
