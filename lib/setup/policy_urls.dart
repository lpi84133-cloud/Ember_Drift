// ============================================================
// PolicyUrls — public, non-sensitive URLs shipped as plaintext
// ============================================================
// These URLs appear inside the native game menu (Privacy Policy /
// Support buttons) and are read by the store reviewer. Encoding them
// would look suspicious, so they stay plaintext here and are the ONLY
// legitimate string literals for this project's canonical domain.
// ============================================================

class PolicyUrls {
  PolicyUrls._();

  static const String home = 'https://emberdrrift.com';
  static const String privacy = 'https://emberdrrift.com/privacy-policy.html';
  static const String support = 'https://emberdrrift.com/support.html';
}
