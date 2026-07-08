import 'policy_urls.dart';
import 'veiled_bytes.dart';

// ============================================================
// MissionFacade — single access point for app-wide constants
// ============================================================
// Identity strings ship as plaintext (they show up in the store listing
// anyway); endpoints / credentials resolve through the obfuscator so
// plaintext never lands in the binary.
// ============================================================

class MissionFacade {
  MissionFacade._();

  // Identity — must match android/app/build.gradle.kts applicationId,
  // AndroidManifest android:label, and the store listing exactly.
  static const String packageId = 'com.volcano.emberdrift';
  static const String marketId = 'com.volcano.emberdrift';
  static const String displayTitle = 'Ember Drift';

  // iOS store id — unused on Android (Android-only build).
  static const String appleStoreId = '';

  // Endpoints / credentials — pulled from the obfuscated byte tables.
  static String get gateUrl => peekGateEndpoint();
  static String get appsflyerKey => peekAppsflyerKey();
  static String get firebaseProject => peekFirebaseProject();

  // Public URLs (never obfuscated).
  static const String privacyUrl = PolicyUrls.privacy;
  static const String supportUrl = PolicyUrls.support;
  static const String homeUrl = PolicyUrls.home;

  // Timing knobs.
  //
  // Cooldown before we re-prompt the notification opt-in after a Skip.
  // 3 days — do not lower without approval, the store guide is strict.
  static const int inviteQuietWindow = 3 * 24 * 60 * 60;

  // Retry delay when AppsFlyer reports af_status == "Organic" on the
  // very first callback (SDK timing false positive).
  static const int organicRetryPause = 5;
}
