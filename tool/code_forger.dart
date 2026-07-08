// ignore_for_file: avoid_print
// ============================================================
// CODE FORGER — plaintext → CipherRing byte arrays
// ============================================================
// Mirrors lib/stealth/cipher_ring.dart bit-for-bit. Run with:
//   dart run tool/code_forger.dart
//
// The printed const arrays go into lib/setup/veiled_bytes.dart.
// Any change to `_charm` / `_bandLen` in the runtime obfuscator must
// be reflected here, or the encoded bytes decode to garbage.
// ============================================================

const String _charm = 'em8Rr_Dr1FT#volc4';
const int _bandLen = 27;

List<int> _brewBand() {
  int hi = 0xC6BC279692B5C323;
  int lo = 0x9E6C63D0676A9A99;
  for (final int c in _charm.codeUnits) {
    hi ^= c;
    hi = (hi * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF;
    lo = _rotL64(lo, 13) ^ (hi & 0x00FFFFFFFF);
    lo = (lo + 0xAF63BD4C8601B7BF) & 0xFFFFFFFFFFFFFFFF;
  }

  int a = ((hi ^ lo) & 0xFFFFFFFF);
  if (a == 0) a = 0xA5D3C7F1;
  int carry = (((hi >> 32) ^ (lo >> 24)) & 0xFFFFFFFF);
  if (carry == 0) carry = 0x3F1A2B4C;

  final List<int> band = List<int>.filled(_bandLen, 0);
  for (int i = 0; i < _bandLen; i++) {
    final int product = a * 0xFFFEB81B + carry;
    a = product & 0xFFFFFFFF;
    carry = (product >> 32) & 0xFFFFFFFF;
    band[i] = ((a >> 8) ^ (carry >> 4)) & 0xFF;
  }
  return band;
}

int _rotL64(int value, int shift) {
  final int s = shift & 63;
  return ((value << s) | (value >> (64 - s))) & 0xFFFFFFFFFFFFFFFF;
}

int _positionalMask(int index) {
  final int raw = (index * 0x9F) & 0xFF;
  return ((raw << 3) | (raw >> 5)) & 0xFF;
}

final List<int> _band = _brewBand();

List<int> _shroud(String plain) {
  final List<int> bytes = plain.codeUnits;
  final List<int> out = List<int>.filled(bytes.length, 0);
  for (int i = 0; i < bytes.length; i++) {
    out[i] = (bytes[i] ^ _band[i % _bandLen] ^ _positionalMask(i)) & 0xFF;
  }
  return out;
}

void _emit(String label, String plain) {
  if (plain.isEmpty) {
    print('// $label — leave empty until manager provides value');
    print('const <int>[];\n');
    return;
  }
  final List<int> packed = _shroud(plain);
  print('// $label <= "$plain"');
  print('const <int>[${packed.join(', ')}],\n');
}

void main() {
  // -----------------------------------------------------------------
  // Fill in the plaintext values below, then run:
  //   dart run tool/code_forger.dart
  // Paste the printed arrays into lib/setup/veiled_bytes.dart.
  //
  // NEVER commit real plaintext values to source control. This file
  // is a working scratchpad — clear the strings before pushing.
  // -----------------------------------------------------------------
  const String gateEndpoint = 'https://emberdrrift.com/config.php';
  const String gcdBase = 'https://gcdsdk.appsflyer.com/install_data/v4.0/';
  const String chromeMajor = '149.0.7636.72';
  const String webkitMajor = '537.36';
  const String appsflyerKey = ''; // fill in when re-packing
  const String firebaseProject = ''; // fill in when re-packing

  print('=== Ember Drift code_forger ===\n');
  _emit('gateEndpoint', gateEndpoint);
  _emit('gcdBase', gcdBase);
  _emit('chromeMajor', chromeMajor);
  _emit('webkitMajor', webkitMajor);
  _emit('appsflyerKey', appsflyerKey);
  _emit('firebaseProject', firebaseProject);
}
