import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'activation_service.dart';
import 'ui_activation.dart';
import 'ui_shell.dart';
import 'proactive_service.dart';
import 'v39/desktop_icon_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Local notifications are optional; failure must not block the whole app.
    try { await ProactiveNotificationService.initialize(); } catch (_) {}
    final controller = await AppController.create();
    if (controller.data.fontPath.isNotEmpty) {
      try {
        final file = controller.local.resolve(controller.data.fontPath);
        if (await file.exists()) {
          final loader = FontLoader('XinyuCustomFont')..addFont(
            file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
          await loader.load();
        }
      } catch (_) { /* Invalid font: fall back to OS default. */ }
    }
    await DesktopIconScale.initialize();
    final activation = await ActivationService.create();
    runApp(XinyuApp(controller: controller, activation: activation));
  } catch (error) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: SelectableText('应用初始化失败。可能是设备编号、密钥存储或本地数据读取异常，未自动清空数据。\n\n$error',
        textAlign: TextAlign.center),
    )))));
  }
}

class XinyuApp extends StatelessWidget {
  final AppController controller;
  final ActivationService activation;
  const XinyuApp({super.key, required this.controller, required this.activation});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, activation]),
    builder: (context, _) {
      final dark = controller.data.darkMode;
      final themeColor = Color(controller.data.themeColor);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '心屿 OS',
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: themeColor),
          scaffoldBackgroundColor: const Color(0xFFF9F7FB),
          fontFamily: controller.data.fontPath.isNotEmpty ? 'XinyuCustomFont' : null,
          appBarTheme: const AppBarTheme(centerTitle: true)),
        darkTheme: ThemeData(useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: themeColor,
            brightness: Brightness.dark),
          fontFamily: controller.data.fontPath.isNotEmpty ? 'XinyuCustomFont' : null,
          appBarTheme: const AppBarTheme(centerTitle: true)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(controller.data.fontScale)),
          child: child ?? const SizedBox.shrink()),
        home: activation.isActivated
          ? PhoneHomeScreen(controller: controller)
          : ActivationScreen(activation: activation),
      );
    },
  );
}
