/// Parsed answer from the gate endpoint. Wire keys `ok / url / expires /
/// message` are mapped verbatim so the backend contract stays intact.
class ShellVerdict {
  const ShellVerdict({
    required this.approved,
    this.destination,
    this.note,
    this.expiresAtSeconds,
  });

  /// Backend `ok` — true means "route the user to [destination]".
  final bool approved;

  /// Backend `url` — content to load into the WebView.
  final String? destination;

  /// Backend `message` — diagnostic note (e.g. "organic", "no data").
  final String? note;

  /// Backend `expires` — Unix seconds after which [destination] should
  /// be refreshed. Null means "no ttl provided".
  final int? expiresAtSeconds;

  factory ShellVerdict.parse(Map<String, dynamic> raw) {
    return ShellVerdict(
      approved: raw['ok'] as bool? ?? false,
      destination: raw['url'] as String?,
      note: raw['message'] as String?,
      expiresAtSeconds: raw['expires'] as int?,
    );
  }

  factory ShellVerdict.refused(String note) =>
      ShellVerdict(approved: false, note: note);

  bool get hasDestination =>
      destination != null && destination!.isNotEmpty;
}
