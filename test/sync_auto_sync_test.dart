// test/sync_auto_sync_test.dart
// The Auto Sync switch used to be written to preferences and ignored: the
// background timer synced every 45s no matter what the user chose. These tests
// pin the real behaviour (default on, honours the stored value, reacts to the
// switch immediately).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drinks_calculator_fixed/providers/sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to enabled when nothing was ever stored', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SyncProvider();
    // _loadAutoSync is async; give it a turn.
    await Future<void>.delayed(Duration.zero);
    expect(provider.autoSync, isTrue);
    provider.dispose();
  });

  test('honours a stored "off" choice', () async {
    SharedPreferences.setMockInitialValues({'auto_sync': false});
    final provider = SyncProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.autoSync, isFalse);
    provider.dispose();
  });

  test('setAutoSync flips the flag and persists it', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SyncProvider();
    await Future<void>.delayed(Duration.zero);

    await provider.setAutoSync(false);
    expect(provider.autoSync, isFalse);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_sync'), isFalse);

    await provider.setAutoSync(true);
    expect(provider.autoSync, isTrue);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_sync'), isTrue);
    provider.dispose();
  });

  test('the setting survives a restart (new provider reads it back)', () async {
    SharedPreferences.setMockInitialValues({'auto_sync': false});
    final first = SyncProvider();
    await Future<void>.delayed(Duration.zero);
    await first.setAutoSync(false);
    first.dispose();

    final second = SyncProvider();
    await Future<void>.delayed(Duration.zero);
    expect(second.autoSync, isFalse);
    second.dispose();
  });

  test('manual sync is still allowed while auto sync is off', () async {
    SharedPreferences.setMockInitialValues({'auto_sync': false});
    final provider = SyncProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.autoSync, isFalse);
    // Offline in the test environment → the call must be a safe no-op, not a
    // crash, and must not throw.
    expect(() => provider.manualSync(), returnsNormally);
    provider.dispose();
  });
}
