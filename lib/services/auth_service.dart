import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;

  // Kiểm tra trạng thái đăng nhập
  Future<bool> checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid');
    
    if (uid != null) {
      try {
        final snapshot = await _db.child('users/$uid').get();
        if (snapshot.exists) {
          _currentUser = UserModel.fromJson(Map<String, dynamic>.from(snapshot.value as Map));
          notifyListeners();
          return true;
        }
      } catch (e) {
        print('Error checking login: $e');
      }
    }
    
    return false;
  }

  // Đăng ký
Future<bool> register({
  required String email,
  required String password,
  required String displayName,
}) async {
  try {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    print('=== BAT DAU DANG KY ===');
    print('Email: $email');
    print('Display Name: $displayName');

    // Tạo user trong Firebase Auth
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    print('✓ Firebase Auth thanh cong');

    if (userCredential.user != null) {
      final uid = userCredential.user!.uid;
      print('✓ UID: $uid');
      
      // Tạo user model
      final user = UserModel(
        uid: uid,
        email: email,
        displayName: displayName,
        createdAt: DateTime.now(),
      );

      print('Dang luu vao Database...');
      print('Path: users/$uid');

      // Lưu vào Realtime Database - SỬA CÁCH CONVERT
      try {
        final userJson = user.toJson();
        print('Data: $userJson');
        
        await _db.child('users/$uid').set(userJson);
        print('✓ Da luu vao Database');
      } catch (e) {
        print('✗ Loi luu Database: $e');
        print('Stack trace: ${StackTrace.current}');
        
        // Thử lại bằng cách khác
        try {
          await _db.child('users/$uid/uid').set(uid);
          await _db.child('users/$uid/email').set(email);
          await _db.child('users/$uid/displayName').set(displayName);
          await _db.child('users/$uid/createdAt').set(DateTime.now().toIso8601String());
          print('✓ Da luu vao Database (cach 2)');
        } catch (e2) {
          print('✗ Loi luu Database lan 2: $e2');
          throw Exception('Loi luu Database: $e2');
        }
      }

      // Lưu vào SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', uid);
      print('✓ Da luu SharedPreferences');

      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      
      print('=== DANG KY THANH CONG ===');
      return true;
    }

    print('✗ UserCredential.user = null');
    _isLoading = false;
    notifyListeners();
    return false;
    
  } on FirebaseAuthException catch (e) {
    _isLoading = false;
    
    print('✗ Firebase Auth Exception: ${e.code}');
    print('Message: ${e.message}');
    
    switch (e.code) {
      case 'weak-password':
        _errorMessage = 'Mat khau qua yeu (toi thieu 6 ky tu)';
        break;
      case 'email-already-in-use':
        _errorMessage = 'Email da duoc su dung';
        break;
      case 'invalid-email':
        _errorMessage = 'Email khong hop le';
        break;
      default:
        _errorMessage = 'Loi: ${e.message}';
    }
    
    notifyListeners();
    return false;
  } catch (e, stackTrace) {
    _isLoading = false;
    _errorMessage = 'Loi khong xac dinh: $e';
    print('✗ Exception: $e');
    print('Stack trace: $stackTrace');
    notifyListeners();
    return false;
  }
}

  // Đăng nhập
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Đăng nhập Firebase Auth
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        final user = userCredential.user!;
        final uid = user.uid;

        // ===== KIỂM TRA EMAIL ĐÃ ĐƯỢC XÁC THỰC CHƯA =====
        print('>>> Checking email verification for uid: $uid');
        await user.reload(); // Reload để lấy trạng thái mới nhất
        final refreshedUser = _auth.currentUser;

        if (refreshedUser != null && !refreshedUser.emailVerified) {
          // Email chưa được xác thực → Đăng xuất và báo lỗi
          print('>>> Email not verified, logging out');
          await _auth.signOut();
          _isLoading = false;
          _errorMessage = 'Email chưa được xác thực.\n\nVui lòng kiểm tra hộp thư và xác thực email trước khi đăng nhập.';
          notifyListeners();
          return false;
        }

        print('>>> Email verified, loading user data from database');
        print('>>> Auth state: ${_auth.currentUser != null}');

        // Lấy thông tin user từ database
        print('>>> Attempting to read: users/$uid');
        final snapshot = await _db.child('users/$uid').get();
        print('>>> Successfully read database');

        if (snapshot.exists) {
          _currentUser = UserModel.fromJson(
            Map<String, dynamic>.from(snapshot.value as Map)
          );

          // Lưu vào SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('uid', uid);

          _isLoading = false;
          notifyListeners();

          return true;
        }
      }

      _isLoading = false;
      notifyListeners();
      return false;

    } on FirebaseAuthException catch (e) {
      _isLoading = false;

      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          _errorMessage = 'Email hoặc mật khẩu không đúng';
          break;
        case 'invalid-email':
          _errorMessage = 'Email không hợp lệ';
          break;
        case 'user-disabled':
          _errorMessage = 'Tài khoản đã bị vô hiệu hóa';
          break;
        case 'too-many-requests':
          _errorMessage = 'Quá nhiều lần thử. Vui lòng thử lại sau';
          break;
        case 'network-request-failed':
          _errorMessage = 'Lỗi kết nối mạng. Vui lòng kiểm tra internet';
          break;
        default:
          _errorMessage = 'Đăng nhập thất bại. Vui lòng thử lại';
      }

      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;

      // Kiểm tra xem có phải lỗi permission không
      if (e.toString().contains('permission-denied')) {
        _errorMessage = 'Lỗi hệ thống. Vui lòng liên hệ quản trị viên';
      } else {
        _errorMessage = 'Đăng nhập thất bại. Vui lòng thử lại';
      }

      print('Login error: $e'); // Log để dev debug
      notifyListeners();
      return false;
    }
  }

  // Đăng xuất
  Future<void> logout() async {
    await _auth.signOut();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');

    _currentUser = null;
    notifyListeners();
  }

  // Đổi mật khẩu
  Future<void> changePassword(String currentPassword, String newPassword) async {
    try {
      final user = _auth.currentUser;

      if (user == null || user.email == null) {
        throw Exception('Không tìm thấy người dùng');
      }

      // Re-authenticate người dùng với mật khẩu hiện tại
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Đổi mật khẩu
      await user.updatePassword(newPassword);

    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
          throw Exception('Mật khẩu hiện tại không đúng');
        case 'weak-password':
          throw Exception('Mật khẩu mới quá yếu (tối thiểu 6 ký tự)');
        case 'requires-recent-login':
          throw Exception('Vui lòng đăng nhập lại để đổi mật khẩu');
        default:
          throw Exception('Lỗi: ${e.message}');
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // Gửi email reset password
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _auth.sendPasswordResetEmail(email: email);

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;

      switch (e.code) {
        case 'user-not-found':
          _errorMessage = 'Không tìm thấy tài khoản với email này';
          break;
        case 'invalid-email':
          _errorMessage = 'Email không hợp lệ';
          break;
        default:
          _errorMessage = 'Lỗi: ${e.message}';
      }

      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Lỗi không xác định: $e';
      notifyListeners();
      return false;
    }
  }

  // Gửi email xác thực
  Future<bool> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        _errorMessage = 'Không tìm thấy người dùng';
        notifyListeners();
        return false;
      }

      if (user.emailVerified) {
        _errorMessage = 'Email đã được xác thực';
        notifyListeners();
        return false;
      }

      await user.sendEmailVerification();
      return true;
    } catch (e) {
      _errorMessage = 'Lỗi gửi email xác thực: $e';
      notifyListeners();
      return false;
    }
  }

  // Kiểm tra email đã được xác thực chưa
  Future<bool> checkEmailVerified() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        return false;
      }

      // Reload user để lấy trạng thái mới nhất
      await user.reload();
      final refreshedUser = _auth.currentUser;

      return refreshedUser?.emailVerified ?? false;
    } catch (e) {
      print('Lỗi kiểm tra email verification: $e');
      return false;
    }
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}