/**
 * ==============================================
 * USERS MANAGEMENT MODULE
 * ==============================================
 * Quản lý người dùng: Hiển thị, xem mật khẩu, reset mật khẩu, xóa liên kết thiết bị
 */

import { readData, writeData, updateData, firebaseEnabled } from './firebase.js';
import { showSecurityPrompt } from './auth.js';

// Mock data người dùng
let mockUsers = {};
let filteredUsers = {};
let currentPage = 1;
const usersPerPage = 5;

/**
 * Khởi tạo module Users
 */
export async function initUsers() {
    console.log('👥 Khởi tạo module Users...');

    // Load dữ liệu người dùng
    await loadUsers();

    // Render bảng người dùng
    renderUserTable();
}

/**
 * Load danh sách người dùng từ Firebase hoặc mock data
 */
async function loadUsers() {
    try {
        console.log('🔄 Đang load người dùng từ Firebase...');
        const usersData = await readData('users');
        const devicesData = await readData('devices');

        if (usersData && Object.keys(usersData).length > 0) {
            // Xử lý dữ liệu users
            mockUsers = {};

            for (const [userId, userData] of Object.entries(usersData)) {
                // Đếm số thiết bị có ownerId = userId
                let deviceCount = 0;
                let userDevices = [];

                if (devicesData) {
                    for (const [deviceId, device] of Object.entries(devicesData)) {
                        if (device.info && device.info.ownerId === userId) {
                            deviceCount++;
                            userDevices.push(deviceId);
                        }
                    }
                }

                mockUsers[userId] = {
                    fullName: userData.displayName || userData.email || 'Unknown User',
                    username: userData.email ? userData.email.split('@')[0] : userId,
                    email: userData.email || '',
                    phoneNumber: userData.phoneNumber || '',
                    createdAt: userData.createdAt || Date.now(),
                    deviceCount: deviceCount,
                    devices: userDevices,
                    ...userData
                };
            }

            console.log('✅ Đã load người dùng từ Firebase:', Object.keys(mockUsers).length, 'người dùng');
        } else {
            console.log('⚠️ Không có dữ liệu người dùng, dùng mock data');
            mockUsers = generateMockUsers();
        }
    } catch (error) {
        console.error('❌ Lỗi khi load người dùng:', error);
        mockUsers = generateMockUsers();
    }
}

/**
 * Tạo dữ liệu người dùng mẫu
 */
function generateMockUsers() {
    return {
        
    };
}

/**
 * Render bảng người dùng với pagination
 */
export function renderUserTable() {
    const tbody = document.getElementById('usersTableBody');
    if (!tbody) return;

    if (Object.keys(mockUsers).length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-center">Chưa có người dùng nào</td></tr>';
        renderUserPagination(0, 0);
        return;
    }

    // Áp dụng filter
    filteredUsers = filterUsers();
    const users = Object.entries(filteredUsers);
    const totalUsers = users.length;
    const totalPages = Math.ceil(totalUsers / usersPerPage);

    if (totalUsers === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-center">Không tìm thấy người dùng nào phù hợp</td></tr>';
        renderUserPagination(0, 0);
        return;
    }

    // Tính toán users cho trang hiện tại
    const startIndex = (currentPage - 1) * usersPerPage;
    const endIndex = startIndex + usersPerPage;
    const currentUsers = users.slice(startIndex, endIndex);

    let html = '';
    let rowNum = startIndex + 1;

    for (const [userId, user] of currentUsers) {
        const fullEmail = user.email || `${user.username}@example.com`;
        const deviceCount = user.deviceCount || 0;

        // Format ngày đăng ký
        const createdDate = user.createdAt ? new Date(user.createdAt).toLocaleDateString('vi-VN') : '--';

        html += `
            <tr>
                <td>${rowNum++}</td>
                <td><strong>${user.fullName}</strong></td>
                <td style="position: relative;">
                    <span id="account_${userId}" style="display: inline-block; min-width: 150px;">••••••••••••</span>
                    <button class="btn-icon" onclick="window.userModule.showAccountInfo('${userId}')" title="Xem tài khoản">
                        <i id="account_eye_${userId}" class="bi bi-eye"></i>
                    </button>
                </td>
                <td>${createdDate}</td>
                <td>
                    <strong style="color: #4CAF50;">${deviceCount}</strong>
                    ${deviceCount > 0 ? `<button class="btn-icon" onclick="window.userModule.showUserDevices('${userId}')" title="Xem danh sách thiết bị" style="margin-left: 8px;">
                        <i class="bi bi-list-ul"></i>
                    </button>` : ''}
                </td>
            </tr>
        `;
    }

    tbody.innerHTML = html;
    renderUserPagination(totalUsers, totalPages);

    // Cập nhật stats
    if (window.updateUserStats) {
        window.updateUserStats();
    }
}

