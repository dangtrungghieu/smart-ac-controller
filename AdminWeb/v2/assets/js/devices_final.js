/**
 * ==============================================
 * DEVICES MANAGEMENT MODULE - FINAL VERSION
 * ==============================================
 * - Modal đẹp
 * - Search & Filter
 * - Pagination (6 devices/page)
 * - Add device modal
 */

import { readData, writeData, updateData, deleteData, firebaseEnabled } from './firebase.js';

let mockDevices = {};
let filteredDevices = {};
let currentPage = 1;
const devicesPerPage = 5;
const ADMIN_CODE = "123456";
const SENSOR_TIMEOUT_MS = 15000; // 15 seconds - sensor offline if no update within this time
let previousTimestamps = {}; // Lưu timestamps lần trước để so sánh
let deviceComputedStatus = {}; // Lưu trạng thái đã tính toán để dùng cho filter

/**
 * Khởi tạo module
 */
export async function initDevices() {
    console.log('📱 Khởi tạo Devices Module (Final)...');

    await loadDevices();
    setupEventListeners();
    renderDeviceTable();
    startMonitoring();
}

/**
 * Load dữ liệu thiết bị
 */
async function loadDevices() {
    try {
        const devicesData = await readData('devices');
        const statusData = await readData('status');
        const usersData = await readData('users');

        if (devicesData && Object.keys(devicesData).length > 0) {
            mockDevices = {};

            for (const [deviceId, device] of Object.entries(devicesData)) {
                let ownerName = null;
                if (device.info?.ownerId && usersData) {
                    const owner = usersData[device.info.ownerId];
                    if (owner) {
                        ownerName = owner.displayName || owner.email || device.info.ownerId;
                    }
                }

                mockDevices[deviceId] = {
                    ...device,
                    ownerName: ownerName,
                    status: statusData?.[deviceId] || { online: false }
                };
            }
            console.log('✅ Đã load', Object.keys(mockDevices).length, 'thiết bị');
            filteredDevices = { ...mockDevices };
        } else {
            console.log('⚠️ Không có dữ liệu');
            mockDevices = {};
            filteredDevices = {};
        }
    } catch (error) {
        console.error('❌ Lỗi load devices:', error);
        mockDevices = {};
        filteredDevices = {};
    }
}

/**
 * Setup event listeners
 */
function setupEventListeners() {
    console.log('🔗 Setup event listeners...');

    // Nút thêm thiết bị
    document.getElementById('btnAddDevice')?.addEventListener('click', showAddDeviceModal);

    // Search input
    document.getElementById('deviceSearchInput')?.addEventListener('input', handleSearch);

    // Filter select
    document.getElementById('deviceStatusFilter')?.addEventListener('change', handleFilter);

    // Reset filter button
    document.getElementById('btnResetDeviceFilter')?.addEventListener('click', resetFilters);

    // Delegate events trên document
    document.addEventListener('click', handleClick);

    console.log('✅ Event listeners ready');
}

/**
 * Xử lý tất cả click events
 */
function handleClick(e) {
    // Nút toggle claim code
    if (e.target.closest('.btn-toggle-claim')) {
        const btn = e.target.closest('.btn-toggle-claim');
        const deviceId = btn.dataset.deviceId;
        toggleClaimCode(deviceId);
        return;
    }

    // Nút 3 chấm - mở modal
    if (e.target.closest('.btn-device-menu')) {
        const btn = e.target.closest('.btn-device-menu');
        const deviceId = btn.dataset.deviceId;
        showDeviceActionModal(deviceId);
        return;
    }

    // Đóng modal khi click overlay
    if (e.target.classList.contains('modal-overlay')) {
        closeModal();
        return;
    }

    // Nút đóng modal
    if (e.target.closest('.modal-close') || e.target.closest('.btn-cancel')) {
        closeModal();
        return;
    }

    // Các nút action trong modal
    if (e.target.closest('[data-action]')) {
        const btn = e.target.closest('[data-action]');
        const action = btn.dataset.action;
        const deviceId = btn.dataset.deviceId;
        handleAction(action, deviceId);
        return;
    }

    // Pagination
    if (e.target.closest('.page-btn')) {
        const btn = e.target.closest('.page-btn');
        const page = parseInt(btn.dataset.page);
        if (!isNaN(page) && !btn.disabled) {
            goToPage(page);
        }
        return;
    }
}

/**
 * Hiển thị modal thao tác thiết bị
 */
function showDeviceActionModal(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const deviceName = device.info?.deviceName || 'Thiết bị';

    const modalHTML = `
        <div class="modal-overlay" id="deviceActionModal">
            <div class="modal-container">
                <div class="modal-header">
                    <div class="modal-title">
                        <h2>${deviceName}</h2>
                        <p class="modal-subtitle"><code>${deviceId}</code></p>
                    </div>
                    <button class="modal-close">
                        <i class="bi bi-x-lg"></i>
                    </button>
                </div>

                <div class="modal-body">
                    <button class="action-btn" data-action="changeClaimCode" data-device-id="${deviceId}">
                        <i class="bi bi-key"></i>
                        <div class="action-content">
                            <span class="action-title">Đổi Claim Code</span>
                            <span class="action-desc">Thay đổi mã kích hoạt thiết bị</span>
                        </div>
                        <i class="bi bi-chevron-right"></i>
                    </button>

                    <button class="action-btn" data-action="exportPDF" data-device-id="${deviceId}">
                        <i class="bi bi-file-earmark-pdf"></i>
                        <div class="action-content">
                            <span class="action-title">Xuất thông tin thiết bị</span>
                            <span class="action-desc">Tạo file PDF hướng dẫn cho khách hàng</span>
                        </div>
                        <i class="bi bi-chevron-right"></i>
                    </button>

                    <button class="action-btn danger" data-action="deleteDevice" data-device-id="${deviceId}">
                        <i class="bi bi-trash"></i>
                        <div class="action-content">
                            <span class="action-title">Xóa thiết bị</span>
                            <span class="action-desc">Xóa vĩnh viễn khỏi hệ thống</span>
                        </div>
                        <i class="bi bi-chevron-right"></i>
                    </button>
                </div>

                <div class="modal-footer">
                    <button class="btn-cancel">Đóng</button>
                </div>
            </div>
        </div>
    `;

    document.body.insertAdjacentHTML('beforeend', modalHTML);
    setTimeout(() => {
        document.getElementById('deviceActionModal').classList.add('show');
    }, 10);
}

