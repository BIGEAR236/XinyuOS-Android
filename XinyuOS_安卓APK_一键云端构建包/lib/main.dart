import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'activation_service.dart';
import 'ui_activation.dart';
import 'ui_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = await AppController.create();
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
          appBarTheme: const AppBarTheme(centerTitle: true)),
        darkTheme: ThemeData(useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: themeColor,
            brightness: Brightness.dark),
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
