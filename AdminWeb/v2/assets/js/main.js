/**
 * ==============================================
 * MAIN MODULE
 * ==============================================
 * Điều hướng, khởi tạo, quản lý trạng thái chung
 */

import { initializeFirebase } from './firebase.js';
import { login, logout, isLoggedIn } from './auth.js';
import { initDevices, renderDeviceTable, updateDeviceStats, initDeviceFilters } from './devices_final.js';
import { initUsers, renderUserTable, initUserFilters } from './users.js';
import { initLibraries, renderLibraryTable, initLibraryFilters } from './libraries.js';
import { initSettings, applyTheme } from './settings.js';

/**
 * Hàm khởi tạo ứng dụng
 */
async function initApp() {
    console.log('🚀 Khởi tạo ứng dụng Smart AC Admin...');

    // Áp dụng theme từ localStorage
    applyTheme();

    // Khởi tạo Firebase
    await initializeFirebase();

    // Kiểm tra trạng thái đăng nhập
    if (isLoggedIn()) {
        // Đã đăng nhập -> hiển thị dashboard
        showDashboard();
    } else {
        // Chưa đăng nhập -> hiển thị màn hình login
        showLogin();
    }

    // Gắn sự kiện form đăng nhập
    const loginForm = document.getElementById('loginForm');
    if (loginForm) {
        loginForm.addEventListener('submit', handleLogin);
    }

    // Gắn sự kiện nút đăng xuất
    const logoutBtn = document.getElementById('logoutBtn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', handleLogout);
    }

    // Gắn sự kiện avatar dropdown
    initAvatarDropdown();

    // Gắn sự kiện sidebar navigation
    initNavigation();
}

/**
 * Khởi tạo avatar dropdown menu
 */
function initAvatarDropdown() {
    const avatar = document.getElementById('adminAvatar');
    const dropdown = document.getElementById('adminDropdown');

    if (!avatar || !dropdown) return;

    // Toggle dropdown khi click avatar
    avatar.addEventListener('click', (e) => {
        e.stopPropagation();
        dropdown.classList.toggle('show');
    });

    // Đóng dropdown khi click bên ngoài
    document.addEventListener('click', (e) => {
        if (!avatar.contains(e.target) && !dropdown.contains(e.target)) {
            dropdown.classList.remove('show');
        }
    });

    // Gắn sự kiện cho các nút trong dropdown
    const btnChangePassword = document.getElementById('btnChangePasswordFromDropdown');
    const btnChangeSecurityCode = document.getElementById('btnChangeSecurityCodeFromDropdown');

    if (btnChangePassword) {
        btnChangePassword.addEventListener('click', () => {
            dropdown.classList.remove('show');
            document.getElementById('btnChangeAdminPassword')?.click();
        });
    }

    if (btnChangeSecurityCode) {
        btnChangeSecurityCode.addEventListener('click', () => {
            dropdown.classList.remove('show');
            document.getElementById('btnChangeSecurityCode')?.click();
        });
    }
}

/**
 * Hiển thị màn hình đăng nhập
 */
function showLogin() {
    document.getElementById('loginPage').style.display = 'flex';
    document.getElementById('adminDashboard').style.display = 'none';
}

/**
 * Hiển thị dashboard
 */
async function showDashboard() {
    document.getElementById('loginPage').style.display = 'none';
    document.getElementById('adminDashboard').style.display = 'flex';

    // Khởi tạo các module
    await initDevices();
    await initUsers();
    await initLibraries();
    initSettings();

    // Khởi tạo filters
    initDeviceFilters();
    initUserFilters();
    initLibraryFilters();

    // Hiển thị tab đầu tiên (Dashboard)
    showSection('dashboard');

    // Cập nhật thống kê
    updateDeviceStats();
    updateDashboardStats();

    // Bắt đầu đồng hồ thời gian thực
    startRealtimeClock();
}

/**
 * Cập nhật thống kê dashboard
 */
function updateDashboardStats() {
    // Đếm users và libraries (sẽ được update từ các module)
    setTimeout(() => {
        updateUserStats();
        updateLibraryStats();
    }, 500);
}

/**
 * Cập nhật số liệu users
 */