/**
 * Xử lý action
 */
function handleAction(action, deviceId) {
    switch(action) {
        case 'changeClaimCode':
            showVerificationModal(deviceId, changeClaimCode);
            break;
        case 'exportPDF':
            closeModal();
            exportDeviceInfo(deviceId);
            break;
        case 'deleteDevice':
            showVerificationModal(deviceId, deleteDevice);
            break;
    }
}

/**
 * Hiển thị modal xác thực
 */
function showVerificationModal(deviceId, callback) {
    const device = mockDevices[deviceId];
    const deviceName = device.info?.deviceName || 'Thiết bị';

    const modalHTML = `
        <div class="modal-overlay verification-modal" id="verificationModal">
            <div class="modal-container small">
                <div class="modal-header">
                    <h2>Xác thực</h2>
                    <button class="modal-close">
                        <i class="bi bi-x-lg"></i>
                    </button>
                </div>

                <div class="modal-body">
                    <p class="verification-text">Vui lòng nhập mã xác thực để thực hiện thao tác trên thiết bị:</p>
                    <p class="device-name-verify"><strong>${deviceName}</strong> <code>${deviceId}</code></p>

                    <div class="form-group">
                        <label for="verificationCode">Mã xác thực</label>
                        <input type="password"
                               id="verificationCode"
                               class="form-control"
                               placeholder="Nhập mã 6 số"
                               maxlength="6"
                               autocomplete="off">
                        <small class="form-hint">Liên hệ quản trị viên để lấy mã xác thực</small>
                        <div class="error-message" id="verificationError" style="display: none;"></div>
                    </div>
                </div>

                <div class="modal-footer">
                    <button class="btn-cancel">Hủy</button>
                    <button class="btn-primary" id="btnVerify">Xác nhận</button>
                </div>
            </div>
        </div>
    `;

    closeModal();
    document.body.insertAdjacentHTML('beforeend', modalHTML);
    setTimeout(() => {
        document.getElementById('verificationModal').classList.add('show');
        document.getElementById('verificationCode').focus();
    }, 10);

    const btnVerify = document.getElementById('btnVerify');
    const inputCode = document.getElementById('verificationCode');
    const errorDiv = document.getElementById('verificationError');

    const handleVerify = () => {
        const code = inputCode.value.trim();

        if (!code) {
            showError('Vui lòng nhập mã xác thực');
            return;
        }

        if (code !== ADMIN_CODE) {
            showError('Mã xác thực không đúng. Vui lòng thử lại.');
            inputCode.value = '';
            inputCode.focus();
            return;
        }

        closeModal();
        callback(deviceId);
    };

    btnVerify.addEventListener('click', handleVerify);
    inputCode.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleVerify();
    });

    function showError(message) {
        errorDiv.textContent = message;
        errorDiv.style.display = 'block';
        inputCode.classList.add('error');

        setTimeout(() => {
            errorDiv.style.display = 'none';
            inputCode.classList.remove('error');
        }, 3000);
    }
}

/**
 * Đóng modal
 */
function closeModal() {
    const modals = document.querySelectorAll('.modal-overlay');
    modals.forEach(modal => {
        modal.classList.remove('show');
        setTimeout(() => modal.remove(), 300);
    });
}

/**
 * Kiểm tra trạng thái sensor dựa trên timestamp
 * @param {string} deviceId - ID của thiết bị
 * @param {string} sensorKey - Key của sensor (lastSeen, ac, room, hlk)
 * @param {number} timestamp - Timestamp cần kiểm tra
 * @returns {boolean} - true nếu sensor online (có thay đổi gần đây), false nếu offline
 */
function isSensorOnline(deviceId, sensorKey, timestamp) {
    if (!timestamp || typeof timestamp !== 'number') {
        return false;
    }

    // Khởi tạo object cho device nếu chưa có
    if (!previousTimestamps[deviceId]) {
        previousTimestamps[deviceId] = {};
    }

    // Lần đầu tiên thấy sensor này
    if (previousTimestamps[deviceId][sensorKey] === undefined) {
        previousTimestamps[deviceId][sensorKey] = {
            value: timestamp,
            lastChanged: Date.now(),
            firstSeen: Date.now()
        };
        // Lần đầu thấy: kiểm tra xem timestamp có gần đây không
        // Nếu timestamp cũ hơn 3 giây so với hiện tại thì coi như offline
        const timeSinceTimestamp = Date.now() - timestamp;
        return timeSinceTimestamp < SENSOR_TIMEOUT_MS;
    }

    // So sánh với giá trị trước đó
    const previous = previousTimestamps[deviceId][sensorKey];
    const hasChanged = previous.value !== timestamp;

    if (hasChanged) {
        // Timestamp đã thay đổi - sensor đang hoạt động
        previousTimestamps[deviceId][sensorKey] = {
            value: timestamp,
            lastChanged: Date.now(),
            firstSeen: previous.firstSeen
        };
        return true;
    } else {
        // Timestamp không đổi - kiểm tra thời gian từ lần thay đổi cuối
        const timeSinceChange = Date.now() - previous.lastChanged;
        return timeSinceChange < SENSOR_TIMEOUT_MS;
    }
}

