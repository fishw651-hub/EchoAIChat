var _currentPage = 1, _pageSize = 15;
var _dashboardRange = 30;

const ADMIN_ICON_PATHS = {
    dashboard: '<path d="M4 19V9m5 10V5m5 14v-7m5 7V3"/>',
    users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    orders: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6"/>',
    network: '<circle cx="12" cy="12" r="3"/><circle cx="5" cy="6" r="2"/><circle cx="19" cy="6" r="2"/><path d="m7 7 3 3m7-3-3 3M5 17l5-3m9 3-5-3"/>',
    versions: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
    activities: '<path d="m12 3 1.8 4.2L18 9l-4.2 1.8L12 15l-1.8-4.2L6 9l4.2-1.8L12 3Z"/><path d="m19 15 .9 2.1L22 18l-2.1.9L19 21l-.9-2.1L16 18l2.1-.9L19 15Z"/>',
    announcements: '<path d="m3 11 18-5v12L3 14v-3Z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>',
    feedback: '<path d="M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4v8Z"/><path d="M8 9h8M8 13h5"/>',
    pricing: '<circle cx="12" cy="12" r="9"/><path d="M16 8h-6a2 2 0 0 0 0 4h4a2 2 0 0 1 0 4H8m4-10v12"/>',
    plans: '<path d="M4 7h16v13H4zM2 4h20v3H2zM12 4v16"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H3v-4h.1a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6V3h4v.1a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>',
    mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
    domain: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    security: '<path d="M12 3 4 6v6c0 5 3.4 8 8 9 4.6-1 8-4 8-9V6l-8-3Z"/><path d="m9 12 2 2 4-5"/>',
    audit: '<path d="M7 3h10v4H7zM5 5H4v16h16V5h-1"/><path d="M8 12h8M8 16h5"/>',
    docs: '<path d="M4 4h6a3 3 0 0 1 3 3v13a3 3 0 0 0-3-3H4V4Zm16 0h-6a3 3 0 0 0-3 3v13a3 3 0 0 1 3-3h6V4Z"/>',
    password: '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    bot: '<rect x="4" y="7" width="16" height="12" rx="3"/><path d="M12 3v4M8 12h.01M16 12h.01M9 16h6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    trend: '<path d="m3 17 6-6 4 4 8-9"/><path d="M15 6h6v6"/>',
    wallet: '<path d="M3 6h16a2 2 0 0 1 2 2v10H5a2 2 0 0 1-2-2V6Z"/><path d="M3 6V5a2 2 0 0 1 2-2h13v3M16 12h5"/>',
    spark: '<path d="m12 3 1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5L12 3Z"/>'
};

function iconSvg(name) {
    const path = ADMIN_ICON_PATHS[name] || ADMIN_ICON_PATHS.spark;
    return `<svg viewBox="0 0 24 24" aria-hidden="true">${path}</svg>`;
}

function setSidebarOpen(open) {
    const sidebar = document.getElementById('sidebar');
    const toggle = document.getElementById('mobileToggle');
    const scrim = document.getElementById('sidebarScrim');
    sidebar.classList.toggle('open', open);
    scrim.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
}

// TODO: 后续引入 i18n 字典支持多语言（当前全站硬编码中文）

if (!localStorage.getItem('admin_token')) { window.location.href = '/admin/login.html'; }

window.addEventListener('load', () => {
    document.getElementById('adminName').textContent = localStorage.getItem('admin_name') || 'Admin';
    document.querySelectorAll('[data-admin-icon]').forEach(el => { el.innerHTML = iconSvg(el.dataset.adminIcon); });
    document.querySelectorAll('.sidebar-nav a').forEach(a => a.addEventListener('click', navClick));
    document.getElementById('btnLogout').addEventListener('click', logout);
    document.getElementById('mobileToggle').addEventListener('click', () => setSidebarOpen(!document.getElementById('sidebar').classList.contains('open')));
    document.getElementById('sidebarScrim').addEventListener('click', () => setSidebarOpen(false));
    document.getElementById('aiReviewSave').addEventListener('click', saveAiReviewConfig);
    // AI 审核按钮（data-ai-review + data-id）事件委托
    ['networkAgentTableBody', 'networkGroupTableBody'].forEach(tbid => {
        document.getElementById(tbid).addEventListener('click', (e) => {
            const btn = e.target.closest('button[data-ai-review]');
            if (btn) runAiReview(btn.dataset.aiReview, btn.dataset.id, btn);
        });
    });
    // 模型定价行内按钮（data-action + data-id）事件委托
    document.getElementById('modelTableBody').addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;
        if (btn.dataset.action === 'edit-model') editPriceById(parseInt(btn.dataset.id, 10));
        else if (btn.dataset.action === 'toggle-model') toggleModelStatus(parseInt(btn.dataset.id, 10));
        else if (btn.dataset.action === 'delete-model') deleteModelPrice(parseInt(btn.dataset.id, 10));
    });
    // 公告管理行内按钮（data-ann-action + data-id）事件委托
    document.getElementById('announcementTableBody').addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-ann-action]');
        if (!btn) return;
        const id = parseInt(btn.dataset.id, 10);
        if (btn.dataset.annAction === 'edit') editAnnouncement(id);
        else if (btn.dataset.annAction === 'delete') deleteAnnouncement(id);
    });
    // 添加模型：拉取远程模型 / 选中填充模型 ID / Key 明文切换
    document.getElementById('modelAddFetchBtn').addEventListener('click', fetchRemoteModels);
    document.getElementById('modelAddModelSelect').addEventListener('change', (e) => {
        if (e.target.value) $('modelAddId').value = e.target.value;
    });
    document.getElementById('modelAddKeyToggle').addEventListener('click', () => {
        const input = $('modelAddKey'), btn = $('modelAddKeyToggle');
        input.type = input.type === 'password' ? 'text' : 'password';
        btn.textContent = input.type === 'password' ? '显示' : '隐藏';
    });
    // 编辑模型：站点 Key 明文切换
    document.getElementById('priceKeyToggle').addEventListener('click', () => {
        const input = $('priceKey'), btn = $('priceKeyToggle');
        input.type = input.type === 'password' ? 'text' : 'password';
        btn.textContent = input.type === 'password' ? '显示' : '隐藏';
    });
    // 视觉能力：勾选原生视觉时隐藏并清空绑定下拉
    document.getElementById('priceNativeVision').addEventListener('change', () => toggleVisionBindGroup('price'));
    document.getElementById('modelAddNativeVision').addEventListener('change', () => toggleVisionBindGroup('modelAdd'));
    showSection('dashboard');
});

function navClick(e) {
    e.preventDefault();
    document.querySelectorAll('.sidebar-nav a').forEach(a => a.classList.remove('active'));
    this.classList.add('active');
    showSection(this.dataset.section);
}

function showSection(name) {
    document.querySelectorAll('.section-panel').forEach(p => p.classList.remove('active'));
    const panel = document.getElementById('section-' + name);
    if (panel) panel.classList.add('active');
    const titles = {
        dashboard:['仪表盘','掌握回响今天的运行状态'], users:['用户管理','账户、额度与订阅状态'], network:['网络内容管理','审核与维护智能体和群聊内容'],
        models:['模型定价','维护模型价格与峰谷倍率'], plans:['订阅计划','配置订阅权益与每日额度'],
        config:['系统配置','调整全局运行参数'], orders:['订单管理','查询与处理支付订单'], versions:['版本管理','发布客户端更新'], activities:['活动管理','配置活动规则与权益'], announcements:['公告管理','配置客户端弹窗公告'], domain:['域名绑定','管理允许访问的域名'], apidocs:['接口文档','查看服务端 API 说明'],
        feedback:['用户反馈','跟进真实用户问题'], password:['修改密码','保护管理账户安全'], smtp:['邮件配置','维护验证码与通知邮件'], audit:['审计日志','追踪关键后台操作']
    };
    const title = titles[name] || [name, ''];
    document.getElementById('topbarTitle').textContent = title[0];
    document.getElementById('topbarSubtitle').textContent = title[1];
    setSidebarOpen(false);
    _currentPage = 1;
    switch(name) {
        case 'dashboard': loadDashboard(); break;
        case 'users': loadUsers(); break;
        case 'network': loadNetworkAgents(); loadPresetTags(); break;
        case 'models': loadModelPrices(); break;
        case 'plans': loadPlans(); loadDefaultQuotas(); break;
        case 'config': loadConfig(); loadTLSConfig(); loadMaintenanceConfig(); loadChatStreamConfig(); loadAiReviewConfig(); break;
        case 'domain': loadDomainConfig(); break;
        case 'apidocs': break; // 纯静态页面无需加载
        case 'orders': loadOrders(); break;
        case 'versions': loadVersions(); break;
        case 'activities': loadActivities(); break;
        case 'announcements': loadAnnouncements(); break;
        case 'feedback': loadFeedbacks(); break;
        case 'smtp': loadSMTPConfig(); loadEmailTemplates(); toggleNotifyMode(); break;
        case 'audit': loadAuditLogs(); break;
        case 'password': break;
    }
}

function logout() {
    localStorage.removeItem('admin_token');
    window.location.href = '/admin/login.html';
}

function $(id) { return document.getElementById(id); }
function toast(msg, type) {
    const c = $('toastContainer');
    const t = document.createElement('div');
    t.className = 'toast toast-' + type;
    t.textContent = msg;
    c.appendChild(t);
    setTimeout(() => t.remove(), 3000);
}
function formatNum(n) { n = Number(n); return isNaN(n) ? '0' : n.toFixed(4); }
function formatDate(s) { return String(s || '').substring(0, 10) || '-'; }

function renderPagination(total, fnName) {
    const totalPages = Math.ceil(total / _pageSize);
    return `<button ${_currentPage<=1?'disabled':''} onclick="event.preventDefault();_currentPage=${_currentPage-1};${fnName}()">上一页</button>
    <span class="page-info">${_currentPage} / ${totalPages||1}（共${total}条）</span>
    <button ${_currentPage>=totalPages?'disabled':''} onclick="event.preventDefault();_currentPage=${_currentPage+1};${fnName}()">下一页</button>`;
}
// 当前活动模态框栈，用于 ESC 关闭最上层
var _modalStack = [];
function showModal(id) {
    const el = $(id);
    if (!el) return;
    el.style.display = 'flex';
    _modalStack.push(id);
    // 点击遮罩（模态框最外层）关闭
    el.onclick = (e) => { if (e.target === el) hideModal(id); };
}
function hideModal(id) {
    const el = $(id);
    if (!el) return;
    el.style.display = 'none';
    el.onclick = null;
    _modalStack = _modalStack.filter(x => x !== id);
}
// ESC 关闭最上层模态框
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && _modalStack.length > 0) {
        hideModal(_modalStack[_modalStack.length - 1]);
    }
});

// ======== 仪表盘 ========
function dashboardMetric(icon, tone, value, label) {
    return `<div class="stat-card"><div class="stat-icon ${tone}">${iconSvg(icon)}</div><div><div class="stat-value">${value}</div><div class="stat-label">${label}</div></div></div>`;
}

function renderDauChart(rawPoints) {
    const points = Array.isArray(rawPoints) ? rawPoints.map(point => ({
        date: String(point.date || ''),
        count: Math.max(0, Number(point.count) || 0)
    })) : [];
    if (points.length === 0) return '<div class="dau-chart-empty">这段时间还没有活跃数据</div>';

    const width = 760, height = 280, left = 42, right = 18, top = 18, bottom = 34;
    const plotWidth = width - left - right, plotHeight = height - top - bottom;
    const maxValue = Math.max(1, ...points.map(point => point.count));
    const coords = points.map((point, index) => ({
        ...point,
        x: left + (points.length === 1 ? plotWidth / 2 : index * plotWidth / (points.length - 1)),
        y: top + (maxValue - point.count) * plotHeight / maxValue
    }));
    const linePath = coords.map((point, index) => `${index === 0 ? 'M' : 'L'}${point.x.toFixed(1)} ${point.y.toFixed(1)}`).join(' ');
    const areaPath = `${linePath} L${coords[coords.length - 1].x.toFixed(1)} ${(height - bottom).toFixed(1)} L${coords[0].x.toFixed(1)} ${(height - bottom).toFixed(1)} Z`;
    const grids = Array.from({length: 5}, (_, index) => {
        const y = top + index * plotHeight / 4;
        const value = Math.round(maxValue * (4 - index) / 4);
        return `<line class="dau-chart-grid" x1="${left}" y1="${y.toFixed(1)}" x2="${width - right}" y2="${y.toFixed(1)}"/><text class="dau-chart-axis" x="${left - 10}" y="${(y + 3).toFixed(1)}" text-anchor="end">${value}</text>`;
    }).join('');
    const labelStep = Math.max(1, Math.ceil(points.length / 6));
    const labels = coords.map((point, index) => {
        if (index !== 0 && index !== coords.length - 1 && index % labelStep !== 0) return '';
        const shortDate = point.date.slice(5).replace('-', '/');
        return `<text class="dau-chart-axis" x="${point.x.toFixed(1)}" y="${height - 10}" text-anchor="middle">${escHtml(shortDate)}</text>`;
    }).join('');
    const dots = coords.map(point => `<circle class="dau-chart-point" cx="${point.x.toFixed(1)}" cy="${point.y.toFixed(1)}" r="4.5" tabindex="0"><title>${escHtml(point.date)}：${point.count} 位活跃用户</title></circle>`).join('');
    return `<svg class="dau-chart-svg" viewBox="0 0 ${width} ${height}" role="img" aria-label="每日活跃用户趋势折线图">
        <defs><linearGradient id="dauGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#557c95"/><stop offset="1" stop-color="#557c95" stop-opacity="0"/></linearGradient></defs>
        ${grids}<path class="dau-chart-area" d="${areaPath}"/><path class="dau-chart-line" d="${linePath}"/>${dots}${labels}
    </svg>`;
}

function setDashboardRange(days) {
    if (![7, 30, 90].includes(days) || days === _dashboardRange) return;
    _dashboardRange = days;
    loadDashboard();
}

async function loadDashboard() {
    const content = $('dashboardContent');
    content.innerHTML = '<div class="dashboard-panel"><div class="dau-chart-loading"><span class="spinner"></span>正在整理运营数据...</div></div>';
    try {
        const r = await api.get('/admin/dashboard?days=' + _dashboardRange);
        const d = r.data || {};
        const change = Number(d.active_change_percent) || 0;
        const changeLabel = `${change > 0 ? '+' : ''}${change.toFixed(1)}%`;
        const today = new Intl.DateTimeFormat('zh-CN', {year:'numeric', month:'long', day:'numeric', weekday:'long'}).format(new Date());
        content.innerHTML = `<div class="dashboard-shell">
            <div class="dashboard-intro"><div><span class="dashboard-eyebrow">Echo Operations</span><h1 class="dashboard-heading">今天的回响，清晰可见</h1><p class="dashboard-caption">从真实活跃、内容规模到模型用量，在一个安静而高效的视图里掌握产品状态。</p></div><div class="dashboard-date">数据按服务器时区统计<strong>${escHtml(today)}</strong></div></div>
            <div class="stats-row">
                ${dashboardMetric('user','blue',Number(d.user_count)||0,'累计用户')}
                ${dashboardMetric('spark','orange',Number(d.today_new_users)||0,'今日新增')}
                ${dashboardMetric('trend','green',Number(d.active_users_today)||0,'今日活跃用户')}
                ${dashboardMetric('bot','purple',Number(d.agent_count)||0,'已创建智能体')}
            </div>
            <div class="stats-row">
                ${dashboardMetric('plans','blue',Number(d.plan_count)||0,'订阅计划')}
                ${dashboardMetric('orders','orange',Number(d.order_pending)||0,'待处理订单')}
                ${dashboardMetric('clock','green','¥'+formatNum(d.today_usage),'今日模型用量')}
                ${dashboardMetric('wallet','purple','¥'+formatNum(d.total_usage_cost),'累计模型用量')}
            </div>
            <div class="dashboard-grid">
                <section class="dashboard-panel" aria-labelledby="dauChartTitle"><div class="dashboard-panel-header"><div><h2 class="dashboard-panel-title" id="dauChartTitle">每日活跃用户</h2><p class="dashboard-panel-subtitle">当天至少访问一次已登录 API 的去重普通用户</p></div><div class="range-switch" aria-label="选择统计周期">${[7,30,90].map(days => `<button type="button" class="${days===_dashboardRange?'active':''}" onclick="setDashboardRange(${days})" aria-pressed="${days===_dashboardRange}">${days}天</button>`).join('')}</div></div><div class="dau-chart-shell">${renderDauChart(d.dau_trend)}</div></section>
                <aside class="dashboard-panel"><div class="dashboard-panel-header"><div><h2 class="dashboard-panel-title">活跃摘要</h2><p class="dashboard-panel-subtitle">快速判断当前用户活跃节奏</p></div></div><div class="dau-summary">
                    <div class="dau-summary-item"><small>今日 DAU</small><strong>${Number(d.active_users_today)||0}</strong><em>较昨日 ${changeLabel}</em></div>
                    <div class="dau-summary-item"><small>昨日 DAU</small><strong>${Number(d.active_users_yesterday)||0}</strong></div>
                    <div class="dau-summary-item"><small>${_dashboardRange} 天峰值</small><strong>${Number(d.dau_peak)||0}</strong></div>
                    <div class="dau-summary-item"><small>日均活跃</small><strong>${(Number(d.dau_average)||0).toFixed(1)}</strong></div>
                </div></aside>
            </div>
        </div>`;
    } catch(e) {
        content.innerHTML = `<div class="dashboard-error"><span>仪表盘加载失败：${escHtml(e.message || '未知错误')}</span><button class="btn btn-sm btn-secondary" type="button" onclick="loadDashboard()">重新加载</button></div>`;
    }
}

