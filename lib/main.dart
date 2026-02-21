import 'package:flutter/material.dart';
import 'welcome_page.dart';
import 'ocr_page.dart';
import 'about_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amharic OCR',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: _themeMode,
      home: WelcomePage(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ), // Set WelcomePage as initial screen
      routes: {
        '/ocr':
            (context) => OCRPage(
              themeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
            ),
        '/about': (context) => const AboutPage(), // Define named route
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
