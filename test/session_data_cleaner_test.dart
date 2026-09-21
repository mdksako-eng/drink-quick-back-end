// test/session_data_cleaner_test.dart
// Shared-device privacy: after a company logs out (or a customer signs in) no
// company name/logo/currency may survive on the device.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/services/company_branding_service.dart';
import 'package:drinks_calculator_fixed/services/session_data_cleaner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('every company-scoped key is wiped on logout', () async {
    final prefs = SharedPreferences.getInstance();
    final store = await prefs;
    for (final key in SessionDataCleaner.companyScopedKeys) {
      await store.setString(key, 'previous-company-value');
    }
    await store.setInt('last_company_id', 42);
    // User preferences must survive.
    await store.setBool('compact_mode', true);
    await store.setInt('theme_mode', 1);
    await store.setString('language', 'fr');

    await SessionDataCleaner.clearCompanyData(companyId: 42);

    final after = await SharedPreferences.getInstance();
    for (final key in SessionDataCleaner.companyScopedKeys) {
      expect(after.get(key), isNull, reason: '$key must be cleared');
    }
    expect(after.getInt('last_company_id'), isNull);
    expect(after.getBool('compact_mode'), isTrue);
    expect(after.getInt('theme_mode'), 1);
    expect(after.getString('language'), 'fr');
  });

  test('the logo cache is per company, so it cannot leak', () async {
    final store = await SharedPreferences.getInstance();
    await store.setString(CompanyBrandingService.cacheKeyFor(7), 'https://a/7.png');
    await store.setString(CompanyBrandingService.cacheKeyFor(9), 'https://a/9.png');
    await store.setString(CompanyBrandingService.prefsKey, 'https://legacy/logo.png');

    await CompanyBrandingService.clearLocal(companyId: 7);

    final after = await SharedPreferences.getInstance();
    expect(after.getString(CompanyBrandingService.cacheKeyFor(7)), isNull);
    expect(after.getString(CompanyBrandingService.cacheKeyFor(9)),
        'https://a/9.png');
    expect(after.getString(CompanyBrandingService.prefsKey), isNull);
  });

  test('cacheKeyFor is company specific', () {
    expect(CompanyBrandingService.cacheKeyFor(12), 'company_logo_url_12');
    expect(CompanyBrandingService.cacheKeyFor(null), 'company_logo_url_null');
  });

  test('clearing with no stored company id still clears the caches', () async {
    final store = await SharedPreferences.getInstance();
    await store.setString('company_name', 'Old Shop');
    await store.setString('currency_symbol', 'XAF');

    await SessionDataCleaner.clearCompanyData();

    final after = await SharedPreferences.getInstance();
    expect(after.getString('company_name'), isNull);
    expect(after.getString('currency_symbol'), isNull);
  });
}
