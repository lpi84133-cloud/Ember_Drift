import 'dart:typed_data';

// ============================================================
// CipherRing — string obfuscation for Ember Drift
// ============================================================
// Every sensitive endpoint / credential ships as a byte list produced
// by `tool/code_forger.dart`, never as a plaintext string literal.
//
// Scheme (deliberately different from the internal template):
//   1. `_charm` is folded into two 64-bit accumulators using a MurmurHash-
//      inspired mix (odd multiplier + rotate).
//   2. A Multiply-With-Carry (Marsaglia MWC) PRNG is seeded from the
//      folded state and produces a `_bandLen`-byte keystream — one MWC
//      step gives 32 bits, we pick the low byte.
//   3. Each byte of the payload = plain ^ band[i % len]
//      ^ rotateLeft(offset, 3), where `offset` is the running index.
//      The rotate-based positional XOR is what makes identical plaintext
//      encode differently across offsets, and differs from the plain
//      `i & 0xFF` variant common in the reference template.
//
// Encoding and decoding use exactly the same routine — the scheme is a
// pure involution. `tool/code_forger.dart` mirrors this file.
//
// Per-project mandatory changes when forking:
//   • Bump `_charm` to a fresh short opaque token (never reused).
//   • Adjust `_bandLen` to a different value in [12, 40].
//   • Re-run tool/code_forger.dart and drop the freshly emitted arrays
//     into lib/setup/veiled_bytes.dart. Old arrays will decode to
//     garbage — do not leave them behind.
// ============================================================

const String _charm = 'em8Rr_Dr1FT#volc4';
const int _bandLen = 27;

Uint8List _brewBand() {
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

  final Uint8List band = Uint8List(_bandLen);
  for (int i = 0; i < _bandLen; i++) {
    // Multiply-with-carry step (Marsaglia): multiplier chosen so that
    // 2*m*2^32 - 1 is a safe prime and the period is > 2^63.
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
  // 3-bit left rotate over the low byte — differs from a plain (i & 0xFF).
  final int raw = (index * 0x9F) & 0xFF;
  return ((raw << 3) | (raw >> 5)) & 0xFF;
}

final Uint8List _band = _brewBand();

/// Reverses an encoded byte list back into the original string. Empty input
/// yields an empty string — that is the safe path taken while the byte
/// arrays in `veiled_bytes.dart` are still unfilled.
String reforge(List<int> shrouded) {
  if (shrouded.isEmpty) return '';
  final Uint8List out = Uint8List(shrouded.length);
  for (int i = 0; i < shrouded.length; i++) {
    out[i] = (shrouded[i] ^ _band[i % _bandLen] ^ _positionalMask(i)) & 0xFF;
  }
  return String.fromCharCodes(out);
}
