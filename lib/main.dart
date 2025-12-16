import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/device_service.dart';
import 'services/schedule_service.dart';
import 'services/schedule_executor.dart';
import 'services/auto_off_service.dart';
import 'screens/splash_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Khởi tạo Firebase - KHÔNG CẦN OPTIONS
  await Firebase.initializeApp();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => DeviceService()),
        ChangeNotifierProvider(create: (_) => ScheduleService()),
        Provider(
          create: (_) {
            final executor = ScheduleExecutor();
            executor.startScheduleChecker(); // Bắt đầu kiểm tra lịch
            return executor;
          },
          dispose: (_, executor) => executor.dispose(),
        ),
        Provider(
          create: (_) {
            final autoOffService = AutoOffService();
            autoOffService.startAutoOffMonitor(); // Bắt đầu auto-off monitor
            return autoOffService;
          },
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'AC Control',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}