/**
 * ==============================================
 * SETTINGS MODULE
 * ==============================================
 * Cài đặt hệ thống: Đổi mật khẩu admin, đổi mã xác thực, theme, bảo mật
 */

import { getAdminPassword, getSecurityCode } from './auth.js';

/**
 * Khởi tạo module Settings
 */
export function initSettings() {
    console.log('⚙️ Khởi tạo module Settings...');

    // Gắn sự kiện các nút
    document.getElementById('btnChangeAdminPassword').addEventListener('click', showChangeAdminPasswordModal);
    document.getElementById('btnChangeSecurityCode').addEventListener('click', showChangeSecurityCodeModal);

    // Theme selector
    const themeSelector = document.getElementById('themeSelector');
    themeSelector.value = localStorage.getItem('theme') || 'light';
    themeSelector.addEventListener('change', changeTheme);

    // Checkbox luôn yêu cầu mã xác thực
    const checkbox = document.getElementById('alwaysRequireSecurity');
    checkbox.checked = localStorage.getItem('alwaysRequireSecurity') === 'true';
    checkbox.addEventListener('change', toggleAlwaysRequireSecurity);

    // Apply theme từ localStorage
    applyTheme();
}

/**
 * Hiển thị modal đổi mật khẩu admin
 */
function showChangeAdminPasswordModal() {
    const modalHTML = `
        <div class="modal show" id="changePasswordModal">
            <div class="modal-content">
                <div class="modal-header">
                    <h3 class="modal-title">🔒 Đổi mật khẩu Admin</h3>
                    <button class="modal-close" id="closeChangePassword">&times;</button>
                </div>
                <div class="modal-body">
                    <form id="changePasswordForm">
                        <div class="form-group">
                            <label>Mã xác thực hiện tại *</label>
                            <input type="password" id="currentSecurityCode" class="form-control" placeholder="Nhập mã xác thực" required>
                        </div>

                        <div class="form-group">
                            <label>Mật khẩu mới *</label>
                            <input type="password" id="newPassword" class="form-control" placeholder="Nhập mật khẩu mới" required>
                        </div>

                        <div class="form-group">
                            <label>Nhập lại mật khẩu mới *</label>
                            <input type="password" id="confirmNewPassword" class="form-control" placeholder="Nhập lại mật khẩu mới" required>
                        </div>

                        <div id="changePasswordError" class="error-message" style="display: none; margin-top: 12px;">
                        </div>
                    </form>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary" id="btnCancelChangePassword">Hủy</button>
                    <button class="btn btn-primary" id="btnSavePassword">💾 Lưu mật khẩu</button>
                </div>
            </div>
        </div>
    `;

    const container = document.getElementById('modalContainer');
    container.innerHTML = modalHTML;

    // Gắn sự kiện
    document.getElementById('closeChangePassword').onclick = () => document.getElementById('changePasswordModal').remove();
    document.getElementById('btnCancelChangePassword').onclick = () => document.getElementById('changePasswordModal').remove();
    document.getElementById('btnSavePassword').onclick = saveNewAdminPassword;
}

/**
 * Lưu mật khẩu admin mới
 */
