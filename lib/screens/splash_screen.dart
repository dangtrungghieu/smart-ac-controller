import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';
import 'home/device_list_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      
      if (!mounted) return;
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final isLoggedIn = await authService.checkLoginStatus();
      
      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isLoggedIn 
              ? const DeviceListScreen() 
              : const LoginScreen(),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Loi khoi dong: $e';
      });
      
      // Sau 3 giây vẫn chuyển sang Login
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.ac_unit,
                  size: 60,
                  color: Color(0xFF667EEA),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Title
              const Text(
                'AC Control',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Subtitle
              const Text(
                'Smart Air Conditioner Control',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Loading or Error
              if (_errorMessage.isEmpty)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}