/**
 * Render bảng thiết bị với pagination
 */
export function renderDeviceTable() {
    const tbody = document.getElementById('devicesTableBody');
    if (!tbody) return;

    const devices = Object.entries(filteredDevices);
    const totalDevices = devices.length;
    const totalPages = Math.ceil(totalDevices / devicesPerPage);

    if (totalDevices === 0) {
        tbody.innerHTML = '<tr><td colspan="11" class="text-center">Chưa có thiết bị</td></tr>';
        renderPagination(0, 0);
        return;
    }

    // Tính toán devices cho trang hiện tại
    const startIndex = (currentPage - 1) * devicesPerPage;
    const endIndex = startIndex + devicesPerPage;
    const currentDevices = devices.slice(startIndex, endIndex);

    let html = '';
    let index = startIndex + 1;

    currentDevices.forEach(([deviceId, device]) => {
        const info = device.info || {};
        const status = device.status || {};
        const deviceName = info.deviceName?.trim() || '...';
        const ownerName = device.ownerName || '...';
        const isOnline = status.online === true;

        // Kiểm tra trạng thái từng sensor
        const esp32Online = isSensorOnline(deviceId, 'lastSeen', status.lastSeen);
        const pzemOnline = isSensorOnline(deviceId, 'ac', status.ac?.lastUpdate);
        const dht22Online = isSensorOnline(deviceId, 'room', status.room?.lastUpdate);
        const hlkOnline = isSensorOnline(deviceId, 'hlk', status.room?.lastUpdate);

        // Tính trạng thái tổng: nếu có ít nhất 1 sensor online thì thiết bị online
        const deviceOnline = esp32Online || pzemOnline || dht22Online || hlkOnline;

        // Lưu trạng thái đã tính toán để dùng cho filter
        deviceComputedStatus[deviceId] = deviceOnline;

        // Debug: Log sensor status
        console.log(`📊 ${deviceId}:`, {
            esp32: { timestamp: status.lastSeen, online: esp32Online },
            pzem: { timestamp: status.ac?.lastUpdate, online: pzemOnline },
            dht22: { timestamp: status.room?.lastUpdate, online: dht22Online },
            hlk: { timestamp: status.room?.lastUpdate, online: hlkOnline },
            deviceOnline: deviceOnline
        });

        html += `
            <tr>
                <td>${index++}</td>
                <td><strong>${deviceName}</strong></td>
                <td><code>${deviceId}</code></td>
                <td>${ownerName}</td>
                <td>
                    <span class="claim-code-hidden" id="claim-${deviceId}">••••••</span>
                    <button class="btn-icon btn-toggle-claim" data-device-id="${deviceId}">
                        <i class="bi bi-eye" id="eye-${deviceId}"></i>
                    </button>
                </td>
                <td>
                    <span class="status-badge ${deviceOnline ? 'status-online' : 'status-offline'}">
                        ${deviceOnline ? '🟢 Online' : '🔴 Offline'}
                    </span>
                </td>
                <td><span class="sensor-badge ${esp32Online ? 'sensor-online' : 'sensor-offline'}">${esp32Online ? '✅' : '❌'}</span></td>
                <td><span class="sensor-badge ${pzemOnline ? 'sensor-online' : 'sensor-offline'}">${pzemOnline ? '✅' : '❌'}</span></td>
                <td><span class="sensor-badge ${dht22Online ? 'sensor-online' : 'sensor-offline'}">${dht22Online ? '✅' : '❌'}</span></td>
                <td><span class="sensor-badge ${hlkOnline ? 'sensor-online' : 'sensor-offline'}">${hlkOnline ? '✅' : '❌'}</span></td>
                <td>
                    <button class="btn-icon btn-device-menu" data-device-id="${deviceId}" title="Thao tác">
                        <i class="bi bi-three-dots-vertical"></i>
                    </button>
                </td>
            </tr>
        `;
    });

    tbody.innerHTML = html;
    renderPagination(totalDevices, totalPages);
    updateStats();
}

/**
 * Render phân trang
 */
