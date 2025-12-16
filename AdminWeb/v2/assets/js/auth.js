/**
 * ==============================================
 * AUTHENTICATION MODULE
 * ==============================================
 * Xử lý đăng nhập, đăng xuất, và quản lý phiên làm việc
 */

/**
 * Lấy mật khẩu admin từ localStorage (hoặc mặc định "admin")
 */
function getAdminPassword() {
    return localStorage.getItem('adminPassword') || 'admin';
}

/**
 * Lấy mã xác thực từ localStorage (hoặc mặc định "123456")
 */
function getSecurityCode() {
    return localStorage.getItem('securityCode') || '123456';
}

/**
 * Kiểm tra trạng thái đăng nhập
 * @returns {boolean} - true nếu đã đăng nhập
 */
function isLoggedIn() {
    return localStorage.getItem('adminLoggedIn') === 'true';
}

/**
 * Đăng nhập
 * @param {string} username - Tên đăng nhập
 * @param {string} password - Mật khẩu
 * @returns {boolean} - true nếu đăng nhập thành công
 */
function login(username, password) {
    const correctUsername = 'admin';
    const correctPassword = getAdminPassword();

    if (username === correctUsername && password === correctPassword) {
        // Lưu trạng thái đăng nhập
        localStorage.setItem('adminLoggedIn', 'true');

        // Reset flag xác thực bảo mật (yêu cầu xác thực lại mỗi phiên mới)
        sessionStorage.removeItem('securityValidated');

        console.log('✅ Đăng nhập thành công');
        return true;
    } else {
        console.log('❌ Đăng nhập thất bại: Sai username hoặc password');
        return false;
    }
}

/**
 * Đăng xuất với xác nhận
 */
function logout() {
    const modalHTML = `
        <div class="modal show" id="logoutConfirmModal">
            <div class="modal-content">
                <div class="modal-header">
                    <h3 class="modal-title">🚪 Xác nhận đăng xuất</h3>
                    <button class="modal-close" id="closeLogoutConfirm">&times;</button>
                </div>
                <div class="modal-body">
                    <p style="font-size: 16px; margin: 20px 0;">Bạn có chắc chắn muốn đăng xuất khỏi hệ thống?</p>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary" id="btnCancelLogout">Hủy</button>
                    <button class="btn-logout" id="btnConfirmLogout">Đăng xuất</button>
                </div>
            </div>
        </div>
    `;

    const container = document.getElementById('modalContainer');
    container.innerHTML = modalHTML;

    document.getElementById('closeLogoutConfirm').onclick = () => {
        document.getElementById('logoutConfirmModal').remove();
    };

    document.getElementById('btnCancelLogout').onclick = () => {
        document.getElementById('logoutConfirmModal').remove();
    };

    document.getElementById('btnConfirmLogout').onclick = () => {
        localStorage.removeItem('adminLoggedIn');
        sessionStorage.removeItem('securityValidated');
        console.log('👋 Đã đăng xuất');

        // Reload trang để về login
        window.location.reload();
    };
}

/**
 * Xác thực mã bảo mật
 * @param {string} inputCode - Mã xác thực nhập vào
 * @returns {boolean} - true nếu mã đúng
 */
function validateSecurityCode(inputCode) {
    const correctCode = getSecurityCode();

    if (inputCode === correctCode) {
        // Đánh dấu đã xác thực trong phiên hiện tại
        const alwaysRequire = localStorage.getItem('alwaysRequireSecurity') === 'true';

        if (!alwaysRequire) {
            sessionStorage.setItem('securityValidated', 'true');
        }

        console.log('✅ Mã xác thực đúng');
        return true;
    } else {
        console.log('❌ Mã xác thực sai');
        return false;
    }
}

/**
 * Kiểm tra xem đã xác thực bảo mật trong phiên chưa
 * @returns {boolean}
 */
function isSecurityValidated() {
    const alwaysRequire = localStorage.getItem('alwaysRequireSecurity') === 'true';

    // Nếu bật "luôn yêu cầu" thì luôn trả về false
    if (alwaysRequire) {
        return false;
    }

    // Nếu không, kiểm tra session
    return sessionStorage.getItem('securityValidated') === 'true';
}

/**
 * Hiển thị popup yêu cầu mã xác thực
 * @param {Function} onSuccess - Callback khi xác thực thành công
 */
function showSecurityPrompt(onSuccess) {
    // Nếu đã xác thực trong phiên, gọi luôn callback
    if (isSecurityValidated()) {
        onSuccess();
        return;
    }

    // Tạo modal HTML
    const modalHTML = `
        <div class="modal show" id="securityModal">
            <div class="modal-content">
                <div class="modal-header">
                    <h3 class="modal-title">🔐 Xác thực bảo mật</h3>
                </div>
                <div class="modal-body">
                    <p style="margin-bottom: 20px; color: var(--text-secondary);">
                        Thao tác này yêu cầu xác thực bảo mật. Vui lòng nhập mã xác thực.
                    </p>
                    <div class="form-group">
                        <label>Mã xác thực:</label>
                        <input type="password" id="securityCodeInput" class="form-control" placeholder="Nhập mã xác thực">
                    </div>
                    <div id="securityError" class="error-message" style="display: none; margin-top: 12px;">
                        ❌ Mã xác thực không đúng!
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary" id="btnCancelSecurity">Hủy</button>
                    <button class="btn btn-primary" id="btnConfirmSecurity">Xác nhận</button>
                </div>
            </div>
        </div>
    `;

    // Thêm vào container
    const container = document.getElementById('modalContainer');
    container.innerHTML = modalHTML;

    const modal = document.getElementById('securityModal');
    const input = document.getElementById('securityCodeInput');
    const errorDiv = document.getElementById('securityError');

    // Focus vào input
    setTimeout(() => input.focus(), 100);

    // Xử lý nút Hủy
    document.getElementById('btnCancelSecurity').onclick = () => {
        modal.remove();
    };

    // Xử lý nút Xác nhận
    document.getElementById('btnConfirmSecurity').onclick = () => {
        const code = input.value.trim();

        if (validateSecurityCode(code)) {
            modal.remove();
            onSuccess();
        } else {
            errorDiv.style.display = 'block';
            input.value = '';
            input.focus();
        }
    };

    // Cho phép Enter để submit
    input.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            document.getElementById('btnConfirmSecurity').click();
        }
    });
}

// Export các hàm
export {
    login,
    logout,
    isLoggedIn,
    getAdminPassword,
    getSecurityCode,
    validateSecurityCode,
    isSecurityValidated,
    showSecurityPrompt
};
