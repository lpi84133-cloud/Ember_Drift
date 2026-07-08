// Smoke test: import surface compiles.
//
// A full widget pump requires a running Flutter engine with platform
// channels for Firebase / SharedPreferences / secure storage, which the
// test host does not provide. So we only assert that the entry-point
// symbols exist — the CI signal is "the app compiles" rather than "the
// app boots inside pure Dart".
import 'package:flutter_test/flutter_test.dart';

import 'package:emberdrift/main.dart' as ed;
import 'package:emberdrift/setup/mission_facade.dart';

void main() {
  test('shell entrypoint compiles and identity is set', () {
    expect(MissionFacade.displayTitle, 'Ember Drift');
    expect(MissionFacade.packageId, 'com.volcano.emberdrift');
    // Reference the entrypoint symbol so it stays wired into the build.
    expect(ed.main, isNotNull);
  });
}