function renderPagination(totalDevices, totalPages) {
    const container = document.getElementById('devicesPagination');
    if (!container) return;

    if (totalPages <= 1) {
        container.innerHTML = '';
        return;
    }

    let html = '<div class="pagination-wrapper">';
    html += '<div class="pagination-info">Hiển thị ' +
            ((currentPage - 1) * devicesPerPage + 1) + '-' +
            Math.min(currentPage * devicesPerPage, totalDevices) +
            ' trong tổng ' + totalDevices + ' thiết bị</div>';

    html += '<div class="pagination">';

    // Previous button
    html += `
        <button class="page-btn prev ${currentPage === 1 ? 'disabled' : ''}"
                data-page="${currentPage - 1}"
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
                        data-page="${i}">
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
    const totalPages = Math.ceil(Object.keys(filteredDevices).length / devicesPerPage);
    if (page < 1 || page > totalPages) return;

    currentPage = page;
    renderDeviceTable();

    // Scroll to top of table
    document.getElementById('devicesTable')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/**
 * Search devices
 */
function handleSearch(e) {
    const searchTerm = e.target.value.toLowerCase().trim();
    applyFilters(searchTerm, document.getElementById('deviceStatusFilter')?.value || '');
}

/**
 * Filter devices
 */
function handleFilter(e) {
    const filterValue = e.target.value;
    applyFilters(document.getElementById('deviceSearchInput')?.value.toLowerCase().trim() || '', filterValue);
}

/**
 * Apply filters
 */
function applyFilters(searchTerm, filterValue) {
    filteredDevices = {};

    for (const [deviceId, device] of Object.entries(mockDevices)) {
        const info = device.info || {};
        const status = device.status || {};

        // Search filter
        const matchSearch = !searchTerm ||
            deviceId.toLowerCase().includes(searchTerm) ||
            (info.deviceName || '').toLowerCase().includes(searchTerm) ||
            (device.ownerName || '').toLowerCase().includes(searchTerm) ||
            (info.claimCode || '').toLowerCase().includes(searchTerm);

        if (!matchSearch) continue;

        // Status filter - sử dụng trạng thái đã tính toán từ sensor
        let matchFilter = true;
        if (filterValue === 'online' || filterValue === 'offline') {
            // Tính toán trạng thái thiết bị từ các sensor
            const esp32Online = isSensorOnline(deviceId, 'lastSeen', status.lastSeen);
            const pzemOnline = isSensorOnline(deviceId, 'ac', status.ac?.lastUpdate);
            const dht22Online = isSensorOnline(deviceId, 'room', status.room?.lastUpdate);
            const hlkOnline = isSensorOnline(deviceId, 'hlk', status.room?.lastUpdate);
            const deviceOnline = esp32Online || pzemOnline || dht22Online || hlkOnline;

            // Lưu lại để dùng khi render
            deviceComputedStatus[deviceId] = deviceOnline;

            if (filterValue === 'online') {
                matchFilter = deviceOnline === true;
            } else if (filterValue === 'offline') {
                matchFilter = deviceOnline === false;
            }
        } else if (filterValue === 'claimed') {
            matchFilter = info.claimed === true;
        } else if (filterValue === 'unclaimed') {
            matchFilter = info.claimed !== true;
        }

        if (matchFilter) {
            filteredDevices[deviceId] = device;
        }
    }

    currentPage = 1; // Reset to first page
    renderDeviceTable();
}

/**
 * Reset filters
 */
function resetFilters() {
    document.getElementById('deviceSearchInput').value = '';
    document.getElementById('deviceStatusFilter').value = '';
    filteredDevices = { ...mockDevices };
    currentPage = 1;
    renderDeviceTable();
}

/**
 * Toggle hiển thị claim code
 */
function toggleClaimCode(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const codeElement = document.getElementById(`claim-${deviceId}`);
    const iconElement = document.getElementById(`eye-${deviceId}`);
    const claimCode = device.info?.claimCode || '------';

    if (codeElement.textContent === '••••••') {
        codeElement.textContent = claimCode;
        codeElement.style.color = '#2196F3';
        codeElement.style.fontWeight = 'bold';
        iconElement.className = 'bi bi-eye-slash';

        setTimeout(() => {
            codeElement.textContent = '••••••';
            codeElement.style.color = '';
            codeElement.style.fontWeight = '';
            iconElement.className = 'bi bi-eye';
        }, 5000);
    } else {
        codeElement.textContent = '••••••';
        codeElement.style.color = '';
        codeElement.style.fontWeight = '';
        iconElement.className = 'bi bi-eye';
    }
}

/**
 * Đổi claim code
 */
async function changeClaimCode(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const deviceName = device.info?.deviceName || 'Thiết bị';
    const currentCode = device.info?.claimCode || '';

    const modalHTML = `
        <div class="modal-overlay" id="changeClaimCodeModal">
            <div class="modal-container small">
                <div class="modal-header">
                    <div class="modal-title">
                        <h2>Đổi Claim Code</h2>
                        <p class="modal-subtitle">${deviceName} <code>${deviceId}</code></p>
                    </div>
                    <button class="modal-close">
                        <i class="bi bi-x-lg"></i>
                    </button>
                </div>

                <div class="modal-body">
                    <div class="form-group">
                        <label for="currentClaimCode">Claim Code hiện tại</label>
                        <input type="text"
                               id="currentClaimCode"
                               class="form-control"
                               value="${currentCode}"
                               disabled
                               style="background: var(--bg-secondary); opacity: 0.7;">
                    </div>

                    <div class="form-group">
                        <label for="newClaimCodeInput">
                            Claim Code mới *
                            <button type="button" class="btn-generate" id="btnGenerateNewClaimCode" title="Tự động sinh mã">
                                <i class="bi bi-arrow-clockwise"></i>
                            </button>
                        </label>
                        <input type="text"
                               id="newClaimCodeInput"
                               class="form-control"
                               placeholder="Nhập 6 ký tự"
                               maxlength="6"
                               autocomplete="off"
                               style="text-transform: uppercase;">
                        <small class="form-hint">Mã kích hoạt bảo mật (6 ký tự)</small>
                        <div class="error-message" id="claimCodeError" style="display: none;"></div>
                    </div>
                </div>

                <div class="modal-footer">
                    <button class="btn-cancel">Hủy</button>
                    <button class="btn-primary" id="btnSubmitClaimCode">Xác nhận</button>
                </div>
            </div>
        </div>
    `;

    closeModal();
    document.body.insertAdjacentHTML('beforeend', modalHTML);
    setTimeout(() => {
        document.getElementById('changeClaimCodeModal').classList.add('show');
        document.getElementById('newClaimCodeInput').focus();
    }, 10);

    const btnSubmit = document.getElementById('btnSubmitClaimCode');
    const inputNewCode = document.getElementById('newClaimCodeInput');
    const errorDiv = document.getElementById('claimCodeError');
    const btnGenerate = document.getElementById('btnGenerateNewClaimCode');

    // Auto uppercase
    inputNewCode.addEventListener('input', (e) => {
        e.target.value = e.target.value.toUpperCase();
    });

    // Generate button
    btnGenerate.addEventListener('click', () => {
        inputNewCode.value = generateClaimCode();
        inputNewCode.style.color = '#4CAF50';
        setTimeout(() => {
            inputNewCode.style.color = '';
        }, 1000);
    });

    const handleSubmit = async () => {
        const newCode = inputNewCode.value.trim();

        if (!newCode) {
            showError('Vui lòng nhập Claim Code mới');
            inputNewCode.focus();
            return;
        }

        if (newCode.length !== 6) {
            showError('Claim Code phải có đúng 6 ký tự');
            inputNewCode.focus();
            return;
        }

        if (newCode === currentCode) {
            showError('Claim Code mới phải khác Claim Code hiện tại');
            inputNewCode.focus();
            return;
        }

        try {
            if (firebaseEnabled) {
                await updateData(`devices/${deviceId}/info`, {
                    claimCode: newCode.toUpperCase(),
                    lastModified: Date.now()
                });
            }

            mockDevices[deviceId].info.claimCode = newCode.toUpperCase();
            filteredDevices = { ...mockDevices };

            closeModal();
            renderDeviceTable();
            alert('✅ Đã đổi Claim Code thành công!');
        } catch (error) {
            showError('Lỗi: ' + error.message);
        }
    };

    btnSubmit.addEventListener('click', handleSubmit);
    inputNewCode.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleSubmit();
    });

    function showError(message) {
        errorDiv.textContent = message;
        errorDiv.style.display = 'block';

        setTimeout(() => {
            errorDiv.style.display = 'none';
        }, 3000);
    }
}

/**
 * Xuất PDF với template HTML đầy đủ
 */
function exportDeviceInfo(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const info = device.info || {};
    const deviceName = info.deviceName || 'Thiết bị mới';
    const claimCode = info.claimCode || '------';
    const ownerName = device.ownerName || 'Khách hàng';
    const activationDate = info.createdAt ? new Date(info.createdAt).toLocaleDateString('vi-VN') : new Date().toLocaleDateString('vi-VN');
    const currentDate = new Date().toLocaleString('vi-VN');

    // Tạo HTML template thu gọn (2 trang A4)
    const pdfHTML = `
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <title>Thông tin thiết bị ${deviceId}</title>
    <style>
        @page { size: A4; margin: 15mm; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            line-height: 1.5;
            color: #333;
            font-size: 10pt;
        }
        .container { max-width: 100%; }

        /* Header */
        .header {
            text-align: center;
            border-bottom: 3px solid #2196F3;
            padding-bottom: 10px;
            margin-bottom: 15px;
        }
        .logo { width: 60px; height: 60px; margin: 0 auto 8px; }
        .company-name {
            font-size: 14pt;
            font-weight: bold;
            color: #2196F3;
            margin-bottom: 3px;
        }
        .doc-title {
            font-size: 12pt;
            font-weight: 600;
            color: #555;
            margin-top: 5px;
        }

        /* Sections */
        .section {
            margin-bottom: 12px;
            page-break-inside: avoid;
        }
        .section-title {
            font-size: 11pt;
            font-weight: bold;
            color: #2196F3;
            margin-bottom: 8px;
            padding-bottom: 3px;
            border-bottom: 2px solid #e0e0e0;
        }

        /* Info table */
        .info-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 10px;
        }
        .info-table td {
            padding: 6px;
            vertical-align: top;
            border-bottom: 1px solid #e0e0e0;
        }
        .info-table td:first-child {
            font-weight: 600;
            width: 35%;
            color: #555;
        }
        .info-table td:last-child { color: #333; }
        .highlight {
            background: #fff3cd;
            padding: 2px 6px;
            border-radius: 3px;
            font-weight: bold;
            color: #856404;
            font-family: 'Courier New', monospace;
            font-size: 12pt;
        }

        /* Steps */
        .step {
            margin-bottom: 10px;
        }
        .step-title {
            font-weight: 600;
            color: #2196F3;
            margin-bottom: 4px;
        }
        .step-content {
            margin-left: 15px;
            line-height: 1.6;
        }
        .step-content ul {
            margin: 5px 0 5px 15px;
            padding: 0;
        }
        .step-content li {
            margin-bottom: 3px;
        }

        /* Support box */
        .info-box {
            background: #f8f9fa;
            padding: 10px;
            border-left: 3px solid #2196F3;
            margin: 10px 0;
            font-size: 9.5pt;
        }
        .info-box-title {
            font-weight: bold;
            color: #2196F3;
            margin-bottom: 5px;
        }

        /* Footer */
        .footer {
            margin-top: 20px;
            padding-top: 10px;
            border-top: 2px solid #e0e0e0;
            text-align: center;
            font-size: 8pt;
            color: #777;
        }

        .note {
            background: #fff3cd;
            border-left: 3px solid #ffc107;
            padding: 8px;
            margin: 8px 0;
            font-size: 9pt;
        }

        @media print {
            body { print-color-adjust: exact; -webkit-print-color-adjust: exact; }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <div class="logo">
                <svg width="60" height="60" viewBox="0 0 100 100">
                    <circle cx="50" cy="50" r="45" fill="#2196F3"/>
                    <text x="50" y="65" text-anchor="middle" fill="white" font-size="40" font-weight="bold">AC</text>
                </svg>
            </div>
            <div class="company-name">SMART AC SOLUTIONS</div>
            <div class="doc-title">THÔNG TIN THIẾT BỊ & HƯỚNG DẪN SỬ DỤNG</div>
        </div>

        <!-- I. Thông tin thiết bị -->
        <div class="section">
            <div class="section-title">I. THÔNG TIN THIẾT BỊ</div>
            <table class="info-table">
                <tr>
                    <td>Mã thiết bị (Device ID):</td>
                    <td><strong>${deviceId}</strong></td>
                </tr>
                <tr>
                    <td>Claim Code:</td>
                    <td><span class="highlight">${claimCode}</span></td>
                </tr>
                <tr>
                    <td>Ngày xuất bản:</td>
                    <td>${activationDate}</td>
                </tr>
            </table>
            <div class="note">
                <strong>Lưu ý:</strong> Vui lòng bảo quản Claim Code cẩn thận. Đây là mã bảo mật duy nhất để kích hoạt thiết bị.
            </div>
        </div>

        <!-- II. Hướng dẫn sử dụng -->
        <div class="section">
            <div class="section-title">II. HƯỚNG DẪN KÍCH HOẠT</div>

            <div class="step">
                <div class="step-title">Bước 1: Cấp nguồn cho thiết bị</div>
                <div class="step-content">
                    • Cắm dây điện vào ổ cắm 220V, đèn LED nháy đỏ → Thiết bị sẵn sàng
                </div>
            </div>

            <div class="step">
                <div class="step-title">Bước 2: Kết nối WiFi</div>
                <div class="step-content">
                    <strong>a) Kết nối vào WiFi thiết bị:</strong>
                    <ul>
                        <li>Tìm và kết nối WiFi: <strong>AC-Setup-[số]</strong></li>
                        <li>Mật khẩu: <strong>12345678</strong></li>
                    </ul>
                    <strong>b) Cấu hình:</strong>
                    <ul>
                        <li>Mở trình duyệt, truy cập: <strong>192.168.4.1</strong></li>
                        <li>Nhập Device ID: <strong>${deviceId}</strong></li>
                        <li>Nhập Claim Code: <strong>${claimCode}</strong></li>
                        <li>Chọn WiFi nhà bạn và nhập mật khẩu</li>
                        <li>Nhấn <strong>Lưu và Khởi động</strong></li>
                    </ul>
                    <strong>c) Kiểm tra:</strong> Đèn sáng đỏ liên tục → Thành công ✓
                </div>
            </div>

            <div class="step">
                <div class="step-title">Bước 3: Kích hoạt trên App</div>
                <div class="step-content">
                    <ul>
                        <li>Tải app <strong>"Smart AC Control"</strong> từ CH Play/App Store</li>
                        <li>Đăng ký tài khoản với email và xác thực</li>
                        <li>Đăng nhập → Nhấn "Thêm thiết bị mới"</li>
                        <li>Nhập <strong>Device ID</strong> và <strong>Claim Code</strong></li>
                        <li>Chọn hãng máy lạnh hoặc dùng chức năng "Học lệnh"</li>
                        <li>Hoàn tất và bắt đầu điều khiển</li>
                    </ul>
                </div>
            </div>

            <div class="step">
                <div class="step-title">Bước 4: Reset thiết bị (khi cần)</div>
                <div class="step-content">
                    • Nhấn giữ nút <strong>màu xanh</strong> trong <strong>5 giây</strong> → Đèn nháy 3 lần → Reset thành công
                </div>
            </div>
        </div>

        <!-- III. Thông tin hỗ trợ -->
        <div class="section">
            <div class="section-title">III. HỖ TRỢ & BẢO HÀNH</div>

            <div class="info-box">
                <div class="info-box-title">Hỗ trợ kỹ thuật 24/7:</div>
                📞 Hotline: <strong>0963 840 472</strong> | 📧 Email: <strong>ac_control@gmail.com</strong> | 🌐 <strong>www.smartac.vn</strong>
            </div>

            <div class="info-box">
                <div class="info-box-title">Chính sách bảo hành:</div>
                • Thời hạn: <strong>12 tháng</strong> từ ngày kích hoạt<br>
                • Bảo hành: Lỗi phần cứng, lỗi kỹ thuật do nhà sản xuất<br>
                • Không bảo hành: Hư hỏng do va đập, ngập nước, tự ý sửa chữa<br>
                • Điều kiện: Còn tem bảo hành, có hóa đơn/tài liệu này
            </div>
        </div>

        <!-- IV. Giới thiệu sản phẩm -->
        <div class="section" style="margin-top: 20px;">
            <div class="section-title">IV. SMART AC CONTROL - GIẢI PHÁP ĐIỀU KHIỂN THÔNG MINH</div>

            <div style="margin-bottom: 12px;">
                <strong style="color: #2196F3;">🌟 Tại sao chọn Smart AC Control?</strong>
                <ul style="margin: 8px 0 0 20px; line-height: 1.8;">
                    <li><strong>Tiết kiệm điện năng:</strong> Giảm đến 30% hóa đơn tiền điện với chế độ tự động tắt thông minh</li>
                    <li><strong>Điều khiển từ xa:</strong> Bật/tắt máy lạnh mọi lúc, mọi nơi qua smartphone</li>
                    <li><strong>Lên lịch thông minh:</strong> Đặt lịch bật/tắt tự động theo thói quen của bạn</li>
                    <li><strong>Theo dõi thời gian thực:</strong> Giám sát nhiệt độ, độ ẩm và công suất tiêu thụ</li>
                    <li><strong>Tương thích rộng:</strong> Hỗ trợ hầu hết các dòng máy lạnh phổ biến tại Việt Nam</li>
                </ul>
            </div>

            <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 12px; border-radius: 8px; text-align: center; margin-top: 15px;">
                <strong style="font-size: 11pt;">🎁 ƯU ĐÃI ĐẶC BIỆT</strong><br>
                <span style="font-size: 9.5pt;">Miễn phí 1 năm sử dụng App Premium khi kích hoạt thiết bị trong vòng 30 ngày!</span>
            </div>
        </div>

        <!-- Footer -->
        <div class="footer">
            <div style="margin-bottom: 3px;">
                <strong>Smart AC Solutions</strong> - Ngày xuất bản: ${currentDate}
            </div>
            <div>
                Hotline: 0963 840 472 | Website: www.smartac.vn | © 2025 Smart AC Solutions
            </div>
        </div>
    </div>
