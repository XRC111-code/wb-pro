import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';

class WbApp extends StatefulWidget {
  const WbApp({super.key});

  @override
  State<WbApp> createState() => _WbAppState();
}

class _WbAppState extends State<WbApp> {
  ThemeMode _mode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wb-pro',
      debugShowCheckedModeBanner: false,
      theme: WbTheme.light(),
      darkTheme: WbTheme.dark(),
      themeMode: _mode,
      home: HomePage(onToggleTheme: _toggleTheme),
    );
  }
}
