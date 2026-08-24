const BASE = '/api/v1';

function getToken() { return localStorage.getItem('admin_token'); }

async function request(method, path, body) {
    const opts = { method, headers: { 'Content-Type': 'application/json' } };
    const token = getToken();
    if (token) opts.headers['Authorization'] = 'Bearer ' + token;
    if (body) opts.body = JSON.stringify(body);

    const res = await fetch(BASE + path, opts);
    if (res.status === 401) {
        localStorage.removeItem('admin_token');
        window.location.href = '/admin/login.html';
        throw new Error('未登录');
    }
    let data;
    try {
        data = await res.json();
    } catch (e) {
        // JSON 解析失败：读取实际响应内容以便诊断
        let raw = '';
        try { raw = await res.text(); } catch (_) {}
        const preview = raw.length > 200 ? raw.slice(0, 200) + '...(截断)' : raw;
        console.error('[API] JSON 解析失败', {
            path: path,
            status: res.status,
            contentType: res.headers.get('Content-Type'),
            bodyPreview: preview
        });
        throw new Error('响应不是合法JSON (HTTP ' + res.status + ', ' + (res.headers.get('Content-Type')||'未知') + '): ' + preview);
    }
    if (data.code !== 0) {
        let msg = data.message || '请求失败';
        if (data.code === 40000) msg = '参数错误: ' + msg;
        throw new Error(msg);
    }
    return data;
}

async function uploadFile(method, path, formData) {
    const opts = { method, headers: {} };
    const token = getToken();
    if (token) opts.headers['Authorization'] = 'Bearer ' + token;
    opts.body = formData;

    const res = await fetch(BASE + path, opts);
    if (res.status === 401) {
        localStorage.removeItem('admin_token');
        window.location.href = '/admin/login.html';
        throw new Error('未登录');
    }
    let data;
    try {
        data = await res.json();
    } catch (e) {
        let raw = '';
        try { raw = await res.text(); } catch (_) {}
        const preview = raw.length > 200 ? raw.slice(0, 200) + '...(截断)' : raw;
        console.error('[API Upload] JSON 解析失败', {
            path: path,
            status: res.status,
            contentType: res.headers.get('Content-Type'),
            bodyPreview: preview
        });
        throw new Error('响应不是合法JSON (HTTP ' + res.status + '): ' + preview);
    }
    if (data.code !== 0) {
        throw new Error(data.message || '上传失败');
    }
    return data;
}

const api = {
    get: (path) => request('GET', path),
    post: (path, body) => request('POST', path, body),
    put: (path, body) => request('PUT', path, body),
    del: (path) => request('DELETE', path),
    upload: (path, formData) => uploadFile('POST', path, formData)
};