</body>
</html>
    `;

    // Mở cửa sổ mới với PDF content
    const printWindow = window.open('', '_blank');
    if (printWindow) {
        printWindow.document.write(pdfHTML);
        printWindow.document.close();

        // Auto print sau khi load xong
        printWindow.onload = () => {
            setTimeout(() => {
                printWindow.print();
            }, 500);
        };
    }

    alert('✅ Đã mở cửa sổ PDF. Bạn có thể in hoặc lưu thành PDF!');
}

/**
 * Xóa thiết bị
 */
async function deleteDevice(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const deviceName = device.info?.deviceName || deviceId;

    if (!confirm(`⚠️ Xóa thiết bị "${deviceName}"?\n\nKhông thể hoàn tác!`)) {
        return;
    }

    try {
        if (firebaseEnabled) {
            await deleteData(`devices/${deviceId}`);
        }

        delete mockDevices[deviceId];
        delete filteredDevices[deviceId];

        // Adjust page if needed
        const totalPages = Math.ceil(Object.keys(filteredDevices).length / devicesPerPage);
        if (currentPage > totalPages && currentPage > 1) {
            currentPage--;
        }

        renderDeviceTable();
        alert('✅ Đã xóa thiết bị!');
    } catch (error) {
        alert('❌ Lỗi: ' + error.message);
    }
}

/**
 * Tạo Device ID ngẫu nhiên (6 ký tự)
 */
function generateDeviceId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let id = '';
    for (let i = 0; i < 6; i++) {
        id += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return id;
}

/**
 * Tạo Claim Code ngẫu nhiên (6 ký tự)
 */
function generateClaimCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Bỏ I, O, 0, 1 để tránh nhầm
    let code = '';
    for (let i = 0; i < 6; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
}

/**
 * Modal thêm thiết bị mới
 */
function showAddDeviceModal() {
    const modalHTML = `
        <div class="modal-overlay" id="addDeviceModal">
            <div class="modal-container small">
                <div class="modal-header">
                    <h2>Thêm thiết bị mới</h2>
                    <button class="modal-close">
                        <i class="bi bi-x-lg"></i>
                    </button>
                </div>

                <div class="modal-body">
                    <div class="form-group">
                        <label for="newDeviceId">
                            Device ID *
                            <button type="button" class="btn-generate" id="btnGenerateDeviceId" title="Tự động sinh mã">
                                <i class="bi bi-arrow-clockwise"></i>
                            </button>
                        </label>
                        <input type="text"
                               id="newDeviceId"
                               class="form-control"
                               placeholder="vd: A3F7K2"
                               autocomplete="off">
                        <small class="form-hint">Mã định danh duy nhất cho thiết bị</small>
                    </div>

                    <div class="form-group">
                        <label for="newClaimCode">
                            Claim Code *
                            <button type="button" class="btn-generate" id="btnGenerateClaimCode" title="Tự động sinh mã">
                                <i class="bi bi-arrow-clockwise"></i>
                            </button>
                        </label>
                        <input type="text"
                               id="newClaimCode"
                               class="form-control"
                               placeholder="6 ký tự"
                               maxlength="6"
                               autocomplete="off"
                               style="text-transform: uppercase;">
                        <small class="form-hint">Mã kích hoạt bảo mật (6 ký tự)</small>
                    </div>

                    <div style="margin: 16px 0;">
                        <button type="button" class="btn-auto-generate" id="btnAutoGenerate">
                            <i class="bi bi-magic"></i>
                            Tự động sinh cả 2 mã
                        </button>
                    </div>

                    <div class="error-message" id="addDeviceError" style="display: none;"></div>
                </div>

                <div class="modal-footer">
                    <button class="btn-cancel">Hủy</button>
                    <button class="btn-primary" id="btnSubmitDevice">Thêm thiết bị</button>
                </div>
            </div>
        </div>
    `;

    document.body.insertAdjacentHTML('beforeend', modalHTML);
    setTimeout(() => {
        document.getElementById('addDeviceModal').classList.add('show');
        document.getElementById('newDeviceId').focus();
    }, 10);

    const btnSubmit = document.getElementById('btnSubmitDevice');
    const inputDeviceId = document.getElementById('newDeviceId');
    const inputClaimCode = document.getElementById('newClaimCode');
    const errorDiv = document.getElementById('addDeviceError');

    // Auto uppercase
    inputClaimCode.addEventListener('input', (e) => {
        e.target.value = e.target.value.toUpperCase();
    });

    const handleSubmit = async () => {
        const deviceId = inputDeviceId.value.trim();
        const claimCode = inputClaimCode.value.trim();

        // Validation
        if (!deviceId) {
            showError('Vui lòng nhập Device ID');
            inputDeviceId.focus();
            return;
        }

        if (!claimCode) {
            showError('Vui lòng nhập Claim Code');
            inputClaimCode.focus();
            return;
        }

        if (claimCode.length !== 6) {
            showError('Claim Code phải có đúng 6 ký tự');
            inputClaimCode.focus();
            return;
        }

        if (mockDevices[deviceId]) {
            showError('Device ID đã tồn tại!');
            inputDeviceId.focus();
            return;
        }

        // Create device with full structure
        const deviceData = {
            info: {
                deviceId: deviceId,
                claimCode: claimCode.toUpperCase(),
                published: true,
                claimed: false,
                owner: null,
                deviceName: "",
                roomName: "",
                macAddress: "",
                firmwareVersion: "",
                createdAt: Date.now(),
                lastModified: Date.now()
            },
            wifi: {
                configured: false,
                ssid: "",
                connected: false,
                signalStrength: 0,
                ip: "",
                lastConnected: 0
            },
            ir: {
                setupCompleted: false,
                method: "",
                library: {
                    brandId: "",
                    selectedAt: 0
                },
                learned: {
                    progress: 0,
                    commands: {
                        power: "",
                        temp_up: "",
                        temp_down: ""
                    }
                }
            },
            settings: {
                autoOffEnabled: true,
                autoOffDelay: 300,
                notifications: true,
                temperatureUnit: "celsius"
            }
        };

        try {
            if (firebaseEnabled) {
                await writeData(`devices/${deviceId}`, deviceData);
            }

            mockDevices[deviceId] = { ...deviceData, status: { online: false } };
            filteredDevices = { ...mockDevices };

            closeModal();
            renderDeviceTable();
            alert('✅ Đã thêm thiết bị thành công!');
        } catch (error) {
            showError('Lỗi: ' + error.message);
        }
    };

    // Event listeners cho nút tự động sinh
    const btnGenerateDeviceId = document.getElementById('btnGenerateDeviceId');
    const btnGenerateClaimCode = document.getElementById('btnGenerateClaimCode');
    const btnAutoGenerate = document.getElementById('btnAutoGenerate');

    btnGenerateDeviceId.addEventListener('click', () => {
        inputDeviceId.value = generateDeviceId();
        inputDeviceId.style.color = '#4CAF50';
        setTimeout(() => {
            inputDeviceId.style.color = '';
        }, 1000);
    });

    btnGenerateClaimCode.addEventListener('click', () => {
        inputClaimCode.value = generateClaimCode();
        inputClaimCode.style.color = '#4CAF50';
        setTimeout(() => {
            inputClaimCode.style.color = '';
        }, 1000);
    });

    btnAutoGenerate.addEventListener('click', () => {
        inputDeviceId.value = generateDeviceId();
        inputClaimCode.value = generateClaimCode();
        inputDeviceId.style.color = '#4CAF50';
        inputClaimCode.style.color = '#4CAF50';
        setTimeout(() => {
            inputDeviceId.style.color = '';
            inputClaimCode.style.color = '';
        }, 1000);
    });

    btnSubmit.addEventListener('click', handleSubmit);
    inputDeviceId.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            inputClaimCode.focus();
        }
    });
    inputClaimCode.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleSubmit();
    });

    function showError(message) {
        errorDiv.textContent = message;
        errorDiv.style.display = 'block';

        setTimeout(() => {
            errorDiv.style.display = 'none';
        }, 3000);
    }
}

/**
 * Cập nhật thống kê
 */
function updateStats() {
    const devices = Object.values(mockDevices);

    // Tổng thiết bị
    const totalElem = document.getElementById('statTotalDevices');
    if (totalElem) {
        totalElem.textContent = devices.length;
    }

    const claimedElem = document.getElementById('statClaimed');
    if (claimedElem) {
        claimedElem.textContent = devices.filter(d => d.info?.claimed).length;
    }

    const onlineElem = document.getElementById('statOnline');
    if (onlineElem) {
        onlineElem.textContent = devices.filter(d => d.status?.online).length;
    }

    const offlineElem = document.getElementById('statOffline');
    if (offlineElem) {
        offlineElem.textContent = devices.filter(d => !d.status?.online).length;
    }

    const unclaimedElem = document.getElementById('statUnclaimed');
    if (unclaimedElem) {
        unclaimedElem.textContent = devices.filter(d => !d.info?.claimed).length;
    }
}

/**
 * Giám sát liên tục
 */
function startMonitoring() {
    setInterval(async () => {
        try {
            const statusData = await readData('status');
            if (statusData) {
                for (const [deviceId, status] of Object.entries(statusData)) {
                    if (mockDevices[deviceId]) {
                        mockDevices[deviceId].status = status;
                        if (filteredDevices[deviceId]) {
                            filteredDevices[deviceId].status = status;
                        }
                    }
                }
                renderDeviceTable();
            }
        } catch (error) {
            console.error('Monitor error:', error);
        }
    }, 15000);
}

// Export functions
export function updateDeviceStats() {
    updateStats();
}

export function initDeviceFilters() {
    // Already initialized in setupEventListeners
}

console.log('✅ Devices Final loaded');
