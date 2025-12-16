/**
 * ==============================================
 * FIREBASE CONFIGURATION & INITIALIZATION
 * ==============================================
 * File này chứa cấu hình Firebase và các hàm tiện ích
 * để kết nối với Firebase Realtime Database
 */

// Firebase Configuration - Dùng REST API thay vì SDK để bypass Rules
const FIREBASE_URL = "https://ac-control-db-default-rtdb.asia-southeast1.firebasedatabase.app";
const DATABASE_SECRET = "TSVCjAw2PJWDSofxbJwNwU3fXr5fXXs4T18VHDwa"; // Database Secret (Legacy token)

// Biến cờ kiểm tra Firebase có được kích hoạt không
let firebaseEnabled = true; // Luôn true vì dùng REST API

/**
 * Khởi tạo Firebase - Dùng REST API thay vì SDK
 */
async function initializeFirebase() {
    try {
        // Test kết nối bằng cách fetch một path đơn giản
        const testUrl = `${FIREBASE_URL}/.json?auth=${DATABASE_SECRET}`;
        const response = await fetch(testUrl);

        if (response.ok) {
            firebaseEnabled = true;
            console.log('✅ Firebase REST API đã kết nối thành công');
            console.log('📍 Database URL:', FIREBASE_URL);
            return true;
        } else {
            throw new Error('Không thể kết nối Firebase');
        }
    } catch (error) {
        console.error('❌ Lỗi khởi tạo Firebase:', error);
        firebaseEnabled = false;
        return false;
    }
}

/**
 * Đọc dữ liệu từ Firebase bằng REST API
 * @param {string} path - Đường dẫn đến dữ liệu (vd: 'devices', 'users')
 * @returns {Promise<any>} - Dữ liệu từ Firebase hoặc null nếu lỗi
 */
async function readData(path) {
    if (!firebaseEnabled) {
        console.warn('Firebase chưa được kích hoạt, trả về null');
        return null;
    }

    try {
        const url = `${FIREBASE_URL}/${path}.json?auth=${DATABASE_SECRET}`;
        const response = await fetch(url);

        if (response.ok) {
            const data = await response.json();
            if (data) {
                console.log(`✅ Đọc dữ liệu từ /${path}:`, Object.keys(data || {}).length, 'items');
                return data;
            } else {
                console.log(`⚠️ Không có dữ liệu tại path: /${path}`);
                return null;
            }
        } else {
            console.error(`❌ Lỗi HTTP ${response.status} khi đọc /${path}`);
            return null;
        }
    } catch (error) {
        console.error(`❌ Lỗi khi đọc dữ liệu từ ${path}:`, error);
        return null;
    }
}

/**
 * Ghi dữ liệu vào Firebase bằng REST API
 * @param {string} path - Đường dẫn
 * @param {any} data - Dữ liệu cần ghi
 * @returns {Promise<boolean>} - true nếu thành công, false nếu lỗi
 */
async function writeData(path, data) {
    if (!firebaseEnabled) {
        console.warn('Firebase chưa được kích hoạt');
        return false;
    }

    try {
        const url = `${FIREBASE_URL}/${path}.json?auth=${DATABASE_SECRET}`;
        const response = await fetch(url, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });

        if (response.ok) {
            console.log(`✅ Đã ghi dữ liệu vào /${path}`);
            return true;
        } else {
            console.error(`❌ Lỗi HTTP ${response.status} khi ghi /${path}`);
            return false;
        }
    } catch (error) {
        console.error(`❌ Lỗi khi ghi dữ liệu vào ${path}:`, error);
        return false;
    }
}

/**
 * Cập nhật dữ liệu trong Firebase bằng REST API
 * @param {string} path - Đường dẫn
 * @param {any} data - Dữ liệu cần cập nhật (chỉ update các field được chỉ định)
 * @returns {Promise<boolean>}
 */
async function updateData(path, data) {
    if (!firebaseEnabled) {
        console.warn('Firebase chưa được kích hoạt');
        return false;
    }

    try {
        const url = `${FIREBASE_URL}/${path}.json?auth=${DATABASE_SECRET}`;
        const response = await fetch(url, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });

        if (response.ok) {
            console.log(`✅ Đã cập nhật dữ liệu tại /${path}`);
            return true;
        } else {
            console.error(`❌ Lỗi HTTP ${response.status} khi cập nhật /${path}`);
            return false;
        }
    } catch (error) {
        console.error(`❌ Lỗi khi cập nhật dữ liệu tại ${path}:`, error);
        return false;
    }
}

/**
 * Xóa dữ liệu từ Firebase bằng REST API
 * @param {string} path - Đường dẫn
 * @returns {Promise<boolean>}
 */
async function deleteData(path) {
    if (!firebaseEnabled) {
        console.warn('Firebase chưa được kích hoạt');
        return false;
    }

    try {
        const url = `${FIREBASE_URL}/${path}.json?auth=${DATABASE_SECRET}`;
        const response = await fetch(url, {
            method: 'DELETE'
        });

        if (response.ok) {
            console.log(`✅ Đã xóa dữ liệu tại /${path}`);
            return true;
        } else {
            console.error(`❌ Lỗi HTTP ${response.status} khi xóa /${path}`);
            return false;
        }
    } catch (error) {
        console.error(`❌ Lỗi khi xóa dữ liệu tại ${path}:`, error);
        return false;
    }
}

/**
 * Lắng nghe thay đổi dữ liệu realtime - KHÔNG hỗ trợ với REST API
 * REST API không có realtime updates, cần polling hoặc dùng Firebase SDK
 */
async function listenData(path, callback) {
    console.warn('⚠️ REST API không hỗ trợ realtime updates. Dùng polling thay thế.');

    // Polling mỗi 5 giây
    setInterval(async () => {
        const data = await readData(path);
        callback(data);
    }, 5000);
}

// Export các hàm để sử dụng ở file khác
export {
    initializeFirebase,
    readData,
    writeData,
    updateData,
    deleteData,
    listenData,
    firebaseEnabled
};