// ======== 用户管理 ========
async function loadUsers() {
    const kw = ($('userSearch')?.value) || '';
    try {
        const r = await api.get('/admin/users?page='+_currentPage+'&page_size='+_pageSize+'&keyword='+encodeURIComponent(kw));
        const users = r.data.records || [];
        const rows = users.map(u => {
            const uid = u.ID||u.id;
            const uname = escHtml(u.Username||u.username);
            const role = escHtml(u.Role||u.role);
            const unameAttr = escAttr(u.Username||u.username);
            const roleAttr = escAttr(u.Role||u.role);
            return `<tr>
            <td>${uid}</td><td>${uname}</td><td>${escHtml(u.Nickname||u.nickname||'-')}</td>
            <td>${escHtml(u.Email||u.email||'-')}</td><td><span class="balance-tiers">免:${formatNum(u.free_quota_left)} | 订:${formatNum(u.subscription_quota_left)} | 零:${formatNum(u.Balance||u.balance)}</span><br><small class="text-muted">共${formatNum(u.total_balance)}</small></td>
            <td><span class="tag tag-${(u.Role||u.role)==='super_admin'?'danger':(u.Role||u.role)==='admin'?'warning':'info'}">${role}</span></td>
            <td><span class="tag tag-${(u.Status||u.status)===1?'success':'danger'}">${(u.Status||u.status)===1?'正常':'禁用'}</span></td>
            <td class="actions"><button class="btn btn-sm btn-secondary" onclick="editUser(${uid},'${unameAttr}',${u.Status||u.status},'${roleAttr}',${u.Balance||u.balance})">编辑</button><button class="btn btn-sm btn-primary" onclick="showAssignSub(${uid},'${unameAttr}')">订阅</button><button class="btn btn-sm btn-warning" onclick="showResetTest(${uid},'${unameAttr}')">测试重置</button><button class="btn btn-sm btn-danger" onclick="deleteUser(${uid},'${unameAttr}')">删除</button></td>
        </tr>`;
        }).join('');
        $('userTableBody').innerHTML = rows || '<tr><td colspan="8" class="text-center text-muted">暂无数据</td></tr>';
        $('userPagination').innerHTML = renderPagination(r.data.total, 'loadUsers');
    } catch(e) { toast(e.message, 'error'); }
}
function searchUsers() { _currentPage = 1; loadUsers(); }
function editUser(id, uname, status, role, balance) {
    $('editUserId').value = id; $('editUserUname').textContent = uname;
    $('editUserStatus').value = status; $('editUserRole').value = role; $('editUserBalance').value = balance;
    showModal('modalEditUser');
}
async function saveUser() {
    try {
        await api.put('/admin/users/'+$('editUserId').value, {
            status: parseInt($('editUserStatus').value),
            role: $('editUserRole').value,
            balance: parseFloat($('editUserBalance').value)
        });
        toast('保存成功', 'success'); hideModal('modalEditUser'); loadUsers();
    } catch(e) { toast(e.message, 'error'); }
}
function showResetTest(id, uname) {
    $('resetTestId').value = id;
    $('resetTestUname').textContent = uname;
    $('resetTestBalance').value = '';
    $('resetTestConfirm').checked = false;
    showModal('modalResetTest');
}
async function confirmResetTest() {
    if (!$('resetTestConfirm').checked) { toast('请先勾选确认', 'error'); return; }
    const id = $('resetTestId').value;
    const body = { confirm: true };
    const bal = $('resetTestBalance').value.trim();
    if (bal !== '') body.balance = parseFloat(bal);
    try {
        const r = await api.post('/admin/users/'+id+'/reset-test', body);
        toast(r.message || '重置成功', 'success'); hideModal('modalResetTest'); loadUsers();
    } catch(e) { toast(e.message, 'error'); }
}
function showAddUser() {
    ['newUsername','newEmail','newPassword','newNickname','newBalance'].forEach(id => $(id).value = '');
    $('newBalance').value = '0'; $('newRole').value = 'user';
    showModal('modalAddUser');
}
async function saveNewUser() {
    const username = $('newUsername').value.trim();
    const password = $('newPassword').value;
    if (!username) { toast('用户名不能为空', 'error'); return; }
    if (!password) { toast('密码不能为空', 'error'); return; }
    try {
        await api.post('/admin/users', {
            username: username,
            email: $('newEmail').value,
            password: password,
            nickname: $('newNickname').value,
            role: $('newRole').value,
            balance: parseFloat($('newBalance').value)||0
        });
        toast('用户创建成功', 'success'); hideModal('modalAddUser'); loadUsers();
    } catch(e) { toast(e.message, 'error'); }
}
async function deleteUser(id, uname) {
    if (!confirm(`确定删除用户 "${uname}"？此操作不可撤销。`)) return;
    try { await api.del('/admin/users/'+id); toast('删除成功', 'success'); loadUsers(); }
    catch(e) { toast(e.message, 'error'); }
}
function showAssignSub(id, uname) {
    $('assignUserId').value = id; $('assignUserUname').textContent = uname;
    $('assignQuota').value = ''; $('assignDays').value = '';
    $('userSubList').innerHTML = '<span class="text-muted">加载中...</span>';

    api.get('/admin/users/'+id+'/subscriptions').then(r => {
        const subs = r.data || [];
        if (subs.length === 0) {
            $('userSubList').innerHTML = '<span class="text-muted">无订阅记录</span>';
        } else {
            $('userSubList').innerHTML = '<table style="width:100%;border-collapse:collapse"><tr style="background:var(--gray-100)"><th style="padding:6px 8px;text-align:left;font-size:12px">计划</th><th style="padding:6px 8px;text-align:left;font-size:12px">配额</th><th style="padding:6px 8px;text-align:left;font-size:12px">有效期</th><th style="padding:6px 8px;text-align:left;font-size:12px">状态</th></tr>' +
                subs.map(s => `<tr><td style="padding:6px 8px;font-size:12px">${escHtml(s.plan_name)}</td><td style="padding:6px 8px;font-size:12px">¥${escHtml(s.daily_quota)}</td><td style="padding:6px 8px;font-size:12px">${escHtml(s.started_at)} → ${escHtml(s.expires_at)}</td><td style="padding:6px 8px;font-size:12px"><span class="tag tag-${s.active?'success':'danger'}">${s.active?'有效':'过期'}</span></td></tr>`).join('') + '</table>';
        }
    }).catch(() => { $('userSubList').innerHTML = '<span class="text-muted">加载失败</span>'; });

    api.get('/admin/plans').then(r => {
        $('assignPlanId').innerHTML = (r.data||[]).filter(p => (p.Status||p.status)===1).map(p => `<option value="${p.ID||p.id}">${escHtml(p.Name||p.name)} (${p.Price||p.price}元/${p.DurationDays||p.duration_days}天/日配额${p.DailyQuota||p.daily_quota})</option>`).join('');
        showModal('modalAssignSub');
    }).catch(e => toast(e.message, 'error'));
}
async function saveAssignSub() {
    try {
        await api.post('/admin/users/'+$('assignUserId').value+'/subscription', {
            plan_id: parseInt($('assignPlanId').value),
            daily_quota: parseFloat($('assignQuota').value)||0,
            duration_days: parseInt($('assignDays').value)||0
        });
        toast('订阅分配成功', 'success'); hideModal('modalAssignSub'); loadUsers();
    } catch(e) { toast(e.message, 'error'); }
}

// ======== 网络内容管理（智能体市场 / 群聊市场 / 预设标签库） ========
var _networkAgentPage = 1, _networkAgentStatus = '', _networkAgentQ = '';
var _networkGroupPage = 1, _networkGroupStatus = '', _networkGroupQ = '';
var _networkPageSize = 15;
var _networkAgentTotal = 0, _networkGroupTotal = 0; // 当前总条数，用于分页边界检查
var _rejectTarget = null; // {type:'agent'|'group', id:number}
var _viewingAgentId = null, _viewingGroupId = null;
var _presetTags = [];

function switchNetworkSubtab(tabName) {
    document.querySelectorAll('.sub-tab').forEach(b => b.classList.remove('active'));
    const btn = document.querySelector('.sub-tab[data-subtab="'+tabName+'"]');
    if (btn) btn.classList.add('active');
    ['network-agents','network-groups','network-tags'].forEach(t => {
        const el = $('subtab-'+t);
        if (el) el.style.display = (t === tabName) ? 'block' : 'none';
    });
    if (tabName === 'network-agents') loadNetworkAgents();
    else if (tabName === 'network-groups') loadNetworkGroups();
    else if (tabName === 'network-tags') loadPresetTags();
}

function statusLabel(s) {
    return {pending:'待审核', approved:'已通过', rejected:'已拒绝', taken_down:'已下架'}[s] || s || '-';
}

function renderAvatar(a, size) {
    size = size || 32;
    if (a.avatar_path) {
        return `<img src="${escHtml(a.avatar_path)}" style="width:${size}px;height:${size}px;border-radius:50%;object-fit:cover;vertical-align:middle">`;
    }
    let color = '#2563eb';
    if (a.avatar_color != null) {
        const c = Number(a.avatar_color);
        if (!isNaN(c)) {
            const a8 = (c >>> 24) & 0xff;
            const r = (c >>> 16) & 0xff;
            const g = (c >>> 8) & 0xff;
            const b = c & 0xff;
            color = `rgba(${r},${g},${b},${(a8/255).toFixed(3)})`;
        }
    }
    const initial = (a.name || '?').charAt(0);
    return `<div style="width:${size}px;height:${size}px;border-radius:50%;background:${color};color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:${Math.floor(size*0.5)}px;font-weight:600;vertical-align:middle">${escHtml(initial)}</div>`;
}

function renderTags(tags) {
    if (!tags || !tags.length) return '<span class="text-muted">-</span>';
    return tags.map(t => '<span class="tag-chip">'+escHtml(t)+'</span>').join(' ');
}

// ======== AI 内容审核 ========
// 徽章复用 status-badge 配色：pass=绿 / reject=红 / error=灰；reason 悬停可见
function renderAiReviewCell(item, type) {
    const s = item.ai_review_status || '';
    let badge = '<span class="text-muted">-</span>';
    if (s) {
        const map = {
            pass:   ['status-approved',   'AI 通过'],
            reject: ['status-rejected',   'AI 建议拒绝'],
            error:  ['status-taken_down', 'AI 审核失败']
        };
        const m = map[s] || ['status-taken_down', s];
        const reason = item.ai_review_reason || '';
        badge = `<span class="status-badge ${m[0]}" title="${escHtml(reason)}">${m[1]}</span>`;
    }
    return badge + ` <button class="btn btn-sm btn-secondary" data-ai-review="${type}" data-id="${item.id}">AI 审核</button>`;
}

async function runAiReview(type, id, btn) {
    if (btn) { btn.disabled = true; btn.textContent = '审核中...'; }
    try {
        const r = await api.post('/admin/network/' + (type === 'agent' ? 'agents' : 'groups') + '/' + id + '/ai-review');
        const v = r.data || {};
        if (v.pass) toast('AI 审核：通过（' + (v.risk_level || 'none') + '）', 'success');
        else toast('AI 审核：建议拒绝 — ' + (v.reason || ''), 'error');
    } catch(e) { toast(e.message, 'error'); }
    if (type === 'agent') loadNetworkAgents(); else loadNetworkGroups();
}

async function loadAiReviewConfig() {
    try {
        // 审核模型下拉选项来自模型定价列表（models 页已缓存则复用，否则现拉）
        let models = modelPricesCache;
        if (!models.length) {
            const mr = await api.get('/admin/model-prices');
            models = Array.isArray(mr.data) ? mr.data : ((mr.data && mr.data.models) || []);
            modelPricesCache = models;
        }
        const sel = $('aiReviewModel');
        sel.innerHTML = '<option value="">自动（默认）</option>' + models.map(m => {
            const mid = m.model_id || m.ModelID || '';
            return `<option value="${escHtml(mid)}">${escHtml(mid)}</option>`;
        }).join('');

        const r = await api.get('/admin/ai-review-config');
        const d = r.data || {};
        $('aiReviewEnabled').checked = d.enabled || false;
        $('aiReviewAuto').checked = d.auto || false;
        $('aiReviewPrompt').value = d.prompt || '';
        sel.value = d.model || '';
        if (sel.value !== (d.model || '')) sel.value = ''; // 配置的模型已不在定价列表时回落"自动"
        $('aiReviewStatus').textContent = '';
    } catch(e) { $('aiReviewStatus').textContent = '加载失败: '+e.message; }
}

async function saveAiReviewConfig() {
    try {
        await api.put('/admin/ai-review-config', {
            enabled: $('aiReviewEnabled').checked,
            auto: $('aiReviewAuto').checked,
            prompt: $('aiReviewPrompt').value,
            model: $('aiReviewModel').value
        });
        toast('AI 审核配置保存成功', 'success');
        $('aiReviewStatus').textContent = '✅ 配置已生效';
    } catch(e) { toast(e.message, 'error'); $('aiReviewStatus').textContent = '❌ '+e.message; }
}

function renderNetworkPagination(total, type) {
    const page = type === 'agent' ? _networkAgentPage : _networkGroupPage;
    const totalPages = Math.ceil(total / _networkPageSize);
    const prevFn = type === 'agent' ? 'networkAgentPrevPage' : 'networkGroupPrevPage';
    const nextFn = type === 'agent' ? 'networkAgentNextPage' : 'networkGroupNextPage';
    return `<button ${page<=1?'disabled':''} onclick="${prevFn}()">上一页</button>
    <span class="page-info">${page} / ${totalPages||1}（共${total}条）</span>
    <button ${page>=totalPages?'disabled':''} onclick="${nextFn}()">下一页</button>`;
}

