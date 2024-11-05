import 'package:blossomcompanion/pages/main_page.dart';
import 'package:flutter/material.dart';
import 'package:metadata_god/metadata_god.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize metadata handling
  MetadataGod.initialize();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blossom Companion',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.pink,
        scaffoldBackgroundColor: Colors.grey[900],
        colorScheme: ColorScheme.dark(
          primary: Colors.pink,
          secondary: Colors.pinkAccent,
          surface: Colors.grey[850]!,
          onSurface: Colors.white,
        ),
        cardColor: Colors.grey[850],
        chipTheme: ChipThemeData(
          backgroundColor: Colors.grey[800],
          disabledColor: Colors.grey[700],
          selectedColor: Colors.pinkAccent,
          secondarySelectedColor: Colors.pinkAccent,
          labelStyle: const TextStyle(color: Colors.white),
          secondaryLabelStyle: const TextStyle(color: Colors.white),
          brightness: Brightness.dark,
        ),
      ),
      home: const MainPage(),
    );
  }
}
