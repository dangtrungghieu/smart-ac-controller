/**
 * ==============================================
 * DEVICES MANAGEMENT MODULE V2
 * ==============================================
 * Phiên bản mới - đơn giản và hiệu quả hơn
 */

import { readData, writeData, updateData, deleteData, firebaseEnabled } from './firebase.js';

let mockDevices = {};

/**
 * Khởi tạo module
 */
export async function initDevices() {
    console.log('📱 Khởi tạo Devices Module V2...');

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
        } else {
            console.log('⚠️ Không có dữ liệu');
            mockDevices = {};
        }
    } catch (error) {
        console.error('❌ Lỗi load devices:', error);
        mockDevices = {};
    }
}

/**
 * Setup event listeners
 */
function setupEventListeners() {
    console.log('🔗 Setup event listeners...');

    // Nút thêm thiết bị
    document.getElementById('btnAddDevice')?.addEventListener('click', showAddDeviceModal);

    // Delegate events trên document
    document.addEventListener('click', handleClick);

    console.log('✅ Event listeners ready');
}

/**
 * Xử lý tất cả click events
 */
function handleClick(e) {
    // Nút 3 chấm - mở menu
    if (e.target.closest('.btn-device-menu')) {
        const btn = e.target.closest('.btn-device-menu');
        const deviceId = btn.dataset.deviceId;
        toggleMenu(deviceId);
        return;
    }

    // Các nút action
    if (e.target.closest('[data-device-action]')) {
        const btn = e.target.closest('[data-device-action]');
        const action = btn.dataset.deviceAction;
        const deviceId = btn.dataset.deviceId;

        console.log('🎯 Action:', action, 'Device:', deviceId);
        executeAction(action, deviceId);
        return;
    }

    // Click ngoài menu - đóng menu
    if (!e.target.closest('.device-menu-popup')) {
        closeAllMenus();
    }
}

/**
 * Toggle menu
 */
function toggleMenu(deviceId) {
    const menu = document.getElementById(`menu-${deviceId}`);
    if (!menu) return;

    const isOpen = menu.style.display === 'block';

    // Đóng tất cả menu khác
    closeAllMenus();

    // Toggle menu hiện tại
    if (!isOpen) {
        menu.style.display = 'block';
        console.log('📂 Menu opened:', deviceId);
    }
}

/**
 * Đóng tất cả menu
 */
function closeAllMenus() {
    document.querySelectorAll('.device-menu-popup').forEach(menu => {
        menu.style.display = 'none';
    });
}

/**
 * Thực thi action
 */
function executeAction(action, deviceId) {
    closeAllMenus();

    switch(action) {
        case 'changeClaimCode':
            changeClaimCode(deviceId);
            break;
        case 'exportInfo':
            exportDeviceInfo(deviceId);
            break;
        case 'delete':
            deleteDevice(deviceId);
            break;
        default:
            console.error('Unknown action:', action);
    }
}

/**
 * Render bảng thiết bị
 */
export function renderDeviceTable() {
    const tbody = document.getElementById('devicesTableBody');
    if (!tbody) return;

    if (Object.keys(mockDevices).length === 0) {
        tbody.innerHTML = '<tr><td colspan="11" class="text-center">Chưa có thiết bị</td></tr>';
        return;
    }

    let html = '';
    let index = 1;

    for (const [deviceId, device] of Object.entries(mockDevices)) {
        const info = device.info || {};
        const status = device.status || {};

        const deviceName = info.deviceName?.trim() || '...';
        const ownerName = device.ownerName || '...';
        const isOnline = status.online === true;

        html += `
            <tr>
                <td>${index++}</td>
                <td><strong>${deviceName}</strong></td>
                <td><code>${deviceId}</code></td>
                <td>${ownerName}</td>
                <td>
                    <span class="claim-code-hidden" id="claim-${deviceId}">••••••</span>
                    <button class="btn-icon" onclick="window.deviceModule.toggleClaimCode('${deviceId}')">
                        <i class="bi bi-eye" id="eye-${deviceId}"></i>
                    </button>
                </td>
                <td>
                    <span class="status-badge ${isOnline ? 'status-online' : 'status-offline'}">
                        ${isOnline ? '🟢 Online' : '🔴 Offline'}
                    </span>
                </td>
                <td><span class="sensor-badge ${isOnline ? 'sensor-online' : 'sensor-offline'}">${isOnline ? '✅' : '❌'}</span></td>
                <td><span class="sensor-badge sensor-offline">❌</span></td>
                <td><span class="sensor-badge sensor-offline">❌</span></td>
                <td><span class="sensor-badge sensor-offline">❌</span></td>
                <td style="position: relative;">
                    <button class="btn-icon btn-device-menu" data-device-id="${deviceId}">
                        <i class="bi bi-three-dots-vertical"></i>
                    </button>
                    <div class="device-menu-popup" id="menu-${deviceId}" style="display: none;">
                        <div class="menu-header">
                            <strong>${deviceName}</strong>
                            <code>${deviceId}</code>
                        </div>
                        <button class="menu-item" data-device-action="changeClaimCode" data-device-id="${deviceId}">
                            <i class="bi bi-key"></i>
                            <span>Đổi Claim Code</span>
                        </button>
                        <button class="menu-item" data-device-action="exportInfo" data-device-id="${deviceId}">
                            <i class="bi bi-file-earmark-pdf"></i>
                            <span>Xuất PDF</span>
                        </button>
                        <button class="menu-item danger" data-device-action="delete" data-device-id="${deviceId}">
                            <i class="bi bi-trash"></i>
                            <span>Xóa thiết bị</span>
                        </button>
                    </div>
                </td>
            </tr>
        `;
    }

    tbody.innerHTML = html;
    updateStats();
}