function saveNewAdminPassword() {
    const securityCode = document.getElementById('currentSecurityCode').value.trim();
    const newPassword = document.getElementById('newPassword').value.trim();
    const confirmPassword = document.getElementById('confirmNewPassword').value.trim();

    const errorDiv = document.getElementById('changePasswordError');

    // Validate
    if (!securityCode || !newPassword || !confirmPassword) {
        errorDiv.textContent = '❌ Vui lòng điền đầy đủ tất cả các trường!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra mã xác thực
    if (securityCode !== getSecurityCode()) {
        errorDiv.textContent = '❌ Mã xác thực không đúng!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra mật khẩu mới trùng nhau
    if (newPassword !== confirmPassword) {
        errorDiv.textContent = '❌ Mật khẩu mới không trùng khớp!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra độ dài mật khẩu
    if (newPassword.length < 4) {
        errorDiv.textContent = '❌ Mật khẩu phải có ít nhất 4 ký tự!';
        errorDiv.style.display = 'block';
        return;
    }

    // Lưu mật khẩu mới vào localStorage
    localStorage.setItem('adminPassword', newPassword);

    // Đóng modal
    document.getElementById('changePasswordModal').remove();

    alert('✅ Đã đổi mật khẩu admin thành công!\n\nVui lòng đăng nhập lại với mật khẩu mới.');

    console.log('✅ Đã đổi mật khẩu admin');
}

/**
 * Hiển thị modal đổi mã xác thực
 */
function showChangeSecurityCodeModal() {
    const modalHTML = `
        <div class="modal show" id="changeSecurityModal">
            <div class="modal-content">
                <div class="modal-header">
                    <h3 class="modal-title">🔐 Đổi mã xác thực</h3>
                    <button class="modal-close" id="closeChangeSecurity">&times;</button>
                </div>
                <div class="modal-body">
                    <form id="changeSecurityForm">
                        <div class="form-group">
                            <label>Mật khẩu admin hiện tại *</label>
                            <input type="password" id="currentAdminPassword" class="form-control" placeholder="Nhập mật khẩu admin" required>
                        </div>

                        <div class="form-group">
                            <label>Mã xác thực mới *</label>
                            <input type="password" id="newSecurityCode" class="form-control" placeholder="Nhập mã xác thực mới" required>
                        </div>

                        <div class="form-group">
                            <label>Nhập lại mã xác thực mới *</label>
                            <input type="password" id="confirmNewSecurityCode" class="form-control" placeholder="Nhập lại mã xác thực mới" required>
                        </div>

                        <div id="changeSecurityError" class="error-message" style="display: none; margin-top: 12px;">
                        </div>
                    </form>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary" id="btnCancelChangeSecurity">Hủy</button>
                    <button class="btn btn-primary" id="btnSaveSecurity">💾 Lưu mã xác thực</button>
                </div>
            </div>
        </div>
    `;

    const container = document.getElementById('modalContainer');
    container.innerHTML = modalHTML;

    // Gắn sự kiện
    document.getElementById('closeChangeSecurity').onclick = () => document.getElementById('changeSecurityModal').remove();
    document.getElementById('btnCancelChangeSecurity').onclick = () => document.getElementById('changeSecurityModal').remove();
    document.getElementById('btnSaveSecurity').onclick = saveNewSecurityCode;
}

/**
 * Lưu mã xác thực mới
 */
function saveNewSecurityCode() {
    const adminPassword = document.getElementById('currentAdminPassword').value.trim();
    const newCode = document.getElementById('newSecurityCode').value.trim();
    const confirmCode = document.getElementById('confirmNewSecurityCode').value.trim();

    const errorDiv = document.getElementById('changeSecurityError');

    // Validate
    if (!adminPassword || !newCode || !confirmCode) {
        errorDiv.textContent = '❌ Vui lòng điền đầy đủ tất cả các trường!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra mật khẩu admin
    if (adminPassword !== getAdminPassword()) {
        errorDiv.textContent = '❌ Mật khẩu admin không đúng!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra mã xác thực mới trùng nhau
    if (newCode !== confirmCode) {
        errorDiv.textContent = '❌ Mã xác thực mới không trùng khớp!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra độ dài mã xác thực
    if (newCode.length < 4) {
        errorDiv.textContent = '❌ Mã xác thực phải có ít nhất 4 ký tự!';
        errorDiv.style.display = 'block';
        return;
    }

    // Lưu mã xác thực mới vào localStorage
    localStorage.setItem('securityCode', newCode);

    // Reset flag xác thực
    sessionStorage.removeItem('securityValidated');

    // Đóng modal
    document.getElementById('changeSecurityModal').remove();

    alert('✅ Đã đổi mã xác thực thành công!');

    console.log('✅ Đã đổi mã xác thực');
}

/**
 * Đổi theme
 */
function changeTheme(event) {
    const theme = event.target.value;
    localStorage.setItem('theme', theme);
    applyTheme();
}

/**
 * Áp dụng theme
 */
function applyTheme() {
    const theme = localStorage.getItem('theme') || 'light';

    if (theme === 'dark') {
        document.body.classList.add('dark-theme');
    } else {
        document.body.classList.remove('dark-theme');
    }

    console.log(`🎨 Áp dụng theme: ${theme}`);
}

/**
 * Bật/tắt luôn yêu cầu mã xác thực
 */
function toggleAlwaysRequireSecurity(event) {
    const isChecked = event.target.checked;
    localStorage.setItem('alwaysRequireSecurity', isChecked.toString());

    if (isChecked) {
        sessionStorage.removeItem('securityValidated');
        console.log('🔒 Bật chế độ luôn yêu cầu mã xác thực');
    } else {
        console.log('🔓 Tắt chế độ luôn yêu cầu mã xác thực');
    }
}

// Export hàm applyTheme để gọi từ main.js
export { applyTheme };
