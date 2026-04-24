import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const InstaGrabApp());
}

/// Root application widget for InstaGrab.
///
/// Provides a dark Material 3 theme optimized for image editing workflows.
class InstaGrabApp extends StatelessWidget {
  const InstaGrabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstaGrab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
