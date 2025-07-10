import 'package:flutter/material.dart';
import 'package:photogallery/Pages/home.dart';
import 'package:photogallery/backend/media_cache.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Preload media data for instant access
    MediaCache().preloadAllData();

    return MaterialApp(
      title: 'Photo Gallery',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.black,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
          background: Colors.white,
          onBackground: Colors.black,
          inversePrimary: Colors.white,
          inverseSurface: Colors.black,
          onInverseSurface: Colors.white,
          outline: Colors.black,
          outlineVariant: Colors.grey,
          surfaceVariant: Color(0xFFF5F5F5),
          onSurfaceVariant: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          shadowColor: Colors.black12,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          shadowColor: Colors.black12,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey,
          elevation: 8,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.white,
          onSecondary: Colors.black,
          surface: Colors.black,
          onSurface: Colors.white,
          background: Colors.black,
          onBackground: Colors.white,
          inversePrimary: Colors.black,
          inverseSurface: Colors.white,
          onInverseSurface: Colors.black,
          outline: Colors.white,
          outlineVariant: Colors.grey,
          surfaceVariant: Color(0xFF1A1A1A),
          onSurfaceVariant: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 1,
          shadowColor: Colors.white12,
        ),
        cardTheme: const CardThemeData(
          color: Colors.black,
          shadowColor: Colors.white12,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.black,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          elevation: 8,
        ),
      ),
      themeMode: ThemeMode.system, // Follows system theme
      home: const MyHomePage(title: 'Photo Gallery'),
    );
  }
}
