/// Which experience the shell has permanently locked onto for this
/// install. `undecided` is the only state on which the shell may retry
/// the config request; the other two are terminal.
enum PathChoice {
  streamed, // WebView (paid attribution)
  local,    // Native game (organic / gate refusal)
  undecided;

  static PathChoice restore(String? raw) {
    switch (raw) {
      case 'streamed':
        return PathChoice.streamed;
      case 'local':
        return PathChoice.local;
      default:
        return PathChoice.undecided;
    }
  }

  String tag() => name;
}
