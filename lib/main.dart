import 'package:boom_board/core/di/core_injector.dart';
import 'package:boom_board/routes/app_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await registerDependencies();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Boom Board',
      initialRoute: home,
      getPages: getRoutes(),
      theme: ThemeData(
        fontFamily: 'PressStart2P',
      ),
    );
  }
}