window.updateUserStats = function() {
    // Sẽ được gọi từ users.js
    const userCount = document.querySelectorAll('#usersTableBody tr').length;
    const statElem = document.getElementById('statTotalUsers');
    if (statElem && userCount > 0) {
        statElem.textContent = userCount;
    }
};

/**
 * Cập nhật số liệu libraries
 */
window.updateLibraryStats = function() {
    // Sẽ được gọi từ libraries.js
    const libCount = document.querySelectorAll('#librariesTableBody tr').length;
    const statElem = document.getElementById('statLibraries');
    if (statElem && libCount > 0) {
        statElem.textContent = libCount;
    }
};

/**
 * Đồng hồ thời gian thực
 */
function startRealtimeClock() {
    function updateClock() {
        const now = new Date();
        const timeString = now.toLocaleTimeString('vi-VN');
        const clockElem = document.getElementById('serverTime');
        if (clockElem) {
            clockElem.textContent = timeString;
        }
    }

    updateClock();
    setInterval(updateClock, 1000);
}

/**
 * Xử lý đăng nhập
 */
function handleLogin(event) {
    event.preventDefault();

    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value.trim();
    const errorDiv = document.getElementById('loginError');
    const loginBtn = document.getElementById('loginBtn');
    const loginBtnText = document.getElementById('loginBtnText');
    const loginBtnSpinner = document.getElementById('loginBtnSpinner');

    // Hiển thị loading
    loginBtn.disabled = true;
    loginBtnText.style.display = 'none';
    loginBtnSpinner.style.display = 'inline-flex';
    errorDiv.style.display = 'none';

    // Giả lập thời gian xử lý đăng nhập
    setTimeout(() => {
        // Thực hiện đăng nhập
        const success = login(username, password);

        if (success) {
            // Đăng nhập thành công - giữ loading khi chuyển trang
            setTimeout(() => {
                showDashboard();
                // Reset button về trạng thái ban đầu
                loginBtn.disabled = false;
                loginBtnText.style.display = 'inline';
                loginBtnSpinner.style.display = 'none';
            }, 500);
        } else {
            // Đăng nhập thất bại
            loginBtn.disabled = false;
            loginBtnText.style.display = 'inline';
            loginBtnSpinner.style.display = 'none';
            errorDiv.style.display = 'block';

            // Reset password field
            document.getElementById('password').value = '';
            document.getElementById('password').focus();
        }
    }, 800); // Hiển thị loading trong 800ms
}

/**
 * Xử lý đăng xuất
 */
function handleLogout() {
    logout(); // Logout sẽ tự hiển thị modal xác nhận
}

/**
 * Khởi tạo navigation (chuyển tab)
 */
function initNavigation() {
    const navItems = document.querySelectorAll('.nav-item');

    navItems.forEach(item => {
        item.addEventListener('click', (event) => {
            event.preventDefault();

            // Lấy section cần hiển thị
            const sectionId = item.getAttribute('data-section');

            // Hiển thị section
            showSection(sectionId);

            // Highlight nav item đang active
            navItems.forEach(nav => nav.classList.remove('active'));
            item.classList.add('active');
        });
    });
}

/**
 * Hiển thị section theo ID
 */
function showSection(sectionId) {
    // Ẩn tất cả sections
    const sections = document.querySelectorAll('.content-section');
    sections.forEach(section => section.classList.remove('active'));

    // Hiển thị section được chọn
    const targetSection = document.getElementById(sectionId);
    if (targetSection) {
        targetSection.classList.add('active');
    }

    // Cập nhật dữ liệu tùy theo section
    switch (sectionId) {
        case 'dashboard':
            updateDeviceStats();
            break;
        case 'devices':
            renderDeviceTable();
            break;
        case 'users':
            renderUserTable();
            break;
        case 'libraries':
            renderLibraryTable();
            break;
    }

    console.log(`📍 Chuyển sang section: ${sectionId}`);
}

/**
 * Chạy ứng dụng khi DOM đã load
 */
document.addEventListener('DOMContentLoaded', () => {
    initApp();
});

// Export các hàm cần thiết
export {
    showSection,
    updateDeviceStats
};