// ======== 智能体市场 ========
async function loadNetworkAgents() {
    try {
        const params = new URLSearchParams({
            page: _networkAgentPage,
            page_size: _networkPageSize
        });
        if (_networkAgentStatus) params.set('status', _networkAgentStatus);
        if (_networkAgentQ) params.set('q', _networkAgentQ);
        const r = await api.get('/admin/network/agents?' + params.toString());
        const d = r.data || {};
        const list = d.list || [];
        const counts = d.counts || {};
        const pendingEl = $('cntPending');
        if (pendingEl) pendingEl.textContent = counts.pending || 0;
        $('networkAgentTableBody').innerHTML = list.map(a => {
            const status = a.status || 'pending';
            const tags = renderTags(a.tags);
            const avatar = renderAvatar(a, 32);
            const actions = renderNetworkAgentActions(a);
            const aiCell = renderAiReviewCell(a, 'agent');
            return `<tr>
                <td>${a.id||''}</td>
                <td>${avatar}</td>
                <td>${escHtml(a.name||'')}</td>
                <td>${escHtml(a.uploader_name||a.uploader||'-')}</td>
                <td>${tags}</td>
                <td><span class="status-badge status-${status}">${statusLabel(status)}</span></td>
                <td>${aiCell}</td>
                <td>${a.download_count||0}</td>
                <td>${escHtml(a.version||'v1')}</td>
                <td>${formatDate(a.submitted_at||a.created_at)}</td>
                <td class="actions">${actions}</td>
            </tr>`;
        }).join('') || '<tr><td colspan="11" class="text-center text-muted">暂无数据</td></tr>';
        _networkAgentTotal = d.total || 0;
        $('networkAgentPagination').innerHTML = renderNetworkPagination(_networkAgentTotal, 'agent');
        // 更新筛选按钮 active 状态
        document.querySelectorAll('#networkAgentStatusFilter button').forEach(b => {
            b.classList.toggle('btn-primary', b.dataset.status === _networkAgentStatus);
            b.classList.toggle('btn-secondary', b.dataset.status !== _networkAgentStatus);
        });
    } catch(e) { toast(e.message, 'error'); }
}

function renderNetworkAgentActions(a) {
    const id = a.id;
    const s = a.status || 'pending';
    let btns = `<button class="btn btn-sm btn-secondary" onclick="viewNetworkAgent(${id})">查看</button>`;
    if (s === 'pending') {
        btns += `<button class="btn btn-sm btn-success" onclick="approveNetworkAgent(${id})">通过</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="showRejectNetworkAgent(${id})">拒绝</button>`;
    } else if (s === 'approved') {
        btns += `<button class="btn btn-sm btn-secondary" onclick="editNetworkAgent(${id})">编辑</button>`;
        btns += `<button class="btn btn-sm btn-warning" onclick="takeDownNetworkAgent(${id})">下架</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="deleteNetworkAgent(${id})">删除</button>`;
    } else if (s === 'rejected') {
        btns += `<button class="btn btn-sm btn-success" onclick="approveNetworkAgent(${id})">通过</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="deleteNetworkAgent(${id})">删除</button>`;
    } else if (s === 'taken_down') {
        btns += `<button class="btn btn-sm btn-success" onclick="restoreNetworkAgent(${id})">恢复</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="deleteNetworkAgent(${id})">删除</button>`;
    }
    return btns;
}

function filterNetworkAgents(status) {
    _networkAgentStatus = status;
    _networkAgentPage = 1;
    loadNetworkAgents();
}

function searchNetworkAgents() {
    _networkAgentQ = ($('networkAgentSearch')?.value || '').trim();
    _networkAgentPage = 1;
    loadNetworkAgents();
}

function networkAgentPrevPage() { if (_networkAgentPage > 1) { _networkAgentPage--; loadNetworkAgents(); } }
function networkAgentNextPage() {
    const totalPages = Math.ceil(_networkAgentTotal / _networkPageSize) || 1;
    if (_networkAgentPage >= totalPages) return; // 边界检查
    _networkAgentPage++; loadNetworkAgents();
}

async function viewNetworkAgent(id) {
    try {
        const r = await api.get('/admin/network/agents/'+id);
        const a = r.data || {};
        _viewingAgentId = id;
        const tags = renderTags(a.tags);
        const avatar = renderAvatar(a, 64);
        $('networkAgentViewBody').innerHTML = `
            <div style="display:flex;gap:16px;align-items:center;margin-bottom:16px">
                ${avatar}
                <div style="flex:1">
                    <h3 style="margin-bottom:4px">${escHtml(a.name||'')}</h3>
                    <div style="font-size:13px;color:var(--gray-500)">上传者: ${escHtml(a.uploader_name||a.uploader||'-')} · 版本: ${escHtml(a.version||'v1')} · 提交: ${formatDate(a.submitted_at||a.created_at)}</div>
                    <div style="margin-top:6px">${tags}</div>
                </div>
            </div>
            <div class="detail-row"><div class="label">状态</div><div class="value"><span class="status-badge status-${a.status}">${statusLabel(a.status)}</span></div></div>
            <div class="detail-row"><div class="label">性别</div><div class="value">${escHtml(a.gender||'-')}</div></div>
            <div class="detail-row"><div class="label">描述</div><div class="value">${escHtml(a.description||'-')}</div></div>
            <div class="detail-row"><div class="label">人设</div><div class="value" style="white-space:pre-wrap">${escHtml(a.persona||'-')}</div></div>
            <div class="detail-row"><div class="label">开场白</div><div class="value">${escHtml(a.opening_line||'-')}</div></div>
            <div class="detail-row"><div class="label">世界观</div><div class="value">${escHtml(a.worldview||'-')}</div></div>
            ${a.reject_reason ? `<div class="detail-row"><div class="label">拒绝理由</div><div class="value" style="color:var(--danger)">${escHtml(a.reject_reason)}</div></div>` : ''}
        `;
        const showApprove = a.status === 'pending' || a.status === 'rejected';
        const showReject = a.status === 'pending';
        $('btnApproveAgentInView').style.display = showApprove ? 'inline-block' : 'none';
        $('btnRejectAgentInView').style.display = showReject ? 'inline-block' : 'none';
        showModal('modalNetworkAgentView');
    } catch(e) { toast(e.message, 'error'); }
}

async function approveNetworkAgent(id) {
    if (!confirm('确定通过该智能体审核？')) return;
    try {
        await api.post('/admin/network/agents/'+id+'/approve');
        toast('已通过审核', 'success');
        loadNetworkAgents();
    } catch(e) { toast(e.message, 'error'); }
}

async function approveNetworkAgentFromView() {
    if (!_viewingAgentId) return;
    if (!confirm('确定通过该智能体审核？')) return;
    try {
        await api.post('/admin/network/agents/'+_viewingAgentId+'/approve');
        toast('已通过审核', 'success');
        hideModal('modalNetworkAgentView');
        loadNetworkAgents();
    } catch(e) { toast(e.message, 'error'); }
}

function showRejectNetworkAgent(id) {
    _rejectTarget = { type: 'agent', id: id };
    $('rejectReason').value = '';
    showModal('modalRejectReason');
    setTimeout(() => $('rejectReason').focus(), 50);
}

function showRejectNetworkAgentFromView() {
    if (_viewingAgentId) showRejectNetworkAgent(_viewingAgentId);
}

function editNetworkAgent(id) {
    api.get('/admin/network/agents/'+id).then(r => {
        const a = r.data || {};
        $('netAgentEditId').value = id;
        $('netAgentEditName').value = a.name || '';
        $('netAgentEditDesc').value = a.description || '';
        $('netAgentEditTags').value = (a.tags || []).join(',');
        $('netAgentEditForceTakeDown').checked = a.status === 'taken_down';
        showModal('modalNetworkAgentEdit');
    }).catch(e => toast(e.message, 'error'));
}

async function saveNetworkAgentEdit() {
    const id = $('netAgentEditId').value;
    if (!id) { toast('参数错误', 'error'); return; }
    const body = {
        name: $('netAgentEditName').value,
        description: $('netAgentEditDesc').value,
        tags: $('netAgentEditTags').value.split(',').map(s => s.trim()).filter(s => s),
        force_take_down: $('netAgentEditForceTakeDown').checked
    };
    try {
        await api.put('/admin/network/agents/'+id, body);
        toast('保存成功', 'success');
        hideModal('modalNetworkAgentEdit');
        loadNetworkAgents();
    } catch(e) { toast(e.message, 'error'); }
}

async function deleteNetworkAgent(id) {
    if (!confirm('确定物理删除该智能体？此操作不可撤销。')) return;
    try {
        await api.del('/admin/network/agents/'+id);
        toast('删除成功', 'success');
        loadNetworkAgents();
    } catch(e) { toast(e.message, 'error'); }
}

async function takeDownNetworkAgent(id) {
    if (!confirm('确定强制下架该智能体？')) return;
    try {
        await api.put('/admin/network/agents/'+id, { force_take_down: true });
        toast('已下架', 'success');
        loadNetworkAgents();
    } catch(e) { toast(e.message, 'error'); }
}

async function restoreNetworkAgent(id) {
    if (!confirm('确定恢复该智能体到已通过状态？')) return;
    try {
        await api.put('/admin/network/agents/'+id, { force_take_down: false });
        toast('已恢复', 'success');
        loadNetworkAgents();
    } catch(e) { toast(e.message, 'error'); }
}

// ======== 群聊市场 ========
async function loadNetworkGroups() {
    try {
        const params = new URLSearchParams({
            page: _networkGroupPage,
            page_size: _networkPageSize
        });
        if (_networkGroupStatus) params.set('status', _networkGroupStatus);
        if (_networkGroupQ) params.set('q', _networkGroupQ);
        const r = await api.get('/admin/network/groups?' + params.toString());
        const d = r.data || {};
        const list = d.list || [];
        const counts = d.counts || {};
        const pendingEl = $('cntGroupPending');
        if (pendingEl) pendingEl.textContent = counts.pending || 0;
        $('networkGroupTableBody').innerHTML = list.map(g => {
            const status = g.status || 'pending';
            const tags = renderTags(g.tags);
            const actions = renderNetworkGroupActions(g);
            const aiCell = renderAiReviewCell(g, 'group');
            const mode = g.simulator_mode ? '模拟器' : (g.speak_mode || '普通');
            return `<tr>
                <td>${g.id||''}</td>
                <td>${escHtml(g.name||'')}</td>
                <td>${escHtml(g.uploader_name||g.uploader||'-')}</td>
                <td>${tags}</td>
                <td><span class="status-badge status-${status}">${statusLabel(status)}</span></td>
                <td>${aiCell}</td>
                <td>${g.download_count||0}</td>
                <td>${escHtml(g.version||'v1')}</td>
                <td>${escHtml(mode)}</td>
                <td>${formatDate(g.submitted_at||g.created_at)}</td>
                <td class="actions">${actions}</td>
            </tr>`;
        }).join('') || '<tr><td colspan="11" class="text-center text-muted">暂无数据</td></tr>';
        _networkGroupTotal = d.total || 0;
        $('networkGroupPagination').innerHTML = renderNetworkPagination(_networkGroupTotal, 'group');
        document.querySelectorAll('#networkGroupStatusFilter button').forEach(b => {
            b.classList.toggle('btn-primary', b.dataset.status === _networkGroupStatus);
            b.classList.toggle('btn-secondary', b.dataset.status !== _networkGroupStatus);
        });
    } catch(e) { toast(e.message, 'error'); }
}

function renderNetworkGroupActions(g) {
    const id = g.id;
    const s = g.status || 'pending';
    let btns = `<button class="btn btn-sm btn-secondary" onclick="viewNetworkGroup(${id})">查看</button>`;
    if (s === 'pending') {
        btns += `<button class="btn btn-sm btn-success" onclick="approveNetworkGroup(${id})">通过</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="showRejectNetworkGroup(${id})">拒绝</button>`;
    } else if (s === 'approved') {
        btns += `<button class="btn btn-sm btn-secondary" onclick="editNetworkGroup(${id})">编辑</button>`;
        btns += `<button class="btn btn-sm btn-warning" onclick="takeDownNetworkGroup(${id})">下架</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="deleteNetworkGroup(${id})">删除</button>`;
    } else if (s === 'rejected') {
        btns += `<button class="btn btn-sm btn-success" onclick="approveNetworkGroup(${id})">通过</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="deleteNetworkGroup(${id})">删除</button>`;
    } else if (s === 'taken_down') {
        btns += `<button class="btn btn-sm btn-success" onclick="restoreNetworkGroup(${id})">恢复</button>`;
        btns += `<button class="btn btn-sm btn-danger" onclick="deleteNetworkGroup(${id})">删除</button>`;
    }
    return btns;
}

function filterNetworkGroups(status) {
    _networkGroupStatus = status;
    _networkGroupPage = 1;
    loadNetworkGroups();
}

function searchNetworkGroups() {
    _networkGroupQ = ($('networkGroupSearch')?.value || '').trim();
    _networkGroupPage = 1;
    loadNetworkGroups();
}

function networkGroupPrevPage() { if (_networkGroupPage > 1) { _networkGroupPage--; loadNetworkGroups(); } }
function networkGroupNextPage() {
    const totalPages = Math.ceil(_networkGroupTotal / _networkPageSize) || 1;
    if (_networkGroupPage >= totalPages) return; // 边界检查
    _networkGroupPage++; loadNetworkGroups();
}

async function viewNetworkGroup(id) {
    try {
        const r = await api.get('/admin/network/groups/'+id);
        const g = r.data || {};
        _viewingGroupId = id;
        const tags = renderTags(g.tags);
        const members = (g.members || g.member_list || []).map(m => {
            const personaSummary = (m.persona || '').length > 80 ? (m.persona.substring(0, 80) + '...') : (m.persona || '-');
            return `<div class="detail-row"><div class="label">${escHtml(m.name||'-')}</div><div class="value" style="white-space:pre-wrap">${escHtml(personaSummary)}</div></div>`;
        }).join('') || '<div class="detail-row"><div class="label">成员</div><div class="value text-muted">无成员数据</div></div>';
        const mode = g.simulator_mode ? '模拟器模式' : (g.speak_mode || '普通模式');
        $('networkGroupViewBody').innerHTML = `
            <div style="margin-bottom:16px">
                <h3 style="margin-bottom:4px">${escHtml(g.name||'')}</h3>
                <div style="font-size:13px;color:var(--gray-500)">上传者: ${escHtml(g.uploader_name||g.uploader||'-')} · 版本: ${escHtml(g.version||'v1')} · 提交: ${formatDate(g.submitted_at||g.created_at)}</div>
                <div style="margin-top:6px">${tags}</div>
            </div>
            <div class="detail-row"><div class="label">状态</div><div class="value"><span class="status-badge status-${g.status}">${statusLabel(g.status)}</span></div></div>
            <div class="detail-row"><div class="label">描述</div><div class="value">${escHtml(g.description||'-')}</div></div>
            <div class="detail-row"><div class="label">群人设</div><div class="value" style="white-space:pre-wrap">${escHtml(g.persona||g.group_persona||'-')}</div></div>
            <div class="detail-row"><div class="label">世界观</div><div class="value">${escHtml(g.worldview||'-')}</div></div>
            <div class="detail-row"><div class="label">发言模式</div><div class="value">${escHtml(mode)}</div></div>
            <div class="detail-row"><div class="label">模拟器</div><div class="value">${g.simulator_mode ? '开启' : '关闭'}</div></div>
            ${g.reject_reason ? `<div class="detail-row"><div class="label">拒绝理由</div><div class="value" style="color:var(--danger)">${escHtml(g.reject_reason)}</div></div>` : ''}
            <h4 style="margin:16px 0 8px;font-size:14px;color:var(--gray-700);border-top:1px solid var(--gray-200);padding-top:12px">成员列表</h4>
            ${members}
        `;
        const showApprove = g.status === 'pending' || g.status === 'rejected';
        const showReject = g.status === 'pending';
        $('btnApproveGroupInView').style.display = showApprove ? 'inline-block' : 'none';
        $('btnRejectGroupInView').style.display = showReject ? 'inline-block' : 'none';
        showModal('modalNetworkGroupView');
    } catch(e) { toast(e.message, 'error'); }
}

async function approveNetworkGroup(id) {
    if (!confirm('确定通过该群聊审核？')) return;
    try {
        await api.post('/admin/network/groups/'+id+'/approve');
        toast('已通过审核', 'success');
        loadNetworkGroups();
    } catch(e) { toast(e.message, 'error'); }
}

