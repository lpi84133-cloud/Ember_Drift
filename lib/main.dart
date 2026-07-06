import 'package:flutter/material.dart';

import 'core/app_colors.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmberDriftApp());
}

class EmberDriftApp extends StatefulWidget {
  const EmberDriftApp({super.key});

  @override
  State<EmberDriftApp> createState() => _EmberDriftAppState();
}

class _EmberDriftAppState extends State<EmberDriftApp> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ember Drift',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.obsidianDark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.emberOrange,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
      ),
      home: _ready
          ? const HomeScreen()
          : LoadingScreen(onComplete: () => setState(() => _ready = true)),
    );
  }
}
