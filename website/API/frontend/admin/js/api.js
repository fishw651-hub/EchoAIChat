const BASE = '/api/v1';

function getToken() { return localStorage.getItem('admin_token'); }

async function request(method, path, body) {
    const opts = {
        method,
        headers: { 'Content-Type': 'application/json' }
    };
    const token = getToken();
    if (token) opts.headers['Authorization'] = 'Bearer ' + token;
    if (body) opts.body = JSON.stringify(body);

    const res = await fetch(BASE + path, opts);
    if (res.status === 401) {
        localStorage.removeItem('admin_token');
        window.location.href = 'login.html';
        throw new Error('未登录');
    }
    if (res.headers.get('content-type')?.includes('text/event-stream')) return res;

    const data = await res.json();
    if (data.code !== 0) {
        let msg = data.message || '请求失败';
        if (data.code === 40000) msg = '参数错误: ' + msg;
        throw new Error(msg);
    }
    return data;
}

const api = {
    get: (path) => request('GET', path),
    post: (path, body) => request('POST', path, body),
    put: (path, body) => request('PUT', path, body),
    del: (path) => request('DELETE', path)
};