/**
 * Toggle hiển thị claim code
 */
function toggleClaimCode(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const span = document.getElementById(`claim-${deviceId}`);
    const icon = document.getElementById(`eye-${deviceId}`);
    const claimCode = device.info?.claimCode || '------';

    if (span.textContent === '••••••') {
        span.textContent = claimCode;
        span.style.color = '#2196F3';
        span.style.fontWeight = 'bold';
        icon.className = 'bi bi-eye-slash';

        setTimeout(() => {
            span.textContent = '••••••';
            span.style.color = '';
            span.style.fontWeight = '';
            icon.className = 'bi bi-eye';
        }, 5000);
    } else {
        span.textContent = '••••••';
        span.style.color = '';
        span.style.fontWeight = '';
        icon.className = 'bi bi-eye';
    }
}

/**
 * Đổi claim code
 */
async function changeClaimCode(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const newCode = prompt('Nhập Claim Code mới (6 ký tự):', device.info?.claimCode || '');
    if (!newCode) return;

    if (newCode.length !== 6) {
        alert('❌ Claim Code phải có 6 ký tự!');
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
        renderDeviceTable();
        alert('✅ Đã đổi Claim Code thành công!');
    } catch (error) {
        alert('❌ Lỗi: ' + error.message);
    }
}

/**
 * Xuất PDF
 */
function exportDeviceInfo(deviceId) {
    const device = mockDevices[deviceId];
    if (!device) return;

    const { jsPDF } = window.jspdf;
    const doc = new jsPDF();

    const claimCode = device.info?.claimCode || '------';
    const deviceName = device.info?.deviceName || deviceId;

    // Header
    doc.setFontSize(24);
    doc.setFont('helvetica', 'bold');
    doc.text('SMART AC', 105, 30, { align: 'center' });

    doc.setFontSize(16);
    doc.text('THONG TIN THIET BI', 105, 50, { align: 'center' });

    // Body
    doc.setFontSize(12);
    doc.text('Device ID:', 30, 80);
    doc.setFont('helvetica', 'bold');
    doc.text(deviceId, 30, 90);

    doc.setFont('helvetica', 'normal');
    doc.text('Claim Code:', 30, 110);
    doc.setFontSize(20);
    doc.setFont('helvetica', 'bold');
    doc.setTextColor(255, 0, 0);
    doc.text(claimCode, 30, 125);

    // Footer
    doc.setFontSize(10);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(0, 0, 0);
    doc.text(`Ngay tao: ${new Date().toLocaleString('vi-VN')}`, 105, 270, { align: 'center' });

    doc.save(`Device_${deviceId}.pdf`);
    alert('✅ Đã xuất PDF thành công!');
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
        renderDeviceTable();
        alert('✅ Đã xóa thiết bị!');
    } catch (error) {
        alert('❌ Lỗi: ' + error.message);
    }
}

/**
 * Thêm thiết bị mới
 */
function showAddDeviceModal() {
    const deviceId = prompt('Nhập Device ID (vd: dv_01):');
    if (!deviceId) return;

    const claimCode = prompt('Nhập Claim Code (6 ký tự):');
    if (!claimCode || claimCode.length !== 6) {
        alert('❌ Claim Code phải có 6 ký tự!');
        return;
    }

    if (mockDevices[deviceId]) {
        alert('❌ Device ID đã tồn tại!');
        return;
    }

    const newDevice = {
        info: {
            deviceId: deviceId,
            claimCode: claimCode.toUpperCase(),
            published: true,
            claimed: false,
            deviceName: '',
            createdAt: Date.now()
        }
    };

    mockDevices[deviceId] = newDevice;

    if (firebaseEnabled) {
        writeData(`devices/${deviceId}`, newDevice);
    }

    renderDeviceTable();
    alert('✅ Đã thêm thiết bị!');
}

/**
 * Cập nhật thống kê
 */
function updateStats() {
    const devices = Object.values(mockDevices);

    document.getElementById('statClaimed').textContent = devices.filter(d => d.info?.claimed).length;
    document.getElementById('statOnline').textContent = devices.filter(d => d.status?.online).length;
    document.getElementById('statOffline').textContent = devices.filter(d => !d.status?.online).length;
    document.getElementById('statUnclaimed').textContent = devices.filter(d => !d.info?.claimed).length;
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
    // Placeholder
}

// Global access
window.deviceModule = {
    initDevices,
    renderDeviceTable,
    updateDeviceStats,
    initDeviceFilters,
    toggleClaimCode
};

console.log('✅ Devices V2 loaded');