/**
 * Render phân trang cho users
 */
function renderUserPagination(totalUsers, totalPages) {
    const container = document.getElementById('usersPagination');
    if (!container) return;

    if (totalPages <= 1) {
        container.innerHTML = '';
        return;
    }

    let html = '<div class="pagination-wrapper">';
    html += '<div class="pagination-info">Hiển thị ' +
            ((currentPage - 1) * usersPerPage + 1) + '-' +
            Math.min(currentPage * usersPerPage, totalUsers) +
            ' trong tổng ' + totalUsers + ' người dùng</div>';

    html += '<div class="pagination">';

    // Previous button
    html += `
        <button class="page-btn prev ${currentPage === 1 ? 'disabled' : ''}"
                data-page="${currentPage - 1}"
                onclick="window.userModule.goToPage(${currentPage - 1})"
                ${currentPage === 1 ? 'disabled' : ''}>
            <i class="bi bi-chevron-left"></i> Trước
        </button>
    `;

    // Page numbers
    html += '<div class="page-numbers">';
    for (let i = 1; i <= totalPages; i++) {
        if (
            i === 1 ||
            i === totalPages ||
            (i >= currentPage - 1 && i <= currentPage + 1)
        ) {
            html += `
                <button class="page-btn ${i === currentPage ? 'active' : ''}"
                        data-page="${i}"
                        onclick="window.userModule.goToPage(${i})">
                    ${i}
                </button>
            `;
        } else if (i === currentPage - 2 || i === currentPage + 2) {
            html += '<span class="page-ellipsis">...</span>';
        }
    }
    html += '</div>';

    // Next button
    html += `
        <button class="page-btn next ${currentPage === totalPages ? 'disabled' : ''}"
                data-page="${currentPage + 1}"
                onclick="window.userModule.goToPage(${currentPage + 1})"
                ${currentPage === totalPages ? 'disabled' : ''}>
            Sau <i class="bi bi-chevron-right"></i>
        </button>
    `;

    html += '</div></div>';
    container.innerHTML = html;
}

/**
 * Chuyển trang
 */
