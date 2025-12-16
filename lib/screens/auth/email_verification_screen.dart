import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/theme.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isResending = false;
  Timer? _checkTimer;
  int _countdown = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _sendVerificationEmail();
    _startCountdown();
    _startCheckingVerification();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  void _startCheckingVerification() {
    // Kiểm tra email verification mỗi 3 giây
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final authService = Provider.of<AuthService>(context, listen: false);
      final isVerified = await authService.checkEmailVerified();

      if (isVerified && mounted) {
        timer.cancel();
        _showSuccessAndNavigate();
      }
    });
  }

  void _showSuccessAndNavigate() async {
    // Đăng xuất người dùng trước khi chuyển về login
    final authService = Provider.of<AuthService>(context, listen: false);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.successColor, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Đăng ký thành công!')),
          ],
        ),
        content: const Text(
          'Email của bạn đã được xác thực thành công!\n\n'
          'Bây giờ bạn có thể đăng nhập để sử dụng ứng dụng.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.successColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Đăng xuất và chuyển về màn hình login
    await authService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _sendVerificationEmail() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.sendEmailVerification();
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isResending = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final success = await authService.sendEmailVerification();

    if (!mounted) return;

    setState(() {
      _isResending = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi lại email xác thực'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      // Reset countdown
      setState(() {
        _countdown = 60;
        _canResend = false;
      });
      _startCountdown();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.errorMessage ?? 'Lỗi gửi email'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _manualCheck() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isVerified = await authService.checkEmailVerified();

    if (!mounted) return;

    if (isVerified) {
      _showSuccessAndNavigate();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email chưa được xác thực. Vui lòng kiểm tra hộp thư của bạn.'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác thực email'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),

            // Icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread,
                size: 60,
                color: AppTheme.primaryColor,
              ),
            ),

            const SizedBox(height: 32),

            // Title
            const Text(
              'Xác thực email của bạn',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Description
            Text(
              'Chúng tôi đã gửi email xác thực đến:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              authService.currentUser?.email ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Warning box - Quan trọng
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[300]!, width: 2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange[800], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LƯU Ý QUAN TRỌNG',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[900],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vui lòng mở email và nhấn vào liên kết xác thực NGAY BÂY GIỜ.\n\n'
                          'Nếu không thấy email, hãy kiểm tra thư mục SPAM/Thư rác.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[900],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info box - Hướng dẫn
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Hướng dẫn chi tiết',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '1. Mở ứng dụng email trên điện thoại/máy tính\n'
                    '2. Tìm email từ "noreply@..." (Firebase)\n'
                    '3. Nếu không thấy ở hộp thư đến → Kiểm tra thư rác\n'
                    '4. Mở email và nhấn vào nút "Verify Email"\n'
                    '5. Sau khi xác thực → Quay lại app này',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[900],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Auto-checking indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green[700]!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Đang tự động kiểm tra xác thực...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Manual check button
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _manualCheck,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'Kiểm tra ngay',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Resend button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: (_canResend && !_isResending) ? _resendEmail : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                icon: _isResending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.email),
                label: Text(
                  _isResending
                      ? 'Đang gửi...'
                      : (_canResend
                          ? 'Gửi lại email'
                          : 'Gửi lại sau $_countdown giây'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Skip for now (logout)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Đăng xuất'),
                    content: const Text(
                      'Bạn cần xác thực email để sử dụng ứng dụng.\n\n'
                      'Bạn có chắc muốn đăng xuất?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Hủy'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Đăng xuất'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  await authService.logout();

                  if (!mounted) return;

                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              child: const Text(
                'Đăng xuất',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
