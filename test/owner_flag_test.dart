// test/owner_flag_test.dart
// The owner flag has been lost twice, in two different places: once while parsing the
// backend response (BackendAuthService.User had no isOwner field at all) and once when
// the provider built its User by hand and omitted it, silently defaulting to false. Both
// layers are pinned here so a paying shop's real owner cannot be demoted again.
import 'package:flutter_test/flutter_test.dart';
import 'package:drinks_calculator_fixed/providers/auth_provider.dart' as provider;
import 'package:drinks_calculator_fixed/services/backend_auth_service.dart' as backend;

void main() {
  /// The exact shape /api/auth/login returns (see the debug log for user 'onean').
  Map<String, dynamic> payload() => <String, dynamic>{
        'id': 32,
        'username': 'onean',
        'email': 'mdksako@gmail.com',
        'role': 'Manager',
        'companyId': 42,
        'emailVerified': true,
        'isOwner': true,
      };

  group('AuthProvider.User', () {
    test('keeps isOwner from the login payload', () {
      expect(provider.User.fromJson(payload()).isOwner, isTrue);
    });

    test('keeps isOwner when the backend replies in snake_case', () {
      final json = payload()..remove('isOwner');
      json['is_owner'] = true;
      expect(provider.User.fromJson(json).isOwner, isTrue);
    });

    test('is not an owner when the flag is absent', () {
      expect(provider.User.fromJson(payload()..remove('isOwner')).isOwner, isFalse);
    });

    test('survives the storage round trip', () {
      // The app writes the user to storage and reloads it on the next cold start; a
      // flag that toJson drops would come back false and hide owner-only actions.
      final user = provider.User.fromJson(payload());
      expect(provider.User.fromJson(user.toJson()).isOwner, isTrue);
    });
  });

  group('BackendAuthService.User', () {
    test('parses isOwner instead of dropping it', () {
      expect(backend.User.fromJson(payload()).isOwner, isTrue);
    });

    test('is not an owner when the flag is absent', () {
      expect(backend.User.fromJson(payload()..remove('isOwner')).isOwner, isFalse);
    });
  });
}
