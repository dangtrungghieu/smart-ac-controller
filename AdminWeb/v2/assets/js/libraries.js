/**
 * ==============================================
 * LIBRARIES MANAGEMENT MODULE
 * ==============================================
 * Quản lý thư viện máy lạnh: Thêm, sửa, xóa
 */

import { readData, writeData, updateData, deleteData, firebaseEnabled } from './firebase.js';

// Mock data thư viện
let mockLibraries = {};
let filteredLibraries = {};
let currentPage = 1;
const librariesPerPage = 5;

/**
 * Khởi tạo module Libraries
 */
export async function initLibraries() {
    console.log('📚 Khởi tạo module Libraries...');

    // Load dữ liệu thư viện
    await loadLibraries();

    // Gắn sự kiện nút "Thêm thư viện"
    document.getElementById('btnAddLibrary').addEventListener('click', showAddLibraryModal);

    // Render bảng thư viện
    renderLibraryTable();
}

/**
 * Load danh sách thư viện từ Firebase hoặc mock data
 */
async function loadLibraries() {
    try {
        console.log('🔄 Đang load thư viện từ Firebase...');
        const data = await readData('ir_library');

        if (data && Object.keys(data).length > 0) {
            mockLibraries = data;
            console.log('✅ Đã load thư viện từ Firebase:', Object.keys(data).length, 'thư viện');
        } else {
            console.log('⚠️ Không có dữ liệu thư viện, dùng mock data');
            mockLibraries = generateMockLibraries();
        }
    } catch (error) {
        console.error('❌ Lỗi khi load thư viện:', error);
        mockLibraries = generateMockLibraries();
    }
}

/**
 * Tạo dữ liệu thư viện mẫu
 */
function generateMockLibraries() {
    return {
        daikin_001: {
            name: 'Daikin FTXS Series',
            brand: 'Daikin',
            model: 'FTXS-25GVMV',
            description: 'Inverter cao cấp, tiết kiệm điện',
            protocol: 'IR_PROTOCOL_DAIKIN',
            popular: true,
            tested: true
        },
        panasonic_001: {
            name: 'Panasonic Inverter',
            brand: 'Panasonic',
            model: 'CU/CS-PU12UKH-8',
            description: 'Làm lạnh nhanh, êm ái',
            protocol: 'IR_PROTOCOL_PANASONIC',
            popular: true,
            tested: true
        },
        lg_001: {
            name: 'LG Dual Inverter',
            brand: 'LG',
            model: 'V13API',
            description: 'Công nghệ Dual Inverter độc quyền',
            protocol: 'IR_PROTOCOL_LG',
            popular: true,
            tested: false
        },
        mitsubishi_001: {
            name: 'Mitsubishi Heavy',
            brand: 'Mitsubishi',
            model: 'SRK/SRC13YL-S5',
            description: 'Bền bỉ, chất lượng Nhật Bản',
            protocol: 'IR_PROTOCOL_MITSUBISHI',
            popular: false,
            tested: true
        }
    };
}

/**
 * Render bảng thư viện với pagination
 */
export function renderLibraryTable() {
    const tbody = document.getElementById('librariesTableBody');
    if (!tbody) return;

    if (Object.keys(mockLibraries).length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center">Chưa có thư viện nào</td></tr>';
        renderLibraryPagination(0, 0);
        return;
    }

    // Áp dụng filter
    filteredLibraries = filterLibraries();
    const libraries = Object.entries(filteredLibraries);
    const totalLibraries = libraries.length;
    const totalPages = Math.ceil(totalLibraries / librariesPerPage);

    if (totalLibraries === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center">Không tìm thấy thư viện nào phù hợp</td></tr>';
        renderLibraryPagination(0, 0);
        return;
    }

    // Tính toán libraries cho trang hiện tại
    const startIndex = (currentPage - 1) * librariesPerPage;
    const endIndex = startIndex + librariesPerPage;
    const currentLibraries = libraries.slice(startIndex, endIndex);

    let html = '';
    let rowNum = startIndex + 1;

    for (const [libId, lib] of currentLibraries) {
        // Tên thư viện từ protocol, Hãng từ name, Model từ class
        const libraryName = lib.protocol || libId;
        const brand = lib.name || '--';
        const modelCode = lib.class || '--';
        const logo = getACBrandLogo(brand);

        html += `
            <tr>
                <td>${rowNum++}</td>
                <td style="text-align: center; font-size: 24px;">${logo}</td>
                <td><strong>${libraryName}</strong></td>
                <td>${brand}</td>
                <td><code>${modelCode}</code></td>
                <td>${lib.description || '--'}</td>
                <td>
                    <button class="btn btn-sm btn-danger" onclick="window.libraryModule.deleteLibrary('${libId}')"><i class="bi bi-trash"></i> Xóa</button>
                </td>
            </tr>
        `;
    }

    tbody.innerHTML = html;
    renderLibraryPagination(totalLibraries, totalPages);

    // Cập nhật stats
    if (window.updateLibraryStats) {
        window.updateLibraryStats();
    }
}