async function approveNetworkGroupFromView() {
    if (!_viewingGroupId) return;
    if (!confirm('确定通过该群聊审核？')) return;
    try {
        await api.post('/admin/network/groups/'+_viewingGroupId+'/approve');
        toast('已通过审核', 'success');
        hideModal('modalNetworkGroupView');
        loadNetworkGroups();
    } catch(e) { toast(e.message, 'error'); }
}

function showRejectNetworkGroup(id) {
    _rejectTarget = { type: 'group', id: id };
    $('rejectReason').value = '';
    showModal('modalRejectReason');
    setTimeout(() => $('rejectReason').focus(), 50);
}

function showRejectNetworkGroupFromView() {
    if (_viewingGroupId) showRejectNetworkGroup(_viewingGroupId);
}

function editNetworkGroup(id) {
    api.get('/admin/network/groups/'+id).then(r => {
        const g = r.data || {};
        $('netGroupEditId').value = id;
        $('netGroupEditName').value = g.name || '';
        $('netGroupEditDesc').value = g.description || '';
        $('netGroupEditTags').value = (g.tags || []).join(',');
        $('netGroupEditForceTakeDown').checked = g.status === 'taken_down';
        showModal('modalNetworkGroupEdit');
    }).catch(e => toast(e.message, 'error'));
}

async function saveNetworkGroupEdit() {
    const id = $('netGroupEditId').value;
    if (!id) { toast('参数错误', 'error'); return; }
    const body = {
        name: $('netGroupEditName').value,
        description: $('netGroupEditDesc').value,
        tags: $('netGroupEditTags').value.split(',').map(s => s.trim()).filter(s => s),
        force_take_down: $('netGroupEditForceTakeDown').checked
    };
    try {
        await api.put('/admin/network/groups/'+id, body);
        toast('保存成功', 'success');
        hideModal('modalNetworkGroupEdit');
        loadNetworkGroups();
    } catch(e) { toast(e.message, 'error'); }
}

async function deleteNetworkGroup(id) {
    if (!confirm('确定物理删除该群聊？此操作不可撤销。')) return;
    try {
        await api.del('/admin/network/groups/'+id);
        toast('删除成功', 'success');
        loadNetworkGroups();
    } catch(e) { toast(e.message, 'error'); }
}

async function takeDownNetworkGroup(id) {
    if (!confirm('确定强制下架该群聊？')) return;
    try {
        await api.put('/admin/network/groups/'+id, { force_take_down: true });
        toast('已下架', 'success');
        loadNetworkGroups();
    } catch(e) { toast(e.message, 'error'); }
}

async function restoreNetworkGroup(id) {
    if (!confirm('确定恢复该群聊到已通过状态？')) return;
    try {
        await api.put('/admin/network/groups/'+id, { force_take_down: false });
        toast('已恢复', 'success');
        loadNetworkGroups();
    } catch(e) { toast(e.message, 'error'); }
}

// ======== 拒绝理由（共用） ========
async function confirmReject() {
    if (!_rejectTarget) { toast('参数错误', 'error'); return; }
    const reason = $('rejectReason').value.trim();
    if (!reason) { toast('请输入拒绝理由', 'error'); return; }
    const path = _rejectTarget.type === 'agent'
        ? '/admin/network/agents/' + _rejectTarget.id + '/reject'
        : '/admin/network/groups/' + _rejectTarget.id + '/reject';
    try {
        await api.post(path, { reason });
        toast('已拒绝', 'success');
        hideModal('modalRejectReason');
        if (_rejectTarget.type === 'agent') {
            if (_viewingAgentId === _rejectTarget.id) hideModal('modalNetworkAgentView');
            loadNetworkAgents();
        } else {
            if (_viewingGroupId === _rejectTarget.id) hideModal('modalNetworkGroupView');
            loadNetworkGroups();
        }
        _rejectTarget = null;
    } catch(e) { toast(e.message, 'error'); }
}

// ======== 预设标签库 ========
async function loadPresetTags() {
    try {
        const r = await api.get('/admin/network/preset-tags');
        const tags = (r.data && r.data.tags) || [];
        _presetTags = tags;
        $('presetTagList').innerHTML = tags.length
            ? tags.map(t => {
                const safe = escAttr(t);
                return `<span class="tag-chip">${escHtml(t)}<span class="remove" onclick="removePresetTag('${safe}')" title="删除">&times;</span></span>`;
            }).join('')
            : '<span class="text-muted">暂无标签</span>';
    } catch(e) { toast(e.message, 'error'); }
}

async function addPresetTag() {
    const v = ($('newPresetTag').value || '').trim();
    if (!v) { toast('请输入标签', 'error'); return; }
    const tags = (_presetTags || []).slice();
    if (tags.indexOf(v) >= 0) { toast('标签已存在', 'error'); return; }
    tags.push(v);
    try {
        await api.put('/admin/network/preset-tags', { tags });
        toast('添加成功', 'success');
        $('newPresetTag').value = '';
        loadPresetTags();
    } catch(e) { toast(e.message, 'error'); }
}

async function removePresetTag(tag) {
    if (!confirm('确定删除标签 "' + tag + '"？')) return;
    const tags = (_presetTags || []).filter(t => t !== tag);
    try {
        await api.put('/admin/network/preset-tags', { tags });
        toast('删除成功', 'success');
        loadPresetTags();
    } catch(e) { toast(e.message, 'error'); }
}

