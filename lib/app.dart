import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

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
      // 放在 builder 里而不是包在 MaterialApp 外面：themeMode 解析成实际
      // 亮度这一步发生在 MaterialApp 内部，外面拿不到当前是深色还是浅色。
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        return MiuixTheme(
          data: WbTheme.miuixThemeData(brightness),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: WbTheme.fontFamily),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: HomePage(onToggleTheme: _toggleTheme),
    );
  }
}