function goToPage(page) {
    const totalPages = Math.ceil(Object.keys(filteredUsers).length / usersPerPage);
    if (page < 1 || page > totalPages) return;

    currentPage = page;
    renderUserTable();

    // Scroll to top of table
    document.getElementById('usersTable')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/**
 * Tính số thiết bị của user từ devices
 */
function calculateUserDeviceCount(userId) {
    // Import devices từ devices module nếu có
    // Tạm thời return từ user data
    const user = mockUsers[userId];
    return user.deviceCount || 0;
}

/**
 * Hiển thị modal thêm người dùng
 */
function showAddUserModal() {
    alert('Chức năng thêm người dùng đang được phát triển...');
    // TODO: Implement add user modal
}

/**
 * Xem thông tin tài khoản người dùng (yêu cầu mã xác thực)
 */
function showAccountInfo(userId) {
    showSecurityPrompt(() => {
        const user = mockUsers[userId];
        if (!user) return;

        const accountSpan = document.getElementById(`account_${userId}`);
        const eyeIcon = document.getElementById(`account_eye_${userId}`);
        const fullEmail = user.email || `${user.username}@example.com`;

        if (accountSpan.textContent === '••••••••••••') {
            // Hiển thị email/tài khoản
            accountSpan.textContent = fullEmail;
            accountSpan.style.color = '#2196F3';
            accountSpan.style.fontWeight = 'bold';
            eyeIcon.className = 'bi bi-eye-slash';

            // Tự động ẩn sau 10 giây
            setTimeout(() => {
                accountSpan.textContent = '••••••••••••';
                accountSpan.style.color = '';
                accountSpan.style.fontWeight = '';
                eyeIcon.className = 'bi bi-eye';
            }, 10000);
        } else {
            // Ẩn email/tài khoản
            accountSpan.textContent = '••••••••••••';
            accountSpan.style.color = '';
            accountSpan.style.fontWeight = '';
            eyeIcon.className = 'bi bi-eye';
        }
    });
}

/**
 * Hiển thị danh sách thiết bị của người dùng
 */
async function showUserDevices(userId) {
    const user = mockUsers[userId];
    if (!user) return;

    // Load danh sách thiết bị của user
    const devicesData = await readData('devices');
    const statusData = await readData('status');
    const userDevicesList = [];

    if (devicesData) {
        for (const [deviceId, device] of Object.entries(devicesData)) {
            if (device.info && device.info.ownerId === userId) {
                const deviceStatus = statusData && statusData[deviceId] ? statusData[deviceId] : { online: false };
                userDevicesList.push({
                    id: deviceId,
                    name: device.info.deviceName || '...',
                    online: deviceStatus.online === true
                });
            }
        }
    }

    if (userDevicesList.length === 0) {
        alert('Người dùng này không có thiết bị nào.');
        return;
    }

    // Tạo HTML cho danh sách thiết bị
    let devicesHTML = userDevicesList.map((device, index) => `
        <div style="padding: 12px; border: 1px solid var(--border-color); border-radius: 8px; margin-bottom: 10px; display: flex; justify-content: space-between; align-items: center;">
            <div>
                <strong>${index + 1}. ${device.name}</strong>
                <span class="status-badge ${device.online ? 'status-online' : 'status-offline'}" style="margin-left: 10px; font-size: 11px;">
                    ${device.online ? '✅ Online' : '❌ Offline'}
                </span>
                <br>
                <code style="font-size: 12px; color: var(--text-secondary);">${device.id}</code>
            </div>
        </div>
    `).join('');

    const modalHTML = `
        <div class="modal show" id="userDevicesModal">
            <div class="modal-content" style="max-width: 600px;">
                <div class="modal-header">
                    <h3 class="modal-title">📱 Danh sách thiết bị - ${user.fullName}</h3>
                    <button class="modal-close" id="closeUserDevicesModal">&times;</button>
                </div>
                <div class="modal-body" style="max-height: 400px; overflow-y: auto;">
                    <p><strong>Tổng số thiết bị: ${userDevicesList.length}</strong></p>
                    <hr style="margin: 16px 0; border: none; border-top: 1px solid var(--border-color);">
                    ${devicesHTML}
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary" id="btnCloseUserDevices">Đóng</button>
                </div>
            </div>
        </div>
    `;

    const container = document.getElementById('modalContainer');
    container.innerHTML = modalHTML;

    document.getElementById('closeUserDevicesModal').onclick = () => {
        document.getElementById('userDevicesModal').remove();
    };

    document.getElementById('btnCloseUserDevices').onclick = () => {
        document.getElementById('userDevicesModal').remove();
    };
}

/**
 * Xóa liên kết thiết bị của người dùng (yêu cầu mã xác thực)
 */
async function unlinkDevices(userId) {
    showSecurityPrompt(async () => {
        const user = mockUsers[userId];
        if (!user) return;

        // Load danh sách thiết bị của user
        const devicesData = await readData('devices');
        const userDevicesList = [];

        if (devicesData) {
            for (const [deviceId, device] of Object.entries(devicesData)) {
                if (device.info && device.info.ownerId === userId) {
                    userDevicesList.push({
                        id: deviceId,
                        name: device.info.deviceName || deviceId
                    });
                }
            }
        }

        if (userDevicesList.length === 0) {
            alert('Người dùng này không có thiết bị nào được liên kết.');
            return;
        }

        // Tạo HTML cho danh sách thiết bị
        let devicesHTML = userDevicesList.map((device, index) => `
            <div style="padding: 10px; border: 1px solid var(--border-color); border-radius: 6px; margin-bottom: 10px; display: flex; justify-content: space-between; align-items: center;">
                <div>
                    <strong>${index + 1}. ${device.name}</strong><br>
                    <code style="font-size: 12px;">${device.id}</code>
                </div>
                <button class="btn btn-sm btn-danger" onclick="window.userModule.unlinkSingleDevice('${userId}', '${device.id}')">
                    <i class="bi bi-trash"></i> Xóa
                </button>
            </div>
        `).join('');

        const modalHTML = `
            <div class="modal show" id="unlinkDevicesModal">
                <div class="modal-content" style="max-width: 600px;">
                    <div class="modal-header">
                        <h3 class="modal-title">🔗 Xóa liên kết thiết bị - ${user.fullName}</h3>
                        <button class="modal-close" id="closeUnlinkModal">&times;</button>
                    </div>
                    <div class="modal-body" style="max-height: 400px; overflow-y: auto;">
                        <p><strong>Danh sách thiết bị (${userDevicesList.length}):</strong></p>
                        ${devicesHTML}
                    </div>
                    <div class="modal-footer">
                        <button class="btn btn-secondary" id="btnCancelUnlink">Đóng</button>
                    </div>
                </div>
            </div>
        `;

        const container = document.getElementById('modalContainer');
        container.innerHTML = modalHTML;

        document.getElementById('closeUnlinkModal').onclick = () => {
            document.getElementById('unlinkDevicesModal').remove();
        };

        document.getElementById('btnCancelUnlink').onclick = () => {
            document.getElementById('unlinkDevicesModal').remove();
        };
    });
}

/**
 * Xóa liên kết 1 thiết bị cụ thể
 */
async function unlinkSingleDevice(userId, deviceId) {
    if (!confirm(`⚠️ Xác nhận xóa liên kết thiết bị này?`)) {
        return;
    }

    try {
        // Cập nhật device: xóa ownerId, set claimed = false
        if (firebaseEnabled) {
            await updateData(`devices/${deviceId}/info`, {
                ownerId: '',
                claimed: false,
                claimedAt: null
            });
        }

        // Reload users để cập nhật deviceCount
        await loadUsers();
        renderUserTable();

        // Đóng modal và mở lại với danh sách cập nhật
        document.getElementById('unlinkDevicesModal').remove();

        alert(`✅ Đã xóa liên kết thiết bị thành công!`);

        // Mở lại modal
        unlinkDevices(userId);

    } catch (error) {
        alert('❌ Lỗi khi xóa liên kết: ' + error.message);
    }
}

// Export để gọi từ ngoài
window.userModule = {
    showAccountInfo,
    showUserDevices,
    unlinkDevices,
    unlinkSingleDevice,
    goToPage
};

/**
 * ==================== FILTER & SEARCH ====================
 */

// Biến lưu trạng thái filter
let userFilters = {
    searchText: '',
    deviceStatus: ''
};

/**
 * Khởi tạo filter events
 */
export function initUserFilters() {
    const searchInput = document.getElementById('userSearchInput');
    const deviceFilter = document.getElementById('userDeviceFilter');
    const resetBtn = document.getElementById('btnResetUserFilter');

    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            userFilters.searchText = e.target.value.toLowerCase().trim();
            renderUserTable();
        });
    }

    if (deviceFilter) {
        deviceFilter.addEventListener('change', (e) => {
            userFilters.deviceStatus = e.target.value;
            renderUserTable();
        });
    }

    if (resetBtn) {
        resetBtn.addEventListener('click', () => {
            userFilters = { searchText: '', deviceStatus: '' };
            if (searchInput) searchInput.value = '';
            if (deviceFilter) deviceFilter.value = '';
            currentPage = 1;
            renderUserTable();
        });
    }
}

/**
 * Lọc users theo điều kiện
 */
function filterUsers() {
    let filtered = Object.entries(mockUsers);

    // Lọc theo text search
    if (userFilters.searchText) {
        filtered = filtered.filter(([userId, user]) => {
            const fullName = (user.fullName || '').toLowerCase();
            const searchText = userFilters.searchText;

            return fullName.includes(searchText);
        });
    }

    // Lọc theo device status
    if (userFilters.deviceStatus) {
        filtered = filtered.filter(([userId, user]) => {
            const deviceCount = user.deviceCount || 0;

            switch (userFilters.deviceStatus) {
                case 'hasDevices':
                    return deviceCount > 0;
                case 'noDevices':
                    return deviceCount === 0;
                default:
                    return true;
            }
        });
    }

    return Object.fromEntries(filtered);
}