/**
 * Render phân trang cho libraries
 */
function renderLibraryPagination(totalLibraries, totalPages) {
    const container = document.getElementById('librariesPagination');
    if (!container) return;

    if (totalPages <= 1) {
        container.innerHTML = '';
        return;
    }

    let html = '<div class="pagination-wrapper">';
    html += '<div class="pagination-info">Hiển thị ' +
            ((currentPage - 1) * librariesPerPage + 1) + '-' +
            Math.min(currentPage * librariesPerPage, totalLibraries) +
            ' trong tổng ' + totalLibraries + ' thư viện</div>';

    html += '<div class="pagination">';

    // Previous button
    html += `
        <button class="page-btn prev ${currentPage === 1 ? 'disabled' : ''}"
                data-page="${currentPage - 1}"
                onclick="window.libraryModule.goToPage(${currentPage - 1})"
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
                        onclick="window.libraryModule.goToPage(${i})">
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
                onclick="window.libraryModule.goToPage(${currentPage + 1})"
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
    const totalPages = Math.ceil(Object.keys(filteredLibraries).length / librariesPerPage);
    if (page < 1 || page > totalPages) return;

    currentPage = page;
    renderLibraryTable();

    // Scroll to top of table
    document.getElementById('librariesTable')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/**
 * Get logo emoji cho các hãng máy lạnh
 */
function getACBrandLogo(brandName) {
    const brand = brandName.toLowerCase();

    if (brand.includes('daikin')) return '🌀';
    if (brand.includes('panasonic')) return '⚡';
    if (brand.includes('lg')) return '❄️';
    if (brand.includes('samsung')) return '🔷';
    if (brand.includes('mitsubishi')) return '💎';
    if (brand.includes('toshiba')) return '🌟';
    if (brand.includes('sharp')) return '🔶';
    if (brand.includes('hitachi')) return '⭐';
    if (brand.includes('carrier')) return '🏔️';
    if (brand.includes('gree')) return '🍃';

    return '❄️'; // Default AC icon
}

/**
 * Hiển thị modal thêm thư viện
 */
function showAddLibraryModal() {
    const modalHTML = `
        <div class="modal show" id="addLibraryModal">
            <div class="modal-content">
                <div class="modal-header">
                    <h3 class="modal-title">➕ Thêm thư viện máy lạnh</h3>
                    <button class="modal-close" id="closeAddLibrary">&times;</button>
                </div>
                <div class="modal-body">
                    <form id="addLibraryForm">
                        <div class="form-group">
                            <label>ID thư viện *</label>
                            <input type="text" id="newLibraryId" class="form-control" placeholder="daikin_001" required>
                        </div>

                        <div class="form-group">
                            <label>Tên thư viện *</label>
                            <input type="text" id="newLibraryName" class="form-control" placeholder="Daikin FTXS Series" required>
                        </div>

                        <div class="form-group">
                            <label>Hãng *</label>
                            <input type="text" id="newLibraryBrand" class="form-control" placeholder="Daikin" required>
                        </div>

                        <div class="form-group">
                            <label>Mã Model</label>
                            <input type="text" id="newLibraryModel" class="form-control" placeholder="FTXS-25GVMV">
                        </div>

                        <div class="form-group">
                            <label>Mô tả</label>
                            <textarea id="newLibraryDescription" class="form-control" rows="3" placeholder="Mô tả chi tiết về dòng máy..."></textarea>
                        </div>

                        <div id="addLibraryError" class="error-message" style="display: none; margin-top: 12px;">
                        </div>
                    </form>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary" id="btnCancelAddLibrary">Hủy</button>
                    <button class="btn btn-primary" id="btnSaveLibrary">💾 Lưu thư viện</button>
                </div>
            </div>
        </div>
    `;

    const container = document.getElementById('modalContainer');
    container.innerHTML = modalHTML;

    // Gắn sự kiện
    document.getElementById('closeAddLibrary').onclick = () => document.getElementById('addLibraryModal').remove();
    document.getElementById('btnCancelAddLibrary').onclick = () => document.getElementById('addLibraryModal').remove();
    document.getElementById('btnSaveLibrary').onclick = saveNewLibrary;
}

/**
 * Lưu thư viện mới
 */
async function saveNewLibrary() {
    const libId = document.getElementById('newLibraryId').value.trim();
    const name = document.getElementById('newLibraryName').value.trim();
    const brand = document.getElementById('newLibraryBrand').value.trim();
    const model = document.getElementById('newLibraryModel').value.trim();
    const description = document.getElementById('newLibraryDescription').value.trim();

    const errorDiv = document.getElementById('addLibraryError');

    // Validate
    if (!libId || !name || !brand) {
        errorDiv.textContent = '❌ Vui lòng điền đầy đủ các trường bắt buộc!';
        errorDiv.style.display = 'block';
        return;
    }

    // Kiểm tra trùng ID
    if (mockLibraries[libId]) {
        errorDiv.textContent = `❌ ID thư viện "${libId}" đã tồn tại!`;
        errorDiv.style.display = 'block';
        return;
    }

    // Tạo dữ liệu thư viện
    const libraryData = {
        name: name,
        brand: brand,
        model: model,
        description: description,
        protocol: `IR_PROTOCOL_${brand.toUpperCase()}`,
        popular: false,
        tested: false,
        createdAt: Date.now()
    };

    try {
        // Lưu vào Firebase
        if (firebaseEnabled) {
            await writeData(`ir_library/${libId}`, libraryData);
        }

        mockLibraries[libId] = libraryData;

        // Đóng modal
        document.getElementById('addLibraryModal').remove();

        // Render lại bảng
        renderLibraryTable();

        alert(`✅ Đã thêm thư viện "${name}" thành công!`);

    } catch (error) {
        errorDiv.textContent = '❌ Lỗi khi lưu thư viện: ' + error.message;
        errorDiv.style.display = 'block';
    }
}

/**
 * Sửa thư viện
 */
function editLibrary(libId) {
    alert(`Chức năng sửa thư viện "${libId}" đang được phát triển...`);
    // TODO: Implement edit library modal
}

/**
 * Xóa thư viện
 */
async function deleteLibrary(libId) {
    const library = mockLibraries[libId];
    if (!library) return;

    const libraryName = library.name || libId;

    if (!confirm(`⚠️ Bạn có chắc muốn xóa thư viện "${libraryName}"?\n\nHành động này không thể hoàn tác!`)) {
        return;
    }

    try {
        // Xóa từ Firebase
        if (firebaseEnabled) {
            await deleteData(`ir_library/${libId}`);
        }

        // Xóa từ mock data
        delete mockLibraries[libId];

        // Render lại bảng
        renderLibraryTable();

        alert(`✅ Đã xóa thư viện "${libraryName}" thành công!`);

    } catch (error) {
        alert('❌ Lỗi khi xóa thư viện: ' + error.message);
    }
}

// Export để gọi từ ngoài
window.libraryModule = {
    editLibrary,
    deleteLibrary,
    goToPage
};

/**
 * ==================== FILTER & SEARCH ====================
 */

// Biến lưu trạng thái filter
let libraryFilters = {
    searchText: ''
};

/**
 * Khởi tạo filter events
 */
export function initLibraryFilters() {
    const searchInput = document.getElementById('librarySearchInput');
    const resetBtn = document.getElementById('btnResetLibraryFilter');

    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            libraryFilters.searchText = e.target.value.toLowerCase().trim();
            renderLibraryTable();
        });
    }

    if (resetBtn) {
        resetBtn.addEventListener('click', () => {
            libraryFilters = { searchText: '' };
            if (searchInput) searchInput.value = '';
            currentPage = 1;
            renderLibraryTable();
        });
    }
}

/**
 * Lọc libraries theo điều kiện
 */
function filterLibraries() {
    let filtered = Object.entries(mockLibraries);

    // Lọc theo text search
    if (libraryFilters.searchText) {
        filtered = filtered.filter(([libId, lib]) => {
            const libraryName = (lib.protocol || libId).toLowerCase();
            const brand = (lib.name || '').toLowerCase();
            const modelCode = (lib.class || '').toLowerCase();
            const searchText = libraryFilters.searchText;

            return libraryName.includes(searchText) ||
                   brand.includes(searchText) ||
                   modelCode.includes(searchText);
        });
    }

    return Object.fromEntries(filtered);
}