// ======== 模型定价 ========
let modelPricesCache = [];
async function loadModelPrices() {
    try {
        const r = await api.get('/admin/model-prices');
        // 统一返回结构处理：兼容 r.data 为数组或 {models: [...]} 两种形态
        const models = Array.isArray(r.data) ? r.data : ((r.data && r.data.models) || []);
        modelPricesCache = models;
        $('modelTableBody').innerHTML = models.map(m => {
            const mid = escHtml(m.model_id||m.ModelID);
            const rowId = m.id||m.ID;
            return `<tr>
            <td>${rowId}</td><td><strong>${mid}</strong></td>
            <td>${escHtml(m.provider||m.Provider||'deepseek')}</td>
            <td>${(m.price_per_call>0)?('<span class="tag tag-warning">按次</span> '+formatNum(m.price_per_call)+' 元/次'):(formatNum(m.input_price_per_1m)+'<br><small style="color:var(--gray-500)">'+formatNum(m.input_cache_hit_price_per_1m)+' / '+formatNum(m.output_price_per_1m)+'</small>')}</td>
            <td>${formatNum(m.thinking_input_price_per_1m)}<br><small style="color:var(--gray-500)">${formatNum(m.thinking_cache_hit_price_per_1m)} / ${formatNum(m.thinking_output_price_per_1m)}</small></td>
            <td><span class="tag tag-${(m.status||m.Status)===1?'success':'danger'}">${(m.status||m.Status)===1?'上线中':'已隐藏'}</span> <span class="tag tag-${(m.thinking_status||m.ThinkingStatus)===1?'success':'danger'}">思考</span></td>
            <td class="actions"><button class="btn btn-sm btn-secondary" data-action="edit-model" data-id="${rowId}">编辑</button>
            <button class="btn btn-sm ${(m.status||m.Status)===1?'btn-warning':'btn-success'}" data-action="toggle-model" data-id="${rowId}">${(m.status||m.Status)===1?'隐藏':'恢复上线'}</button>
            <button class="btn btn-sm btn-danger" data-action="delete-model" data-id="${rowId}">删除</button></td>
        </tr>`;
        }).join('') || '<tr><td colspan="7" class="text-center text-muted">暂无定价，请先同步模型</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function editPriceById(id) {
    const m = modelPricesCache.find(x => (x.id||x.ID) == id); if (!m) return;
    $('priceId').value = m.id||m.ID; $('priceModelId').textContent = m.model_id||m.ModelID;
    $('priceInput').value = m.input_price_per_1m||0; $('priceCache').value = m.input_cache_hit_price_per_1m||0; $('priceOutput').value = m.output_price_per_1m||0; $('priceStatus').value = (m.status!==undefined?m.status:1);
    $('priceThinkInput').value = m.thinking_input_price_per_1m||0; $('priceThinkCache').value = m.thinking_cache_hit_price_per_1m||0; $('priceThinkOutput').value = m.thinking_output_price_per_1m||0; $('priceThinkStatus').value = (m.thinking_status!==undefined?m.thinking_status:1);
    $('pricePerCall').value = m.price_per_call||0;
    // 视觉能力：原生勾选 + 绑定下拉（排除自身）
    $('priceNativeVision').checked = !!(m.native_vision || m.NativeVision);
    fillVisionModelOptions('priceVisionModel', m.model_id || m.ModelID);
    $('priceVisionModel').value = m.vision_model_id || m.VisionModelID || '';
    toggleVisionBindGroup('price');
    // 站点配置：provider 只读，base_url/api_format 可改，key 掩码提示、留空不覆盖
    $('priceProvider').value = m.provider || 'deepseek';
    $('priceBaseUrl').value = m.base_url || '';
    $('priceFormat').value = m.api_format || 'openai';
    $('priceKey').value = '';
    $('priceKeyHint').textContent = m.has_key ? '已配置 Key（掩码保护），输入新值覆盖，留空不修改' : '该站点尚未配置 Key，请填写';
    showModal('modalPrice');
}
// 绑定视觉模型下拉：数据源为当前模型列表中 native_vision==true 的模型；excludeId 用于编辑时排除自身
function fillVisionModelOptions(selectId, excludeId) {
    const candidates = modelPricesCache.filter(x => (x.native_vision || x.NativeVision) && (x.model_id || x.ModelID) !== excludeId);
    const sel = $(selectId);
    if (!candidates.length) {
        sel.innerHTML = '<option value="">暂无原生视觉模型可选</option>';
        return;
    }
    sel.innerHTML = '<option value="">不绑定</option>' + candidates.map(x => {
        const mid = x.model_id || x.ModelID;
        const name = x.model_name || x.ModelName || mid;
        return `<option value="${escAttr(mid)}">${escHtml(name)}（${escHtml(mid)}）</option>`;
    }).join('');
}
// 勾选原生视觉时隐藏绑定下拉并清空，未勾选时显示
function toggleVisionBindGroup(prefix) {
    const native = $(prefix + 'NativeVision').checked;
    $(prefix + 'VisionBindGroup').style.display = native ? 'none' : '';
    if (native) $(prefix + 'VisionModel').value = '';
}
async function savePrice() {
    const body = {
        input_price_per_1m: parseFloat($('priceInput').value),
        input_cache_hit_price_per_1m: parseFloat($('priceCache').value),
        output_price_per_1m: parseFloat($('priceOutput').value),
        status: parseInt($('priceStatus').value),
        thinking_input_price_per_1m: parseFloat($('priceThinkInput').value),
        thinking_cache_hit_price_per_1m: parseFloat($('priceThinkCache').value),
        thinking_output_price_per_1m: parseFloat($('priceThinkOutput').value),
        thinking_status: parseInt($('priceThinkStatus').value),
        price_per_call: parseFloat($('pricePerCall').value)||0,
        native_vision: $('priceNativeVision').checked,
        vision_model_id: $('priceNativeVision').checked ? '' : $('priceVisionModel').value,
        base_url: $('priceBaseUrl').value.trim(),
        api_format: $('priceFormat').value
    };
    const key = $('priceKey').value.trim();
    if (key) body.api_key = key;
    try {
        await api.put('/admin/model-prices/'+$('priceId').value, body);
        toast('保存成功', 'success'); hideModal('modalPrice'); loadModelPrices();
    } catch(e) { toast(e.message, 'error'); }
}
async function syncModels() {
    try { await api.post('/admin/model-prices/sync'); toast('同步成功', 'success'); loadModelPrices(); }
    catch(e) { toast(e.message, 'error'); }
}
async function showAddModel() {
    ['modelAddId','modelAddName','modelAddBaseUrl','modelAddKey'].forEach(id => $(id).value = '');
    $('modelAddProvider').value = '';
    $('modelAddFormat').value = 'openai';
    $('modelAddKey').type = 'password'; $('modelAddKeyToggle').textContent = '显示';
    $('modelAddModelSelect').innerHTML = '<option value="">请先拉取模型</option>';
    $('modelAddFetchHint').textContent = '';
    ['modelAddInput','modelAddCache','modelAddOutput','modelAddThinkInput','modelAddThinkCache','modelAddThinkOutput'].forEach(id => $(id).value = '0');
    $('modelAddStatus').value = '1'; $('modelAddThinkStatus').value = '1';
    // 视觉能力：默认非原生，绑定下拉数据源为已有原生视觉模型
    $('modelAddNativeVision').checked = false;
    fillVisionModelOptions('modelAddVisionModel', null);
    toggleVisionBindGroup('modelAdd');
    // provider 候选来自模型列表的 provider 去重（models 页打开时已加载 modelPricesCache）
    try {
        const providers = [...new Set(modelPricesCache.map(m => m.provider || m.Provider).filter(Boolean))];
        if (!providers.includes('deepseek')) providers.unshift('deepseek');
        $('modelAddProviderList').innerHTML = providers.map(p => `<option value="${escAttr(p)}"></option>`).join('');
    } catch(e) { /* 静默失败，仍可手输 */ }
    showModal('modalModelAdd');
}
// 输入 API 地址后代理拉取远程 /models，填充模型下拉框；失败可手输兜底
async function fetchRemoteModels() {
    const base_url = $('modelAddBaseUrl').value.trim();
    if (!base_url) { toast('请先填写 API 地址', 'error'); return; }
    const btn = $('modelAddFetchBtn'), hint = $('modelAddFetchHint');
    btn.disabled = true; btn.textContent = '拉取中...'; hint.textContent = '';
    try {
        const r = await api.post('/admin/models/fetch-remote', {
            base_url: base_url,
            api_key: $('modelAddKey').value.trim(),
            api_format: $('modelAddFormat').value
        });
        const models = (r.data && r.data.models) || [];
        $('modelAddModelSelect').innerHTML = '<option value="">请选择模型</option>' +
            models.map(id => `<option value="${escAttr(id)}">${escHtml(id)}</option>`).join('');
        hint.textContent = `已拉取 ${models.length} 个模型`;
        toast('模型拉取成功', 'success');
    } catch(e) {
        hint.textContent = '拉取失败，可手动输入模型 ID';
        toast(e.message, 'error');
    } finally {
        btn.disabled = false; btn.textContent = '拉取模型';
    }
}
async function saveModelAdd() {
    const model_id = $('modelAddId').value.trim();
    if (!model_id) { toast('模型 ID 不能为空', 'error'); return; }
    const num = id => parseFloat($(id).value) || 0;
    try {
        await api.post('/admin/model-prices', {
            model_id: model_id,
            model_name: $('modelAddName').value.trim(),
            provider: $('modelAddProvider').value.trim(),
            base_url: $('modelAddBaseUrl').value.trim(),
            api_format: $('modelAddFormat').value,
            api_key: $('modelAddKey').value.trim(),
            input_price_per_1m: num('modelAddInput'),
            input_cache_hit_price_per_1m: num('modelAddCache'),
            output_price_per_1m: num('modelAddOutput'),
            status: parseInt($('modelAddStatus').value),
            thinking_input_price_per_1m: num('modelAddThinkInput'),
            thinking_cache_hit_price_per_1m: num('modelAddThinkCache'),
            thinking_output_price_per_1m: num('modelAddThinkOutput'),
            thinking_status: parseInt($('modelAddThinkStatus').value),
            price_per_call: num('modelAddPerCall'),
            native_vision: $('modelAddNativeVision').checked,
            vision_model_id: $('modelAddNativeVision').checked ? '' : $('modelAddVisionModel').value
        });
        toast('添加成功', 'success'); hideModal('modalModelAdd'); loadModelPrices();
    } catch(e) { toast(e.message, 'error'); }
}
async function deleteModelPrice(id) {
    if (!confirm('确定删除该模型定价？删除后该模型将不可用。')) return;
    try { await api.del('/admin/model-prices/'+id); toast('删除成功', 'success'); loadModelPrices(); }
    catch(e) { toast(e.message, 'error'); }
}
// 隐藏/恢复上线：仅切 status，不动价格与站点配置；隐藏后客户端模型列表不可见、聊天请求被拦截
async function toggleModelStatus(id) {
    const m = modelPricesCache.find(x => (x.id||x.ID) == id); if (!m) return;
    const cur = (m.status !== undefined ? m.status : m.Status);
    const next = cur === 1 ? 0 : 1;
    const label = next === 0 ? '隐藏' : '恢复上线';
    if (next === 0 && !confirm(`隐藏后客户端将立即看不到「${m.model_id||m.ModelID}」，已选该模型的用户聊天也会被拦截。确定隐藏？`)) return;
    try {
        await api.put('/admin/model-prices/'+id+'/status', { status: next });
        toast('已'+label, 'success'); loadModelPrices();
    } catch(e) { toast(e.message, 'error'); }
}

// ======== 订阅计划 ========
async function loadDefaultQuotas() {
    try {
        const r = await api.get('/admin/config');
        const cfg = r.data || {};
        $('defaultOcrQuota').value = cfg.default_ocr_daily_quota || '3';
        $('defaultRealReplyQuota').value = cfg.default_real_reply_daily_quota || '30';
    } catch(e) { /* 静默失败 */ }
}
async function saveDefaultQuotas() {
    try {
        await api.put('/admin/config', { key: 'default_ocr_daily_quota', value: String(parseInt($('defaultOcrQuota').value) || 3) });
        await api.put('/admin/config', { key: 'default_real_reply_daily_quota', value: String(parseInt($('defaultRealReplyQuota').value) || 30) });
        $('defaultQuotaStatus').textContent = '✓ 已保存';
        toast('保存成功', 'success');
        setTimeout(() => $('defaultQuotaStatus').textContent = '', 2000);
    } catch(e) { toast(e.message, 'error'); }
}
async function loadPlans() {
    try {
        const r = await api.get('/admin/plans');
        $('planTableBody').innerHTML = (r.data||[]).map(p => {
            const ocrQ = p.ocr_daily_quota;
            const rrQ = p.real_reply_daily_quota;
            const ocrTag = ocrQ === -1 ? '<span class="tag tag-success">无限</span>' : (ocrQ > 0 ? `<span class="tag tag-info">${ocrQ}次/日</span>` : '<span class="tag tag-secondary">系统默认</span>');
            const rrTag = rrQ === -1 ? '<span class="tag tag-success">无限</span>' : (rrQ > 0 ? `<span class="tag tag-info">${rrQ}轮/日</span>` : '<span class="tag tag-secondary">系统默认</span>');
            const syncTag = (p.allow_sync || p.AllowSync) ? '<span class="tag tag-success">Sync On</span>' : '<span class="tag tag-secondary">Sync Off</span>';
            return `<tr>
            <td>${p.ID||p.id}</td><td>${escHtml(p.Name||p.name)}</td><td>${formatNum(p.Price||p.price)} 元</td>
            <td>${formatNum(p.DailyQuota||p.daily_quota)} 元/日</td><td>${p.DurationDays||p.duration_days} 天</td>
            <td>${ocrTag} ${rrTag}</td>
            <td>${syncTag}</td>
            <td><span class="tag tag-${(p.Status||p.status)===1?'success':'danger'}">${(p.Status||p.status)===1?'启用':'停用'}</span></td>
            <td class="actions">
                <button class="btn btn-sm btn-secondary" onclick="editPlan(${p.ID||p.id})">编辑</button>
                <button class="btn btn-sm btn-danger" onclick="deletePlan(${p.ID||p.id})">删除</button>
            </td>
        </tr>`;
        }).join('') || '<tr><td colspan="9" class="text-center text-muted">暂无计划</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function showAddPlan() {
    $('modalPlanTitle').textContent = '新增订阅计划'; $('planId').value = '';
    ['planName','planDesc','planPrice','planQuota','planSort'].forEach(id => $(id).value = '');
    $('planDays').value = '30';
    $('planOcrQuota').value = '0'; $('planRealReplyQuota').value = '0';
    $('planAllowSync').checked = false;
    showModal('modalPlan');
}
function editPlan(id) {
    api.get('/admin/plans').then(r => {
        const p = (r.data||[]).find(x => (x.ID||x.id) == id); if (!p) return;
        $('modalPlanTitle').textContent = '编辑订阅计划'; $('planId').value = id;
        $('planName').value = p.Name||p.name||''; $('planDesc').value = p.Description||p.description||'';
        $('planPrice').value = p.Price||p.price||0; $('planQuota').value = p.DailyQuota||p.daily_quota||0;
        $('planDays').value = p.DurationDays||p.duration_days||30; $('planSort').value = p.SortOrder||p.sort_order||0;
        $('planOcrQuota').value = (p.ocr_daily_quota != null) ? p.ocr_daily_quota : 0;
        $('planRealReplyQuota').value = (p.real_reply_daily_quota != null) ? p.real_reply_daily_quota : 0;
        $('planAllowSync').checked = !!(p.allow_sync || p.AllowSync);
        showModal('modalPlan');
    }).catch(e => toast(e.message, 'error'));
}
async function savePlan() {
    const name = $('planName').value.trim();
    const price = $('planPrice').value;
    if (!name) { toast('计划名称不能为空', 'error'); return; }
    if (price === '' || isNaN(parseFloat(price))) { toast('价格不能为空', 'error'); return; }
    const body = {
        name: name, description: $('planDesc').value,
        price: parseFloat(price), daily_quota: parseFloat($('planQuota').value)||0,
        duration_days: parseInt($('planDays').value)||30, sort_order: parseInt($('planSort').value)||0,
        ocr_daily_quota: parseInt($('planOcrQuota').value)||0,
        real_reply_daily_quota: parseInt($('planRealReplyQuota').value)||0,
        allow_sync: $('planAllowSync').checked
    };
    try {
        const id = $('planId').value;
        if (id) await api.put('/admin/plans/'+id, body); else await api.post('/admin/plans', body);
        toast('保存成功', 'success'); hideModal('modalPlan'); loadPlans();
    } catch(e) { toast(e.message, 'error'); }
}
async function deletePlan(id) {
    if (!confirm('确定删除？')) return;
    try { await api.del('/admin/plans/'+id); toast('删除成功', 'success'); loadPlans(); }
    catch(e) { toast(e.message, 'error'); }
}

// ======== 系统配置 ========
async function loadTLSConfig() {
    try {
        const response = await api.get('/admin/tls-config');
        const cfg = response.data || response;
        $('tlsEnabled').checked = !!cfg.enabled;
        $('tlsPort').value = cfg.port || 443;
        $('tlsAutoAcme').checked = !!cfg.auto_acme;
        $('tlsAcmeEmail').value = cfg.acme_email || '';
        $('tlsAcmeDomains').value = (cfg.acme_domains || []).join('\n');
        $('tlsCacheDir').value = cfg.cache_dir || './data/acme';
        $('tlsCertFile').value = cfg.cert_file || '';
        $('tlsKeyFile').value = cfg.key_file || '';
    } catch (e) { toast('读取 TLS 配置失败: ' + e.message, 'error'); }
}

async function saveTLSConfig() {
    const autoAcme = $('tlsAutoAcme').checked;
    const payload = {
        enabled: $('tlsEnabled').checked,
        port: Number($('tlsPort').value || 443),
        auto_acme: autoAcme,
        acme_email: $('tlsAcmeEmail').value.trim(),
        acme_domains: $('tlsAcmeDomains').value.split(/\r?\n/).map(v => v.trim()).filter(Boolean),
        cache_dir: $('tlsCacheDir').value.trim() || './data/acme',
        cert_file: autoAcme ? '' : $('tlsCertFile').value.trim(),
        key_file: autoAcme ? '' : $('tlsKeyFile').value.trim()
    };
    try {
        await api.put('/admin/tls-config', payload);
        $('tlsStatus').textContent = '已保存，请重启服务';
        toast('TLS 配置已保存，重启服务后生效', 'success');
    } catch (e) { toast('保存 TLS 配置失败: ' + e.message, 'error'); }
}

async function loadConfig() {
    try {
        const r = await api.get('/admin/config');
        const cfg = r.data || {};
        $('configTableBody').innerHTML = Object.entries(cfg).map(([k,v]) => {
            const ek = escHtml(k);
            const ev = escHtml(v);
            const ekAttr = escAttr(k);
            const evAttr = escAttr(v);
            return `<tr>
            <td><code>${ek}</code></td><td>${ev}</td>
            <td class="actions"><button class="btn btn-sm btn-secondary" onclick="editConfig('${ekAttr}','${evAttr}')">编辑</button></td>
        </tr>`;
        }).join('') || '<tr><td colspan="3" class="text-center text-muted">暂无配置</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
    loadPaymentConfig();
    loadTimeOfUsePricing();
}

// === 峰谷价格图形化 UI ===
function touMinutesToTime(min) {
    var h = Math.floor(min / 60);
    var m = min % 60;
    return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
}
function touTimeToMinutes(timeStr) {
    var parts = (timeStr || '00:00').split(':');
    return parseInt(parts[0]) * 60 + parseInt(parts[1] || 0);
}
function touInitSliders() {
    ['touValleyStartSlider', 'touValleyEndSlider', 'touPeakSlider', 'touValleyMultSlider'].forEach(function(id) {
        var el = $(id);
        if (el) el.addEventListener('input', touUpdateUI);
    });
}
function touUpdateUI() {
    var startMin = parseInt($('touValleyStartSlider').value);
    var endMin = parseInt($('touValleyEndSlider').value);
    var peakMult = parseFloat($('touPeakSlider').value);
    var valleyMult = parseFloat($('touValleyMultSlider').value);

    $('touValleyStartDisplay').textContent = touMinutesToTime(startMin);
    $('touValleyEndDisplay').textContent = touMinutesToTime(endMin);
    $('touPeakDisplay').textContent = peakMult.toFixed(2) + '×';
    $('touValleyMultDisplay').textContent = valleyMult.toFixed(2) + '×';

    touUpdateTimeline(startMin, endMin);
    touUpdatePreview(startMin, endMin, peakMult, valleyMult);
}
function touUpdateTimeline(startMin, endMin) {
    var track = $('touTimelineTrack');
    track.querySelectorAll('.tou-valley-zone').forEach(function(el) { el.remove(); });

    if (startMin === endMin) {
        // 全天峰时，无谷时段
    } else if (startMin < endMin) {
        var zone = document.createElement('div');
        zone.className = 'tou-valley-zone';
        zone.style.left = (startMin / 1439 * 100) + '%';
        zone.style.width = ((endMin - startMin) / 1439 * 100) + '%';
        track.appendChild(zone);
    } else {
        // 跨午夜：两段
        var zone1 = document.createElement('div');
        zone1.className = 'tou-valley-zone';
        zone1.style.left = (startMin / 1439 * 100) + '%';
        zone1.style.width = ((1439 - startMin) / 1439 * 100) + '%';
        track.appendChild(zone1);

        var zone2 = document.createElement('div');
        zone2.className = 'tou-valley-zone';
        zone2.style.left = '0%';
        zone2.style.width = (endMin / 1439 * 100) + '%';
        track.appendChild(zone2);
    }

    // 当前时间指示器
    var now = new Date();
    var nowMin = now.getHours() * 60 + now.getMinutes();
    var marker = $('touNowMarker');
    if (marker) {
        marker.style.display = 'block';
        marker.style.left = (nowMin / 1439 * 100) + '%';
    }
}
function touUpdatePreview(startMin, endMin, peakMult, valleyMult) {
    var now = new Date();
    var nowMin = now.getHours() * 60 + now.getMinutes();
    var nowTimeStr = touMinutesToTime(nowMin);

    var isValley;
    if (startMin === endMin) {
        isValley = false;
    } else if (startMin < endMin) {
        isValley = nowMin >= startMin && nowMin < endMin;
    } else {
        isValley = nowMin >= startMin || nowMin < endMin;
    }

    var badge = $('touPreviewBadge');
    var text = $('touPreviewText');
    var mult = $('touPreviewMult');

    if (isValley) {
        badge.textContent = '谷时';
        badge.className = 'tou-preview-badge valley';
        text.textContent = '当前 ' + nowTimeStr + ' 处于谷时段';
        mult.textContent = '费用 ×' + valleyMult.toFixed(2);
    } else {
        badge.textContent = '峰时';
        badge.className = 'tou-preview-badge peak';
        text.textContent = '当前 ' + nowTimeStr + ' 处于峰时段';
        mult.textContent = '费用 ×' + peakMult.toFixed(2);
    }
}
async function loadTimeOfUsePricing() {
    try {
        const r = await api.get('/admin/time-of-use-pricing');
        const pricing = r.data || {};
        var startMin = touTimeToMinutes(pricing.valley_start);
        var endMin = touTimeToMinutes(pricing.valley_end);

        if (!$('touValleyStartSlider').dataset.touInit) {
            touInitSliders();
            $('touValleyStartSlider').dataset.touInit = '1';
        }

        $('touValleyStartSlider').value = startMin;
        $('touValleyEndSlider').value = endMin;
        $('touPeakSlider').value = parseFloat(pricing.peak_multiplier || 1);
        $('touValleyMultSlider').value = parseFloat(pricing.valley_multiplier || 1);

        touUpdateUI();
    } catch(e) { toast(e.message, 'error'); }
}
async function saveTimeOfUsePricing() {
    try {
        var startMin = parseInt($('touValleyStartSlider').value);
        var endMin = parseInt($('touValleyEndSlider').value);
        await api.put('/admin/time-of-use-pricing', {
            valley_start: touMinutesToTime(startMin),
            valley_end: touMinutesToTime(endMin),
            peak_multiplier: parseFloat($('touPeakSlider').value),
            valley_multiplier: parseFloat($('touValleyMultSlider').value)
        });
        toast('峰谷价格已保存', 'success');
    } catch(e) { toast(e.message, 'error'); }
}
function editConfig(key, val) { $('configKey').value = key; $('configKey').readOnly = true; $('configValue').value = val; showModal('modalConfig'); }
function showAddConfig() { $('configKey').value = ''; $('configKey').readOnly = false; $('configValue').value = ''; showModal('modalConfig'); }
async function saveConfig() {
    try {
        await api.put('/admin/config', {key: $('configKey').value, value: $('configValue').value});
        toast('保存成功', 'success'); hideModal('modalConfig'); loadConfig();
    } catch(e) { toast(e.message, 'error'); }
}

async function loadPaymentConfig() {
    try {
        const r = await api.get('/admin/payment-config');
        const d = r.data || {};
        $('payProvider').value = d.provider || 'easypay';
        $('payPid').value = d.pid || '';
        $('payKey').value = '';
        $('payKey').placeholder = d.has_key ? '已配置（留空则不修改）' : '请输入商户密钥';
        $('paySitename').value = d.sitename || '';
        $('payServerUrl').value = d.server_url || '';
        $('payApiUrl').value = d.api_url || '';
        togglePayProvider();
        if (d.provider === 'ifdian') {
            loadIfdianConfig();
            loadIfdianPlans();
        }
        $('payStatus').textContent = '';
    } catch(e) { $('payStatus').textContent = '加载失败: '+e.message; }
}
async function savePaymentConfig() {
    const provider = $('payProvider').value;
    const body = {
        provider: provider,
        pid: $('payPid').value,
        key: $('payKey').value,
        sitename: $('paySitename').value,
        server_url: $('payServerUrl').value,
        api_url: $('payApiUrl').value
    };
    if (provider === 'ifdian') {
        body.ifdian_user_id = $('ifdUserID').value;
        body.ifdian_token = $('ifdToken').value;
        body.ifdian_plan_ids = $('ifdPlanIds').value;
    }
    try {
        await api.put('/admin/payment-config', body);
        if (provider === 'ifdian') {
            await api.put('/admin/ifdian/config', {
                user_id: $('ifdUserID').value,
                token: $('ifdToken').value,
                plan_ids: $('ifdPlanIds').value
            });
        }
        toast('支付配置保存成功', 'success');
        $('payKey').value = ''; $('ifdToken').value = '';
        loadPaymentConfig();
        $('payStatus').textContent = '✅ 配置已生效';
    } catch(e) { toast(e.message, 'error'); $('payStatus').textContent = '❌ '+e.message; }
}
function togglePayProvider() {
    const provider = $('payProvider').value;
    $('payXsgSection').style.display = provider === 'easypay' ? 'block' : 'none';
    $('payIfdSection').style.display = provider === 'ifdian' ? 'block' : 'none';
}

document.addEventListener('DOMContentLoaded', function() {
    const el = document.getElementById('payProvider');
    if (el) el.addEventListener('change', togglePayProvider);
});

function loadIfdianConfig() {
    api.get('/admin/ifdian/config').then(r => {
        $('ifdUserID').value = r.data.user_id||'';
        $('ifdToken').value = '';
        $('ifdToken').placeholder = r.data.has_token ? '已配置（留空则不修改）' : '请输入API Token';
        $('ifdPlanIds').value = r.data.plan_ids||'';
    });
}

// ======== 订单管理 ========
async function loadOrders() {
    const st = ($('orderStatus')?.value) || '';
    try {
        const r = await api.get('/admin/orders?page='+_currentPage+'&page_size='+_pageSize+'&status='+st);
        $('orderTableBody').innerHTML = (r.data.records||[]).map(o => `<tr>
            <td>${escHtml(o.OrderNo||o.order_no)}</td><td>${escHtml(o.Username||o.username)}</td>
            <td><span class="tag tag-info">${escHtml(o.Type||o.type)}</span></td><td>${escHtml(o.PlanName||o.plan_name||'-')}</td>
            <td>${formatNum(o.Amount||o.amount)}</td><td>${formatNum(o.ActualAmount||o.actual_amount)}</td>
            <td><span class="tag tag-${(o.Status||o.status)==='paid'?'success':(o.Status||o.status)==='pending'?'warning':'danger'}">${escHtml(o.Status||o.status)}</span></td>
            <td>${escHtml(o.PaymentType||o.payment_type||'-')}</td><td>${formatDate(o.CreatedAt||o.created_at)}</td>
        </tr>`).join('') || '<tr><td colspan="9" class="text-center text-muted">暂无订单</td></tr>';
        $('orderPagination').innerHTML = renderPagination(r.data.total, 'loadOrders');
    } catch(e) { toast(e.message, 'error'); }
}
function filterOrders() { _currentPage = 1; loadOrders(); }

// ======== 域名绑定 ========
function toggleDomainEnabled() {
    $('domainListSection').style.display = $('domainEnabled').checked ? 'block' : 'none';
}
async function loadDomainConfig() {
    try {
        const r = await api.get('/admin/domain-config');
        const d = r.data || {};
        $('domainEnabled').checked = d.enabled || false;
        $('domainList').value = (d.domains||[]).join('\n');
        toggleDomainEnabled();
        $('domainStatus').textContent = '';
    } catch(e) { $('domainStatus').textContent = '加载失败: '+e.message; }
}
async function saveDomainConfig() {
    try {
        const domains = $('domainList').value.split('\n').map(s => s.trim()).filter(s => s.length > 0);
        await api.put('/admin/domain-config', { enabled: $('domainEnabled').checked, domains: domains });
        toast('域名配置保存成功', 'success');
        $('domainStatus').textContent = '✅ 配置已生效';
    } catch(e) { toast(e.message, 'error'); $('domainStatus').textContent = '❌ '+e.message; }
}

// ======== 站点维护模式 ========
async function loadMaintenanceConfig() {
    try {
        const r = await api.get('/admin/maintenance-config');
        const d = r.data || {};
        $('maintEnabled').checked = d.enabled || false;
        $('maintBypassKey').value = d.bypass_key || '';
        updateMaintBypassHint();
        $('maintStatus').textContent = '';
    } catch(e) { $('maintStatus').textContent = '加载失败: '+e.message; }
}
function updateMaintBypassHint() {
    const key = ($('maintBypassKey')?.value || '').trim();
    $('maintBypassHint').textContent = key
        ? '维护期间通过 /admin/?maint_key=' + key + ' 访问后台（请妥善保管此链接）'
        : '维护期间通过 /admin/?maint_key=你的Key 访问后台；开启并留空保存时将自动生成 Key';
}
async function saveMaintenanceConfig() {
    try {
        const r = await api.put('/admin/maintenance-config', {
            enabled: $('maintEnabled').checked,
            bypass_key: ($('maintBypassKey').value || '').trim()
        });
        if (r.data && r.data.bypass_key) $('maintBypassKey').value = r.data.bypass_key;
        updateMaintBypassHint();
        toast('维护模式配置保存成功', 'success');
        $('maintStatus').textContent = '✅ 配置已生效';
    } catch(e) { toast(e.message, 'error'); $('maintStatus').textContent = '❌ '+e.message; }
}

// ======== AI 上游调用模式 ========
async function loadChatStreamConfig() {
    try {
        const r = await api.get('/admin/chat-stream-config');
        const d = r.data || {};
        $('chatStreamEnabled').checked = d.enabled || false;
        $('chatStreamStatus').textContent = d.enabled ? '当前：流式调用上游' : '当前：非流式调用（默认）';
    } catch(e) { $('chatStreamStatus').textContent = '加载失败: '+e.message; }
}
async function saveChatStreamConfig() {
    try {
        const r = await api.put('/admin/chat-stream-config', { enabled: $('chatStreamEnabled').checked });
        toast('AI 调用模式配置保存成功', 'success');
        $('chatStreamStatus').textContent = '✅ 配置已生效';
    } catch(e) { toast(e.message, 'error'); $('chatStreamStatus').textContent = '❌ '+e.message; }
}

// ======== 版本管理 ========
async function loadVersions() {
    try {
        const r = await api.get('/admin/versions');
        $('versionTableBody').innerHTML = (r.data||[]).map(v => `<tr>
            <td>${v.ID||v.id}</td><td><span class="tag tag-info">${escHtml(v.Platform||v.platform)}</span></td>
            <td><strong>${escHtml(v.Version||v.version)}</strong></td><td>${escHtml(v.VersionCode||v.version_code)}</td>
            <td>${(v.FileSize||v.file_size) ? (v.FileSize/1024/1024).toFixed(1)+'MB' : '-'}</td>
            <td><span class="tag ${(v.IsForce||v.is_force)?'tag-danger':'tag-success'}">${(v.IsForce||v.is_force)?'强制':'可选'}</span></td>
            <td>${v.DownloadCount||v.download_count}</td>
            <td><span class="tag tag-${(v.Status||v.status)===1?'success':'danger'}">${(v.Status||v.status)===1?'启用':'停用'}</span></td>
            <td class="actions">
                <button class="btn btn-sm btn-secondary" onclick="editVersion(${v.ID||v.id})">编辑</button>
                <button class="btn btn-sm btn-danger" onclick="deleteVersion(${v.ID||v.id})">删除</button>
            </td>
        </tr>`).join('') || '<tr><td colspan="9" class="text-center text-muted">暂无版本</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function showAddVersion() {
    $('modalVersionTitle').textContent = '上传新版本'; $('versionId').value = '';
    $('verName').value = ''; $('verCode').value = ''; $('verNotes').value = '';
    $('verFile').value = ''; $('verForce').checked = false; $('verStatus').value = '1';
    $('verDownloadUrl').value = '';
    showModal('modalVersion');
}
function editVersion(id) {
    api.get('/admin/versions').then(r => {
        const v = (r.data||[]).find(x => (x.ID||x.id)===id); if (!v) return;
        $('modalVersionTitle').textContent = '编辑版本'; $('versionId').value = id;
        $('verPlatform').value = v.Platform||v.platform; $('verName').value = v.Version||v.version;
        $('verCode').value = v.VersionCode||v.version_code; $('verNotes').value = v.ReleaseNotes||v.release_notes||'';
        $('verForce').checked = v.IsForce||v.is_force||false; $('verStatus').value = v.Status||v.status;
        $('verDownloadUrl').value = v.DownloadURL||v.download_url||'';
        showModal('modalVersion');
    }).catch(e => toast(e.message, 'error'));
}
async function saveVersion() {
    const id = $('versionId').value;
    const verName = $('verName').value.trim();
    const verCode = $('verCode').value.trim();
    if (!verName) { toast('版本名称不能为空', 'error'); return; }
    if (!verCode) { toast('版本号不能为空', 'error'); return; }
    const hasFile = $('verFile').files[0];
    const externalUrl = $('verDownloadUrl').value.trim();
    // 新建时本地文件与外链二选一；编辑时若两者都无则保留原值
    if (!hasFile && !externalUrl && !id) { toast('请上传安装包文件或填写外部下载直链', 'error'); return; }

    const formData = new FormData();
    formData.append('platform', $('verPlatform').value);
    formData.append('version', $('verName').value);
    formData.append('version_code', $('verCode').value);
    formData.append('release_notes', $('verNotes').value);
    formData.append('is_force', $('verForce').checked ? 'true' : 'false');
    formData.append('status', $('verStatus').value);
    // 外链字段始终提交（包括空串，便于编辑时清空外链）
    formData.append('download_url', externalUrl);
    if (hasFile) formData.append('file', hasFile);

    const token = localStorage.getItem('admin_token');
    const url = id ? '/api/v1/admin/versions/'+id : '/api/v1/admin/versions';
    const method = id ? 'PUT' : 'POST';

    const wrap = $('verProgressWrap');
    const fill = $('verProgressFill');
    const text = $('verProgressText');
    wrap.style.display = 'block';
    fill.style.width = '0%';
    text.textContent = '0%';

    return new Promise(resolve => {
        const xhr = new XMLHttpRequest();
        xhr.open(method, url);
        xhr.setRequestHeader('Authorization', 'Bearer ' + token);
        xhr.timeout = 300000; // 5 分钟超时
        xhr.upload.onprogress = e => {
            if (e.lengthComputable) {
                const pct = Math.round((e.loaded / e.total) * 100);
                fill.style.width = pct + '%';
                text.textContent = pct + '%';
            }
        };
        xhr.onload = () => {
            wrap.style.display = 'none';
            if (xhr.status === 401) {
                localStorage.removeItem('admin_token');
                window.location.href = '/admin/login.html';
                resolve();
                return;
            }
            try {
                const data = JSON.parse(xhr.responseText);
                if (data.code === 0) { toast('保存成功', 'success'); hideModal('modalVersion'); loadVersions(); }
                else toast(data.message, 'error');
            } catch(e) { toast('解析响应失败', 'error'); }
            resolve();
        };
        xhr.onerror = () => { toast('上传失败，请检查网络', 'error'); wrap.style.display = 'none'; resolve(); };
        xhr.ontimeout = () => { toast('上传超时，请重试', 'error'); wrap.style.display = 'none'; resolve(); };
        xhr.send(formData);
    });
}
// ======== 修改密码 ========
async function changePassword() {
    const old = $('pwdOld').value;
    const pwd = $('pwdNew').value;
    const confirmPwd = $('pwdConfirm').value;
    if (!pwd || pwd.length < 6) { toast('新密码至少6位', 'error'); return; }
    if (pwd !== confirmPwd) { toast('两次密码不一致', 'error'); return; }
    try {
        await api.put('/admin/password', { old_password: old, new_password: pwd });
        toast('密码修改成功', 'success');
        $('pwdOld').value = ''; $('pwdNew').value = ''; $('pwdConfirm').value = '';
    } catch(e) { toast(e.message, 'error'); }
}

async function deleteVersion(id) {
    if (!confirm('确定删除？')) return;
    try { await api.del('/admin/versions/'+id); toast('删除成功', 'success'); loadVersions(); }
    catch(e) { toast(e.message, 'error'); }
}

// ======== 活动管理 ========
async function loadActivities() {
    try {
        const r = await api.get('/admin/activities');
        $('activityTableBody').innerHTML = (r.data||[]).map(a => `<tr>
            <td>${a.ID||a.id}</td><td>${escHtml(a.Name||a.name)}</td>
            <td><span class="tag tag-${(a.Type||a.type)==='discount'?'success':'warning'}">${(a.Type||a.type)==='discount'?'打折':'加送'}</span></td>
            <td><span class="tag tag-info">${(a.ApplyScope||a.apply_scope)==='subscribe'?'订阅':(a.ApplyScope||a.apply_scope)==='zero_drop'?'零落':'聊天'}</span></td>
            <td>${(a.Discount||a.discount)}</td>
            <td>${escHtml((a.StartedAt||a.started_at)||'-')}</td>
            <td>${escHtml((a.EndedAt||a.ended_at)||'-')}</td>
            <td><span class="tag tag-${(a.Status||a.status)===1?'success':'danger'}">${(a.Status||a.status)===1?'启用':'停用'}</span></td>
            <td class="actions">
                <button class="btn btn-sm btn-secondary" onclick="editActivity(${a.ID||a.id})">编辑</button>
                <button class="btn btn-sm btn-danger" onclick="deleteActivity(${a.ID||a.id})">删除</button>
            </td>
        </tr>`).join('') || '<tr><td colspan="9" class="text-center text-muted">暂无活动</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function showAddActivity() {
    $('modalActivityTitle').textContent = '创建活动'; $('activityId').value = '';
    ['actName','actDesc','actDiscount','actStart','actEnd'].forEach(id => $(id).value = '');
    $('actType').value = 'discount'; $('actScope').value = 'subscribe'; $('actStatus').value = '1';
    $('actRulesContainer').innerHTML = '';
    toggleActRules();
    showModal('modalActivity');
}
function editActivity(id) {
    api.get('/admin/activities').then(r => {
        const a = (r.data||[]).find(x => (x.ID||x.id)===id); if (!a) return;
        $('modalActivityTitle').textContent = '编辑活动'; $('activityId').value = id;
        $('actName').value = a.Name||a.name||''; $('actDesc').value = a.Description||a.description||'';
        $('actType').value = a.Type||a.type||'discount'; $('actScope').value = a.ApplyScope||a.apply_scope||'subscribe';
        $('actDiscount').value = a.Discount||a.discount||0; $('actStatus').value = a.Status||a.status||1;
        $('actStart').value = a.StartedAt||a.started_at||''; $('actEnd').value = a.EndedAt||a.ended_at||'';
        $('actRulesContainer').innerHTML = '';
        api.get('/admin/activities/'+id+'/rules').then(rr => {
            (rr.data||[]).forEach(rl => addRuleRow(rl));
        }).catch(e => toast(e.message, 'error'));
        toggleActRules();
        showModal('modalActivity');
    }).catch(e => toast(e.message, 'error'));
}
async function saveActivity() {
    const name = $('actName').value.trim();
    if (!name) { toast('活动名称不能为空', 'error'); return; }
    const body = {
        name: name, description: $('actDesc').value,
        type: $('actType').value, apply_scope: $('actScope').value,
        discount: parseFloat($('actDiscount').value),
        started_at: $('actStart').value, ended_at: $('actEnd').value,
        status: parseInt($('actStatus').value)
    };
    const scope = body.apply_scope;
    if (scope === 'chat') {
        body.rules = [];
        document.querySelectorAll('#actRulesContainer .rule-row').forEach(row => {
            body.rules.push({
                model_id: row.querySelector('.r-model').value,
                input_discount: parseFloat(row.querySelector('.r-inp').value)||1,
                cache_hit_discount: parseFloat(row.querySelector('.r-cache').value)||1,
                output_discount: parseFloat(row.querySelector('.r-out').value)||1,
                thinking_input_discount: parseFloat(row.querySelector('.r-tinp').value)||1,
                thinking_cache_hit_discount: parseFloat(row.querySelector('.r-tcache').value)||1,
                thinking_output_discount: parseFloat(row.querySelector('.r-tout').value)||1
            });
        });
    } else {
        // 非 chat scope 也发送空 rules，清除旧规则避免残留
        body.rules = [];
    }
    try {
        const id = $('activityId').value;
        if (id) await api.put('/admin/activities/'+id, body);
        else await api.post('/admin/activities', body);
        toast('保存成功', 'success'); hideModal('modalActivity'); loadActivities();
    } catch(e) { toast(e.message, 'error'); }
}
async function deleteActivity(id) {
    if (!confirm('确定删除？')) return;
    try { await api.del('/admin/activities/'+id); toast('删除成功', 'success'); loadActivities(); }
    catch(e) { toast(e.message, 'error'); }
}
function toggleActRules() {
    $('actRulesSection').style.display = $('actScope').value === 'chat' ? 'block' : 'none';
}
function addRuleRow(data) {
    const div = document.createElement('div');
    div.className = 'rule-row';
    div.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:8px;background:var(--gray-50);border-radius:var(--radius);margin-bottom:6px';
    div.innerHTML = `
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">模型ID</label><input class="form-control r-model" style="font-size:12px;padding:4px 8px" placeholder="deepseek-v4-flash" value="${escHtml((data&&data.ModelID)||(data&&data.model_id)||'')}"></div>
        <div></div>
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">输入折扣</label><input class="form-control r-inp" type="number" step="0.01" style="font-size:12px;padding:4px 8px" value="${(data&&data.InputDiscount)||(data&&data.input_discount)||1}"></div>
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">缓存命中折扣</label><input class="form-control r-cache" type="number" step="0.01" style="font-size:12px;padding:4px 8px" value="${(data&&data.CacheHitDiscount)||(data&&data.cache_hit_discount)||1}"></div>
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">输出折扣</label><input class="form-control r-out" type="number" step="0.01" style="font-size:12px;padding:4px 8px" value="${(data&&data.OutputDiscount)||(data&&data.output_discount)||1}"></div>
        <div style="border-top:1px dashed var(--gray-300);margin-top:4px;grid-column:1/-1"></div>
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">思考-输入折扣</label><input class="form-control r-tinp" type="number" step="0.01" style="font-size:12px;padding:4px 8px" value="${(data&&data.ThinkingInputDiscount)||(data&&data.thinking_input_discount)||1}"></div>
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">思考-缓存命中折扣</label><input class="form-control r-tcache" type="number" step="0.01" style="font-size:12px;padding:4px 8px" value="${(data&&data.ThinkingCacheHitDiscount)||(data&&data.thinking_cache_hit_discount)||1}"></div>
        <div class="form-group" style="margin:0"><label class="form-label" style="font-size:12px">思考-输出折扣</label><input class="form-control r-tout" type="number" step="0.01" style="font-size:12px;padding:4px 8px" value="${(data&&data.ThinkingOutputDiscount)||(data&&data.thinking_output_discount)||1}"></div>
        <div><button class="btn btn-sm btn-danger" onclick="this.closest('.rule-row').remove()" style="margin-top:18px;font-size:11px">移除</button></div>`;
    $('actRulesContainer').appendChild(div);
}

// ======== 公告管理 ========
const ANN_FREQ_LABELS = { once: '仅一次', daily: '每天一次', always: '每次启动' };
const ANN_AUDIENCE_LABELS = { all: '全部用户', subscriber: '仅订阅', free: '仅免费' };

// RFC3339 → datetime-local 输入框值（本地时区）
function annToLocalInput(s) {
    const d = new Date(s);
    if (!s || isNaN(d)) return '';
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
// datetime-local 输入框值 → RFC3339（UTC）
function annFromLocalInput(v) {
    if (!v) return '';
    const d = new Date(v);
    return isNaN(d) ? '' : d.toISOString();
}
// RFC3339 → 表格展示用本地时间
function formatAnnTime(s) {
    const d = new Date(s);
    if (!s || isNaN(d)) return s || '-';
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

async function loadAnnouncements() {
    try {
        const r = await api.get('/admin/announcements');
        $('announcementTableBody').innerHTML = (r.data || []).map(a => {
            const id = a.id || a.ID;
            const freq = a.frequency || a.Frequency || '';
            const audience = a.audience || a.Audience || '';
            const enabled = a.enabled !== undefined ? a.enabled : a.Enabled;
            return `<tr>
            <td>${id}</td><td>${escHtml(a.title || a.Title)}</td>
            <td><span class="tag tag-info">${ANN_FREQ_LABELS[freq] || escHtml(freq)}</span></td>
            <td><span class="tag tag-info">${ANN_AUDIENCE_LABELS[audience] || escHtml(audience)}</span></td>
            <td>${escHtml(formatAnnTime(a.start_at || a.StartAt))} ~ ${escHtml(formatAnnTime(a.end_at || a.EndAt))}</td>
            <td><span class="tag tag-${enabled ? 'success' : 'danger'}">${enabled ? '启用' : '停用'}</span></td>
            <td class="actions">
                <button class="btn btn-sm btn-secondary" data-ann-action="edit" data-id="${id}">编辑</button>
                <button class="btn btn-sm btn-danger" data-ann-action="delete" data-id="${id}">删除</button>
            </td>
        </tr>`;
        }).join('') || '<tr><td colspan="7" class="text-center text-muted">暂无公告</td></tr>';
    } catch (e) { toast(e.message, 'error'); }
}
function showAddAnnouncement() {
    $('modalAnnouncementTitle').textContent = '添加公告'; $('annId').value = '';
    ['annTitle', 'annContent', 'annStart', 'annEnd'].forEach(id => $(id).value = '');
    $('annFrequency').value = 'once'; $('annAudience').value = 'all'; $('annEnabled').checked = true;
    showModal('modalAnnouncement');
}
function editAnnouncement(id) {
    api.get('/admin/announcements').then(r => {
        const a = (r.data || []).find(x => (x.id || x.ID) === id); if (!a) return;
        $('modalAnnouncementTitle').textContent = '编辑公告'; $('annId').value = id;
        $('annTitle').value = a.title || a.Title || '';
        $('annContent').value = a.content || a.Content || '';
        $('annFrequency').value = a.frequency || a.Frequency || 'once';
        $('annAudience').value = a.audience || a.Audience || 'all';
        $('annStart').value = annToLocalInput(a.start_at || a.StartAt);
        $('annEnd').value = annToLocalInput(a.end_at || a.EndAt);
        $('annEnabled').checked = a.enabled !== undefined ? !!a.enabled : !!a.Enabled;
        showModal('modalAnnouncement');
    }).catch(e => toast(e.message, 'error'));
}
async function saveAnnouncement() {
    const title = $('annTitle').value.trim();
    const content = $('annContent').value;
    if (!title) { toast('标题不能为空', 'error'); return; }
    if (!content.trim()) { toast('内容不能为空', 'error'); return; }
    const startAt = annFromLocalInput($('annStart').value);
    const endAt = annFromLocalInput($('annEnd').value);
    if (!startAt || !endAt) { toast('请填写完整的生效时间与截止时间', 'error'); return; }
    if (new Date(endAt) <= new Date(startAt)) { toast('截止时间必须晚于生效时间', 'error'); return; }
    const body = {
        title: title, content: content,
        frequency: $('annFrequency').value, audience: $('annAudience').value,
        start_at: startAt, end_at: endAt,
        enabled: $('annEnabled').checked
    };
    try {
        const id = $('annId').value;
        if (id) await api.put('/admin/announcements/' + id, body);
        else await api.post('/admin/announcements', body);
        toast('保存成功', 'success'); hideModal('modalAnnouncement'); loadAnnouncements();
    } catch (e) { toast(e.message, 'error'); }
}
async function deleteAnnouncement(id) {
    if (!confirm('确定删除该公告？')) return;
    try { await api.del('/admin/announcements/' + id); toast('删除成功', 'success'); loadAnnouncements(); }
    catch (e) { toast(e.message, 'error'); }
}

// ======== 爱发电管理（在支付配置内） ========
async function syncIfdPlans() {
    try {
        await api.post('/admin/ifdian/sync-plans');
        toast('同步成功', 'success'); loadIfdianPlans();
    } catch(e) { toast(e.message, 'error'); }
}
async function loadIfdianPlans() {
    try {
        const r = await api.get('/admin/ifdian/plans');
        $('ifdPlanTableBody').innerHTML = (r.data||[]).map(p => {
            let mapLabel = '未映射';
            if (p.MappingType === 'subscribe') mapLabel = '订阅: '+(p.LocalPlanID||'');
            else if (p.MappingType === 'zero_drop') mapLabel = '零落: '+(p.Amount||'')+'元';
            return `<tr>
                <td>${p.ID||p.id}</td><td>${p.Name||p.name}</td><td>${p.Price||p.price} 元</td>
                <td>${p.PlanType||p.plan_type}</td><td>${mapLabel}</td>
                <td><span class="tag tag-${(p.Status||p.status)===1?'success':'danger'}">${(p.Status||p.status)===1?'启用':'停用'}</span></td>
                <td class="actions"><button class="btn btn-sm btn-secondary" onclick="editIfdMapping(${p.ID||p.id})">映射</button></td>
            </tr>`;
        }).join('') || '<tr><td colspan="7" class="text-center text-muted">暂无方案，请先同步</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function editIfdMapping(id) {
    api.get('/admin/ifdian/plans').then(r => {
        const p = (r.data||[]).find(x => (x.ID||x.id)===id); if (!p) return;
        $('ifdPlanId').value = id; $('ifdPlanName').textContent = p.Name||p.name;
        $('ifdMapType').value = p.MappingType||''; $('ifdMapStatus').value = p.Status||p.status||1;
        $('ifdMapAmount').value = p.Amount||p.amount||'';
        $('ifdMapQuota').value = p.DailyQuota||p.daily_quota||'';
        $('ifdMapDays').value = p.DurationDays||p.duration_days||'';
        api.get('/admin/plans').then(r2 => {
            $('ifdMapPlan').innerHTML = (r2.data||[]).filter(x => (x.Status||x.status)===1).map(x => `<option value="${x.ID||x.id}">${escHtml(x.Name||x.name)}</option>`).join('');
            $('ifdMapPlan').value = p.LocalPlanID||p.local_plan_id||'';
        }).catch(e => toast(e.message, 'error'));
        toggleIfdMapFields();
        showModal('modalIfdMapping');
    }).catch(e => toast(e.message, 'error'));
}
function toggleIfdMapFields() {
    const t = $('ifdMapType').value;
    $('ifdMapSubFields').style.display = t==='subscribe' ? 'block' : 'none';
    $('ifdMapDropFields').style.display = t==='zero_drop' ? 'block' : 'none';
}
async function saveIfdMapping() {
    try {
        await api.put('/admin/ifdian/plans/'+$('ifdPlanId').value+'/mapping', {
            mapping_type: $('ifdMapType').value,
            local_plan_id: parseInt($('ifdMapPlan').value)||0,
            amount: parseFloat($('ifdMapAmount').value)||0,
            daily_quota: parseFloat($('ifdMapQuota').value)||0,
            duration_days: parseInt($('ifdMapDays').value)||0,
            status: parseInt($('ifdMapStatus').value)
        });
        toast('映射保存成功', 'success'); hideModal('modalIfdMapping'); loadIfdianPlans();
    } catch(e) { toast(e.message, 'error'); }
}

// ─── 用户反馈管理 ───

const FB_CATEGORY_LABELS = {
    'feature': '✨ 新功能建议',
    'feature_tweak': '🔧 功能修改建议',
    'bug': '🐞 BUG / 漏洞',
    'ui': '🎨 美化建议',
    'pricing': '💰 订阅付费调整',
    'other': '📝 其他建议'
};

const FB_STATUS_LABELS = {
    0: { label: '待处理', color: 'var(--orange)' },
    1: { label: '处理中', color: 'var(--blue)' },
    2: { label: '已回复', color: 'var(--green)' },
    3: { label: '已关闭', color: 'var(--gray-400)' }
};

let _fbPage = 1;
const _fbPageSize = 15;
let _fbRecordsCache = []; // 缓存当前页反馈记录，供 viewFeedback 查找避免拉取全量数据

async function loadFeedbacks(page) {
    if (page) _fbPage = page;
    const category = document.getElementById('fbCategoryFilter').value;
    const status = document.getElementById('fbStatusFilter').value;
    const params = new URLSearchParams({
        page: _fbPage,
        page_size: _fbPageSize
    });
    if (category) params.set('category', category);
    if (status) params.set('status', status);

    const tbody = document.getElementById('feedbackTableBody');
    tbody.innerHTML = '<tr><td colspan="8" style="padding:24px;text-align:center"><span class="spinner"></span> 加载中...</td></tr>';

    try {
        const r = await api.get('/admin/feedback?' + params.toString());
        const data = r.data || {};
        const records = data.records || [];
        const total = data.total || 0;
        _fbRecordsCache = records; // 缓存当前页记录

        if (records.length === 0) {
            tbody.innerHTML = '<tr><td colspan="8" style="padding:32px;text-align:center;color:var(--gray-400)">📭 暂无反馈记录</td></tr>';
        } else {
            tbody.innerHTML = records.map(f => {
                const cat = escHtml(FB_CATEGORY_LABELS[f.category] || f.category || '');
                const st = FB_STATUS_LABELS[f.status] || FB_STATUS_LABELS[0];
                const content = escHtml(f.content.length > 80 ? f.content.substring(0, 80) + '...' : f.content);
                const replyBadge = f.reply
                    ? '<div style="font-size:11px;color:var(--green);margin-top:4px">💬 已回复: ' + escHtml(f.reply.length > 30 ? f.reply.substring(0, 30) + '...' : f.reply) + '</div>'
                    : '';
                const contact = f.contact ? escHtml(f.contact) : '<span style="color:var(--gray-400)">未填写</span>';
                const username = f.username ? escHtml(f.username) : '<span style="color:var(--gray-400)">匿名</span>';
                const time = new Date(f.created_at).toLocaleString('zh-CN', { hour12: false });

                return '<tr>' +
                    '<td style="padding:8px 12px">#' + f.id + '</td>' +
                    '<td style="padding:8px 12px">' + username + '</td>' +
                    '<td style="padding:8px 12px"><span style="font-size:12px">' + cat + '</span></td>' +
                    '<td style="padding:8px 12px"><div style="max-width:300px">' + content + replyBadge + '</div></td>' +
                    '<td style="padding:8px 12px;font-size:12px">' + contact + '</td>' +
                    '<td style="padding:8px 12px"><span style="color:' + st.color + ';font-size:12px">● ' + st.label + '</span></td>' +
                    '<td style="padding:8px 12px;font-size:12px;color:var(--gray-500)">' + time + '</td>' +
                    '<td style="padding:8px 12px">' +
                        '<button class="btn btn-sm btn-primary" onclick="viewFeedback(' + f.id + ')" style="margin-right:4px">查看</button>' +
                        '<button class="btn btn-sm btn-danger" onclick="deleteFeedback(' + f.id + ')">删除</button>' +
                    '</td>' +
                '</tr>';
            }).join('');
        }
        renderFeedbackPagination(total);
    } catch(e) {
        tbody.innerHTML = '<tr><td colspan="8" style="padding:24px;text-align:center;color:var(--red)">加载失败: ' + escHtml(e.message) + '</td></tr>';
    }
}

function renderFeedbackPagination(total) {
    const el = document.getElementById('feedbackPagination');
    const totalPages = Math.ceil(total / _fbPageSize) || 1;
    if (totalPages <= 1) { el.innerHTML = '<span style="color:var(--gray-400);font-size:12px">共 ' + total + ' 条</span>'; return; }
    let html = '<span style="color:var(--gray-400);font-size:12px;margin-right:12px">共 ' + total + ' 条</span>';
    for (let i = 1; i <= totalPages; i++) {
        const cls = i === _fbPage ? 'btn-primary' : 'btn-secondary';
        html += '<button class="btn btn-sm ' + cls + '" onclick="loadFeedbacks(' + i + ')" style="margin:0 2px;min-width:32px">' + i + '</button>';
    }
    el.innerHTML = html;
}

async function viewFeedback(id) {
    try {
        // 优先从当前页缓存查找，避免拉取全量数据
        let f = _fbRecordsCache.find(x => x.id === id);
        if (!f) {
            // TODO: 后端暂无 GET /admin/feedback/:id 接口，只能拉取列表查找
            const r = await api.get('/admin/feedback?page=1&page_size=100');
            const records = (r.data && r.data.records) || [];
            f = records.find(x => x.id === id);
        }
        if (!f) { toast('反馈不存在', 'error'); return; }

        const cat = FB_CATEGORY_LABELS[f.category] || f.category;
        const st = FB_STATUS_LABELS[f.status] || FB_STATUS_LABELS[0];
        const time = new Date(f.created_at).toLocaleString('zh-CN', { hour12: false });

        const detail =
            '用户: ' + (f.username || '匿名') + '\n' +
            '提交时间: ' + time + '\n' +
            '分类: ' + cat + '\n' +
            '状态: ' + st.label + '\n' +
            '联系方式: ' + (f.contact || '未填写') + '\n' +
            '────────────────\n' +
            '反馈内容:\n' + f.content +
            (f.reply ? '\n\n────────────────\n当前回复:\n' + f.reply : '');

        alert(detail);

        const action = confirm('确定要回复这条反馈吗？\n点击"确定"输入回复内容，点击"取消"则仅修改状态。');
        let reply = f.reply || '';
        let status = f.status;
        if (action) {
            const input = prompt('请输入回复内容（用户将在客户端看到）：', f.reply || '');
            if (input === null) return; // 用户取消
            reply = input.trim();
            if (!reply) { toast('回复内容不能为空', 'error'); return; }
            status = 2; // 已回复
        } else {
            const s = prompt('修改状态（0=待处理 1=处理中 2=已回复 3=已关闭，留空取消）：', String(f.status));
            if (s === null || s === '') return;
            status = parseInt(s);
            if (isNaN(status) || status < 0 || status > 3) { toast('状态无效', 'error'); return; }
        }

        await api.put('/admin/feedback/' + id, { reply: reply, status: status });
        toast('操作成功', 'success');
        loadFeedbacks();
    } catch(e) {
        toast(e.message, 'error');
    }
}

async function replyFeedback(id, status) {
    // 兼容保留：直接弹出输入框
    const reply = prompt('请输入回复内容：', '');
    if (reply === null) return;
    if (status === 2 && !reply.trim()) { toast('回复内容不能为空', 'error'); return; }
    try {
        await api.put('/admin/feedback/' + id, { reply: reply.trim(), status: status });
        toast('操作成功', 'success');
        loadFeedbacks();
    } catch(e) {
        toast(e.message, 'error');
    }
}

async function deleteFeedback(id) {
    if (!confirm('确认删除这条反馈？此操作不可恢复。')) return;
    try {
        await api.del('/admin/feedback/' + id);
        toast('删除成功', 'success');
        loadFeedbacks();
    } catch(e) {
        toast(e.message, 'error');
    }
}

// ======== SMTP 邮件配置 ========
async function loadSMTPConfig() {
    try {
        const r = await api.get('/admin/smtp-config');
        const d = r.data || {};
        const configured = d.configured === true ||
            !!(d.host || d.username || d.from || (d.password && d.password.indexOf('****') === 0));
        $('smtpHost').value = d.host || '';
        $('smtpPort').value = d.port || (d.tls_mode === 'ssl' ? '465' : '587');
        $('smtpUsername').value = d.username || '';
        $('smtpPassword').value = '';
        $('smtpPassword').placeholder = d.password && d.password.indexOf('****') === 0 ? '已配置（留空则不修改）' : '请输入密码或授权码';
        $('smtpFrom').value = d.from || '';
        $('smtpTLSMode').value = d.tls_mode || (d.use_tls === false ? 'none' : 'starttls');
        $('smtpAuthMode').value = d.auth_mode || ((d.username || d.password) ? 'plain' : 'none');
        $('smtpInsecureSkipVerify').checked = d.insecure_skip_verify === true;
        $('smtpUseTLS').checked = d.use_tls !== false;
        syncSMTPUseTLSFromMode();
        $('smtpStatus').textContent = configured ? '✓ 已配置' : '⚠ 未配置';
        $('smtpStatus').style.color = configured ? 'var(--green)' : 'var(--orange)';
    } catch(e) {
        $('smtpStatus').textContent = '❌ 加载失败: ' + e.message;
        $('smtpStatus').style.color = 'var(--red)';
    }
}

function syncSMTPUseTLSFromMode() {
    const tlsMode = $('smtpTLSMode').value;
    $('smtpUseTLS').checked = tlsMode !== 'none';
}

function syncSMTPTLSModeFromLegacyToggle() {
    if (!$('smtpUseTLS').checked) {
        $('smtpTLSMode').value = 'none';
        return;
    }
    if ($('smtpTLSMode').value === 'none') {
        $('smtpTLSMode').value = $('smtpPort').value.trim() === '465' ? 'ssl' : 'starttls';
    }
}

async function saveSMTPConfig() {
    const body = {
        host: $('smtpHost').value.trim(),
        port: $('smtpPort').value.trim(),
        username: $('smtpUsername').value.trim(),
        password: $('smtpPassword').value,
        from: $('smtpFrom').value.trim(),
        use_tls: $('smtpUseTLS').checked,
        tls_mode: $('smtpTLSMode').value,
        auth_mode: $('smtpAuthMode').value,
        insecure_skip_verify: $('smtpInsecureSkipVerify').checked
    };
    if (!body.host) { toast('请填写 SMTP 服务器地址', 'error'); return; }
    if (!body.port) { toast('请填写端口', 'error'); return; }
    try {
        await api.put('/admin/smtp-config', body);
        toast('SMTP 配置保存成功', 'success');
        $('smtpPassword').value = '';
        loadSMTPConfig();
    } catch(e) {
        toast(e.message, 'error');
        $('smtpStatus').textContent = '❌ ' + e.message;
        $('smtpStatus').style.color = 'var(--red)';
    }
}

async function testSMTP() {
    const to = $('smtpTestTo').value.trim();
    if (!to) { toast('请输入收件邮箱', 'error'); return; }
    $('smtpTestStatus').textContent = '发送中...';
    $('smtpTestStatus').style.color = 'var(--gray-500)';
    try {
        const r = await api.post('/admin/smtp-config/test', { to: to });
        toast(r.message || '测试邮件已发送', 'success');
        $('smtpTestStatus').textContent = '✓ ' + (r.message || '已发送');
        $('smtpTestStatus').style.color = 'var(--green)';
    } catch(e) {
        toast(e.message, 'error');
        $('smtpTestStatus').textContent = '❌ ' + e.message;
        $('smtpTestStatus').style.color = 'var(--red)';
    }
}

async function loadEmailTemplates() {
    const statusEl = $('emailTemplateStatus');
    if (statusEl) {
        statusEl.textContent = '加载中...';
        statusEl.style.color = 'var(--gray-500)';
    }
    try {
        const r = await api.get('/admin/email-templates');
        const d = r.data || {};
        $('emailTplAppName').value = d.app_name || '';
        $('emailTplRegisterSubject').value = d.register_subject || '';
        $('emailTplRegisterBody').value = d.register_body || '';
        $('emailTplResetSubject').value = d.reset_subject || '';
        $('emailTplResetBody').value = d.reset_body || '';
        if (statusEl) statusEl.textContent = '';
    } catch(e) {
        if (statusEl) {
            statusEl.textContent = '加载失败: ' + e.message;
            statusEl.style.color = 'var(--red)';
        }
    }
}

async function saveEmailTemplates() {
    const statusEl = $('emailTemplateStatus');
    if (statusEl) {
        statusEl.textContent = '保存中...';
        statusEl.style.color = 'var(--gray-500)';
    }
    try {
        const r = await api.put('/admin/email-templates', {
            app_name: $('emailTplAppName').value.trim(),
            register_subject: $('emailTplRegisterSubject').value.trim(),
            register_body: $('emailTplRegisterBody').value,
            reset_subject: $('emailTplResetSubject').value.trim(),
            reset_body: $('emailTplResetBody').value
        });
        toast(r.message || '模板已保存', 'success');
        if (statusEl) {
            statusEl.textContent = r.message || '已保存';
            statusEl.style.color = 'var(--green)';
        }
    } catch(e) {
        toast(e.message, 'error');
        if (statusEl) {
            statusEl.textContent = e.message;
            statusEl.style.color = 'var(--red)';
        }
    }
}

function toggleNotifyMode() {
    const mode = $('notifyMode') ? $('notifyMode').value : 'single';
    const emailGroup = $('notifyEmailGroup');
    const idsGroup = $('notifyUserIdsGroup');
    if (emailGroup) emailGroup.style.display = mode === 'single' ? 'block' : 'none';
    if (idsGroup) idsGroup.style.display = mode === 'users' ? 'block' : 'none';
}

function parseNotifyUserIdsText(text) {
    return (text || '')
        .split(/[\s,，;；]+/)
        .map(s => s.trim())
        .filter(Boolean);
}

async function sendNotificationEmail() {
    const mode = $('notifyMode').value;
    const subject = $('notifySubject').value.trim();
    const body = $('notifyBody').value.trim();
    if (!subject || !body) { toast('请填写邮件标题和正文', 'error'); return; }
    if (mode === 'all' && !confirm('确定向全部有效用户发送这封通知邮件吗？')) return;

    const statusEl = $('notifyEmailStatus');
    statusEl.textContent = '发送中...';
    statusEl.style.color = 'var(--gray-500)';
    try {
        const r = await api.post('/admin/email/notify', {
            mode: mode,
            email: $('notifyEmail').value.trim(),
            user_ids: parseNotifyUserIdsText($('notifyUserIds').value),
            subject: subject,
            body: body
        });
        const d = r.data || {};
        const msg = '已发送 ' + (d.sent_count || 0) + ' 封，失败 ' + (d.failed_count || 0) + ' 封';
        toast(msg, d.failed_count ? 'warning' : 'success');
        statusEl.textContent = msg;
        statusEl.style.color = d.failed_count ? 'var(--orange)' : 'var(--green)';
    } catch(e) {
        toast(e.message, 'error');
        statusEl.textContent = e.message;
        statusEl.style.color = 'var(--red)';
    }
}

var _auditPageSize = 50;

async function loadAuditLogs(page) {
    if (page) _currentPage = page;
    const tbody = $('auditTableBody');
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:40px"><span class="spinner"></span> 加载中...</td></tr>';

    const action = $('auditActionFilter').value;
    const targetType = $('auditTargetFilter').value;
    const adminID = $('auditAdminFilter').value.trim();

    const params = new URLSearchParams();
    params.set('page', _currentPage);
    params.set('page_size', _auditPageSize);
    if (action) params.set('action', action);
    if (targetType) params.set('target_type', targetType);
    if (adminID) params.set('admin_id', adminID);

    try {
        const r = await api.get('/admin/audit-logs?' + params.toString());
        const logs = r.list || [];
        if (logs.length === 0) {
            tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;padding:40px;color:var(--gray-400)">暂无审计日志</td></tr>';
        } else {
            tbody.innerHTML = logs.map(log => {
                const actionLabel = auditActionLabel(log.action);
                const targetLabel = auditTargetLabel(log.target_type);
                const actionClass = auditActionClass(log.action);
                let detail = '';
                if (log.old_value && log.new_value) {
                    detail = `<span style="color:var(--gray-500)">变更</span>`;
                } else if (log.new_value) {
                    detail = `<span style="color:var(--green-600)">新增</span>`;
                } else if (log.old_value) {
                    detail = `<span style="color:var(--red)">删除</span>`;
                }
                return `<tr>
                    <td>${escHtml(log.id)}</td>
                    <td style="font-size:12px;color:var(--gray-500);white-space:nowrap">${escHtml(log.created_at ? log.created_at.substring(0, 19).replace('T', ' ') : '')}</td>
                    <td>${escHtml(log.admin_name || 'ID:' + log.admin_id)}</td>
                    <td><span class="badge badge-${actionClass}">${escHtml(actionLabel)}</span></td>
                    <td>${escHtml(targetLabel)}</td>
                    <td style="font-family:monospace;font-size:12px">${escHtml(log.target_id)}</td>
                    <td style="max-width:300px">
                        <div style="cursor:pointer;color:var(--primary)" onclick="showAuditDetail(${log.id})">${detail || '查看详情'}</div>
                    </td>
                    <td style="font-family:monospace;font-size:12px;color:var(--gray-500)">${escHtml(log.ip_address)}</td>
                </tr>`;
            }).join('');
        }
        $('auditPagination').innerHTML = renderPagination(r.total || 0, 'loadAuditLogs');
    } catch(e) {
        tbody.innerHTML = `<tr><td colspan="8" style="text-align:center;padding:40px;color:var(--red)">加载失败: ${escHtml(e.message)}</td></tr>`;
    }
}

function auditActionLabel(action) {
    const map = {
        create:'创建', update:'更新', delete:'删除',
        approve:'审核通过', reject:'审核拒绝',
        take_down:'下架', restore:'恢复',
        reset_password:'重置密码', reset_test:'重置测试',
        grant_subscription:'分配订阅', revoke_subscription:'撤销订阅',
        update_config:'更新配置',
        login:'登录', logout:'登出',
        send_email:'发送邮件', other:'其他'
    };
    return map[action] || action;
}

function auditTargetLabel(type) {
    const map = {
        user:'用户', network_agent:'网络智能体', network_group:'网络群聊',
        subscription:'订阅', system_config:'系统配置',
        api_key:'API密钥', subscription_plan:'订阅计划',
        model_price:'模型定价', app_version:'应用版本',
        activity:'活动', ifdian:'爱发电', device:'设备', system:'系统'
    };
    return map[type] || type;
}

function auditActionClass(action) {
    if (action === 'create' || action === 'approve' || action === 'grant_subscription') return 'success';
    if (action === 'delete' || action === 'reject' || action === 'take_down' || action === 'revoke_subscription') return 'danger';
    if (action === 'update' || action === 'update_config' || action === 'reset_password') return 'warning';
    return 'info';
}

function showAuditDetail(id) {
    const tbody = $('auditTableBody');
    const rows = tbody.querySelectorAll('tr');
    let targetLog = null;

    const action = $('auditActionFilter').value;
    const targetType = $('auditTargetFilter').value;
    const adminID = $('auditAdminFilter').value.trim();

    const params = new URLSearchParams();
    params.set('page', _currentPage);
    params.set('page_size', _auditPageSize);
    if (action) params.set('action', action);
    if (targetType) params.set('target_type', targetType);
    if (adminID) params.set('admin_id', adminID);

    api.get('/admin/audit-logs?' + params.toString()).then(r => {
        const log = (r.list || []).find(l => l.id === id);
        if (!log) return;
        let oldVal = log.old_value ? JSON.stringify(JSON.parse(log.old_value), null, 2) : '(无)';
        let newVal = log.new_value ? JSON.stringify(JSON.parse(log.new_value), null, 2) : '(无)';
        alert(
            '操作: ' + auditActionLabel(log.action) + '\n' +
            '对象: ' + auditTargetLabel(log.target_type) + ' #' + log.target_id + '\n' +
            '管理员: ' + (log.admin_name || 'ID:' + log.admin_id) + '\n' +
            '时间: ' + (log.created_at || '') + '\n' +
            'IP: ' + (log.ip_address || '') + '\n\n' +
            '--- 变更前 ---\n' + oldVal + '\n\n' +
            '--- 变更后 ---\n' + newVal
        );
    }).catch(e => {
        alert('加载详情失败: ' + e.message);
    });
}

function escHtml(s) {
    if (s == null) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
// escAttr 用于 onclick="fn('...')" 内的 JS 字符串字面量转义。
// escHtml 不适用于此场景：HTML 属性解析会把 &#39; 解码回 '，导致 JS 字符串被闭合。
// 顺序：先 JS 转义（\ 和 '），再 HTML 转义（& " < >），避免引入的实体被二次转义。
function escAttr(s) {
    if (s == null) return '';
    return String(s)
        .replace(/\\/g, '\\\\')
        .replace(/'/g, "\\'")
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}
