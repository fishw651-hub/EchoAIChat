var _currentPage = 1, _pageSize = 15;

if (!localStorage.getItem('admin_token')) { window.location.href = 'login.html'; }

window.addEventListener('load', () => {
    document.getElementById('adminName').textContent = localStorage.getItem('admin_name') || 'Admin';
    document.querySelectorAll('.sidebar-nav a').forEach(a => a.addEventListener('click', navClick));
    document.getElementById('btnLogout').addEventListener('click', logout);
    document.getElementById('mobileToggle').addEventListener('click', () => {
        document.getElementById('sidebar').classList.toggle('open');
    });
    document.querySelectorAll('.section-panel').forEach(p => p.addEventListener('click', () => {
        document.getElementById('sidebar').classList.remove('open');
    }));
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
        dashboard:'仪表盘', users:'用户管理', agents:'智能体管理',
        apikeys:'API密钥', models:'模型定价', plans:'订阅计划',
        config:'系统配置', orders:'订单管理'
    };
    document.getElementById('topbarTitle').textContent = titles[name] || name;
    document.getElementById('sidebar').classList.remove('open');

    _currentPage = 1;
    switch(name) {
        case 'dashboard': loadDashboard(); break;
        case 'users': loadUsers(); break;
        case 'agents': loadAgents(); break;
        case 'apikeys': loadAPIKeys(); break;
        case 'models': loadModelPrices(); break;
        case 'plans': loadPlans(); break;
        case 'config': loadConfig(); break;
        case 'orders': loadOrders(); break;
    }
}

function logout() {
    localStorage.removeItem('admin_token');
    window.location.href = 'login.html';
}

/* ========== 工具函数 ========== */
function $(id) { return document.getElementById(id); }
function toast(msg, type) {
    const c = $('toastContainer');
    const t = document.createElement('div');
    t.className = 'toast toast-' + type;
    t.textContent = msg;
    c.appendChild(t);
    setTimeout(() => t.remove(), 3000);
}
function formatNum(n) { return Number(n).toFixed ? Number(n).toFixed(4) : n; }
function formatDate(s) { if (!s) return '-'; return s.substring(0, 10); }
function renderPagination(total, onPage) {
    const totalPages = Math.ceil(total / _pageSize);
    return `<button ${_currentPage<=1?'disabled':''} onclick="event.preventDefault();gotoPage(${_currentPage-1},'${onPage}')">上一页</button>
    <span class="page-info">${_currentPage} / ${totalPages||1}（共${total}条）</span>
    <button ${_currentPage>=totalPages?'disabled':''} onclick="event.preventDefault();gotoPage(${_currentPage+1},'${onPage}')">下一页</button>`;
}
function gotoPage(p, fn) { _currentPage = p; window[fn](); }
function showModal(id) { $(id).style.display = 'flex'; }
function hideModal(id) { $(id).style.display = 'none'; }

/* ========== 仪表盘 ========== */
async function loadDashboard() {
    try {
        const r = await api.get('/admin/dashboard');
        const d = r.data;
        const html = `
            <div class="stats-row">
                <div class="stat-card"><div class="stat-icon blue">👥</div><div><div class="stat-value">${d.user_count||0}</div><div class="stat-label">总用户</div></div></div>
                <div class="stat-card"><div class="stat-icon green">🤖</div><div><div class="stat-value">${d.agent_count||0}</div><div class="stat-label">智能体</div></div></div>
                <div class="stat-card"><div class="stat-icon orange">📦</div><div><div class="stat-value">${d.plan_count||0}</div><div class="stat-label">订阅计划</div></div></div>
                <div class="stat-card"><div class="stat-icon purple">📋</div><div><div class="stat-value">${d.order_pending||0}</div><div class="stat-label">待处理订单</div></div></div>
            </div>
            <div class="stats-row">
                <div class="stat-card"><div class="stat-icon blue">📈</div><div><div class="stat-value">${formatNum(d.today_usage)}</div><div class="stat-label">今日用量（元）</div></div></div>
                <div class="stat-card"><div class="stat-icon green">💰</div><div><div class="stat-value">${formatNum(d.total_usage_cost)}</div><div class="stat-label">累计用量（元）</div></div></div>
                <div class="stat-card"><div class="stat-icon orange">🆕</div><div><div class="stat-value">${d.today_new_users||0}</div><div class="stat-label">今日新增用户</div></div></div>
            </div>`;
        $('dashboardContent').innerHTML = html;
    } catch(e) { $('dashboardContent').innerHTML = '<p class="loading">加载失败: '+e.message+'</p>'; }
}

/* ========== 用户管理 ========== */
async function loadUsers() {
    const kw = $('userSearch')?.value || '';
    try {
        const r = await api.get('/admin/users?page='+_currentPage+'&page_size='+_pageSize+'&keyword='+encodeURIComponent(kw));
        const users = r.data.records || [];
        const rows = users.map(u => `
            <tr>
                <td>${u.ID||u.id}</td>
                <td>${u.Username||u.username}</td>
                <td>${u.Nickname||u.nickname||'-'}</td>
                <td>${u.Email||u.email||'-'}</td>
                <td>${formatNum(u.Balance||u.balance)}</td>
                <td><span class="tag tag-${(u.Role||u.role)==='super_admin'?'danger':(u.Role||u.role)==='admin'?'warning':'info'}">${u.Role||u.role}</span></td>
                <td><span class="tag tag-${(u.Status||u.status)===1?'success':'danger'}">${(u.Status||u.status)===1?'正常':'禁用'}</span></td>
                <td class="actions">
                    <button class="btn btn-sm btn-secondary" onclick="editUser(${u.ID||u.id},'${u.Username||u.username}',${u.Status||u.status},'${u.Role||u.role}',${u.Balance||u.balance})">编辑</button>
                </td>
            </tr>`).join('');
        $('userTableBody').innerHTML = rows || '<tr><td colspan="8" class="text-center text-muted">暂无数据</td></tr>';
        $('userPagination').innerHTML = renderPagination(r.data.total, 'loadUsers');
    } catch(e) { toast(e.message, 'error'); }
}
function searchUsers() { _currentPage = 1; loadUsers(); }
function editUser(id, uname, status, role, balance) {
    $('editUserId').value = id;
    $('editUserUname').textContent = uname;
    $('editUserStatus').value = status;
    $('editUserRole').value = role;
    $('editUserBalance').value = balance;
    showModal('modalEditUser');
}
async function saveUser() {
    const id = $('editUserId').value;
    const status = parseInt($('editUserStatus').value);
    const role = $('editUserRole').value;
    const balance = parseFloat($('editUserBalance').value);
    try {
        await api.put('/admin/users/'+id, {status, role, balance});
        toast('保存成功', 'success');
        hideModal('modalEditUser');
        loadUsers();
    } catch(e) { toast(e.message, 'error'); }
}

/* ========== 智能体管理 ========== */
async function loadAgents() {
    try {
        const r = await api.get('/admin/agents');
        const agents = r.data || [];
        const rows = agents.map(a => `
            <tr>
                <td>${a.ID||a.id}</td>
                <td>${a.Name||a.name}</td>
                <td>${a.Model||a.model}</td>
                <td><span class="tag ${(a.IsPublic||a.is_public)?'tag-success':'tag-warning'}">${(a.IsPublic||a.is_public)?'公开':'私有'}</span></td>
                <td><span class="tag ${(a.IsOfficial||a.is_official)?'tag-info':'tag-warning'}">${(a.IsOfficial||a.is_official)?'官方':'自建'}</span></td>
                <td>${a.DownloadCount||a.download_count}</td>
                <td class="actions">
                    <button class="btn btn-sm btn-secondary" onclick="editAgent(${a.ID||a.id})">编辑</button>
                    <button class="btn btn-sm btn-danger" onclick="deleteAgent(${a.ID||a.id})">删除</button>
                </td>
            </tr>`).join('');
        $('agentTableBody').innerHTML = rows || '<tr><td colspan="7" class="text-center text-muted">暂无智能体</td></tr>';
        $('agentPagination').innerHTML = '';
    } catch(e) { toast(e.message, 'error'); }
}
function showAddAgent() {
    $('modalAgentTitle').textContent = '新增智能体';
    $('agentId').value = '';
    ['agentName','agentDesc','agentAvatar','agentPrompt','agentModel','agentTemp','agentMaxTokens','agentReasoning'].forEach(id => $(id).value = '');
    $('agentTemp').value = '1';
    $('agentMaxTokens').value = '2048';
    $('agentThinking').checked = false;
    $('agentPublic').checked = true;
    $('agentOfficial').checked = false;
    showModal('modalAgent');
}
function editAgent(id) {
    api.get('/agents/'+id).then(r => {
        const a = r.data;
        $('modalAgentTitle').textContent = '编辑智能体';
        $('agentId').value = a.id;
        $('agentName').value = a.name||'';
        $('agentDesc').value = a.description||'';
        $('agentAvatar').value = a.avatar_url||'';
        $('agentPrompt').value = a.system_prompt||'';
        $('agentModel').value = a.model||'';
        $('agentTemp').value = a.temperature||1;
        $('agentMaxTokens').value = a.max_tokens||2048;
        $('agentThinking').checked = a.thinking_enabled||false;
        $('agentReasoning').value = a.reasoning_effort||'high';
        $('agentPublic').checked = a.is_public!==false;
        $('agentOfficial').checked = a.is_official||false;
        $('agentSort').value = a.sort_order||0;
        showModal('modalAgent');
    }).catch(e => toast(e.message, 'error'));
}
async function saveAgent() {
    const body = {
        name: $('agentName').value,
        description: $('agentDesc').value,
        avatar_url: $('agentAvatar').value,
        system_prompt: $('agentPrompt').value,
        model: $('agentModel').value||'deepseek-v4-flash',
        temperature: parseFloat($('agentTemp').value)||1,
        max_tokens: parseInt($('agentMaxTokens').value)||2048,
        thinking_enabled: $('agentThinking').checked,
        reasoning_effort: $('agentReasoning').value||'high',
        is_public: $('agentPublic').checked,
        is_official: $('agentOfficial').checked,
        sort_order: parseInt($('agentSort').value)||0
    };
    const id = $('agentId').value;
    try {
        if (id) { await api.put('/admin/agents/'+id, body); }
        else { await api.post('/admin/agents', body); }
        toast('保存成功', 'success');
        hideModal('modalAgent');
        loadAgents();
    } catch(e) { toast(e.message, 'error'); }
}
async function deleteAgent(id) {
    if (!confirm('确定删除该智能体？')) return;
    try { await api.del('/admin/agents/'+id); toast('删除成功', 'success'); loadAgents(); }
    catch(e) { toast(e.message, 'error'); }
}

/* ========== API密钥 ========== */
async function loadAPIKeys() {
    try {
        const r = await api.get('/admin/api-keys');
        const keys = r.data || [];
        const rows = keys.map(k => `
            <tr>
                <td>${k.id}</td>
                <td>${k.provider}</td>
                <td>${k.name}</td>
                <td><code>${k.masked_key}</code></td>
                <td><span class="tag tag-${k.is_active?'success':'danger'}">${k.is_active?'启用':'禁用'}</span></td>
                <td class="actions">
                    <button class="btn btn-sm btn-secondary" onclick="editApiKey(${k.id},'${k.name}',${k.is_active})">编辑</button>
                    <button class="btn btn-sm btn-danger" onclick="deleteApiKey(${k.id})">删除</button>
                </td>
            </tr>`).join('');
        $('apikeyTableBody').innerHTML = rows || '<tr><td colspan="6" class="text-center text-muted">暂无密钥</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function showAddApiKey() {
    $('modalApikeyTitle').textContent = '添加API密钥';
    $('apikeyId').value = '';
    $('apikeyProvider').value = 'deepseek';
    $('apikeyName').value = '';
    $('apikeyKey').value = '';
    $('apikeyKey').type = 'text';
    showModal('modalApikey');
}
function editApiKey(id, name, active) {
    $('modalApikeyTitle').textContent = '编辑API密钥';
    $('apikeyId').value = id;
    $('apikeyName').value = name;
    $('apikeyKey').value = '';
    $('apikeyKey').type = 'password';
    $('apikeyActive').checked = active;
    showModal('modalApikey');
}
async function saveApiKey() {
    const id = $('apikeyId').value;
    const api_key = $('apikeyKey').value;
    const body = { provider: $('apikeyProvider').value, name: $('apikeyName').value, is_active: $('apikeyActive').checked };
    if (api_key) body.api_key = api_key;
    try {
        if (id) { await api.put('/admin/api-keys/'+id, body); }
        else { await api.post('/admin/api-keys', body); }
        toast('保存成功', 'success');
        hideModal('modalApikey');
        loadAPIKeys();
    } catch(e) { toast(e.message, 'error'); }
}
async function deleteApiKey(id) {
    if (!confirm('确定删除？')) return;
    try { await api.del('/admin/api-keys/'+id); toast('删除成功', 'success'); loadAPIKeys(); }
    catch(e) { toast(e.message, 'error'); }
}

/* ========== 模型定价 ========== */
async function loadModelPrices() {
    try {
        const r = await api.get('/admin/model-prices');
        const list = r.data || [];
        const rows = list.map(m => `
            <tr>
                <td>${m.ID||m.id}</td>
                <td><strong>${m.ModelID||m.model_id}</strong></td>
                <td>${formatNum(m.InputPricePer1M||m.input_price_per_1m)}</td>
                <td>${formatNum(m.InputCacheHitPricePer1M||m.input_cache_hit_price_per_1m)}</td>
                <td>${formatNum(m.OutputPricePer1M||m.output_price_per_1m)}</td>
                <td><span class="tag tag-${(m.Status||m.status)===1?'success':'danger'}">${(m.Status||m.status)===1?'启用':'停用'}</span></td>
                <td class="actions">
                    <button class="btn btn-sm btn-secondary" onclick="editPrice(${m.ID||m.id},'${m.ModelID||m.model_id}',${m.InputPricePer1M||m.input_price_per_1m},${m.InputCacheHitPricePer1M||m.input_cache_hit_price_per_1m},${m.OutputPricePer1M||m.output_price_per_1m},${m.Status||m.status})">编辑</button>
                </td>
            </tr>`).join('');
        $('modelTableBody').innerHTML = rows || '<tr><td colspan="7" class="text-center text-muted">暂无定价，请先同步</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function editPrice(id, mid, inp, cache, out, status) {
    $('priceId').value = id;
    $('priceModelId').textContent = mid;
    $('priceInput').value = inp;
    $('priceCache').value = cache;
    $('priceOutput').value = out;
    $('priceStatus').value = status;
    showModal('modalPrice');
}
async function savePrice() {
    try {
        await api.put('/admin/model-prices/'+$('priceId').value, {
            input_price_per_1m: parseFloat($('priceInput').value),
            input_cache_hit_price_per_1m: parseFloat($('priceCache').value),
            output_price_per_1m: parseFloat($('priceOutput').value),
            status: parseInt($('priceStatus').value)
        });
        toast('保存成功', 'success');
        hideModal('modalPrice');
        loadModelPrices();
    } catch(e) { toast(e.message, 'error'); }
}
async function syncModels() {
    try { await api.post('/admin/model-prices/sync'); toast('同步成功', 'success'); loadModelPrices(); }
    catch(e) { toast(e.message, 'error'); }
}

/* ========== 订阅计划 ========== */
async function loadPlans() {
    try {
        const r = await api.get('/admin/plans');
        const plans = r.data || [];
        const rows = plans.map(p => `
            <tr>
                <td>${p.ID||p.id}</td>
                <td>${p.Name||p.name}</td>
                <td>${formatNum(p.Price||p.price)} 元</td>
                <td>${formatNum(p.DailyQuota||p.daily_quota)} 元/日</td>
                <td>${p.DurationDays||p.duration_days} 天</td>
                <td><span class="tag tag-${(p.Status||p.status)===1?'success':'danger'}">${(p.Status||p.status)===1?'启用':'停用'}</span></td>
                <td class="actions">
                    <button class="btn btn-sm btn-secondary" onclick="editPlan(${p.ID||p.id})">编辑</button>
                    <button class="btn btn-sm btn-danger" onclick="deletePlan(${p.ID||p.id})">删除</button>
                </td>
            </tr>`).join('');
        $('planTableBody').innerHTML = rows || '<tr><td colspan="7" class="text-center text-muted">暂无计划</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function showAddPlan() {
    $('modalPlanTitle').textContent = '新增订阅计划';
    $('planId').value = '';
    ['planName','planDesc','planPrice','planQuota','planDays','planSort'].forEach(id => $(id).value = '');
    $('planDays').value = '30';
    showModal('modalPlan');
}
function editPlan(id) {
    api.get('/admin/plans').then(r => {
        const p = (r.data||[]).find(x => (x.ID||x.id) === id);
        if (!p) return;
        $('modalPlanTitle').textContent = '编辑订阅计划';
        $('planId').value = id;
        $('planName').value = p.Name||p.name||'';
        $('planDesc').value = p.Description||p.description||'';
        $('planPrice').value = p.Price||p.price||0;
        $('planQuota').value = p.DailyQuota||p.daily_quota||0;
        $('planDays').value = p.DurationDays||p.duration_days||30;
        $('planSort').value = p.SortOrder||p.sort_order||0;
        showModal('modalPlan');
    }).catch(e => toast(e.message, 'error'));
}
async function savePlan() {
    const body = {
        name: $('planName').value,
        description: $('planDesc').value,
        price: parseFloat($('planPrice').value),
        daily_quota: parseFloat($('planQuota').value)||0,
        duration_days: parseInt($('planDays').value)||30,
        sort_order: parseInt($('planSort').value)||0
    };
    const id = $('planId').value;
    try {
        if (id) { await api.put('/admin/plans/'+id, body); }
        else { await api.post('/admin/plans', body); }
        toast('保存成功', 'success');
        hideModal('modalPlan');
        loadPlans();
    } catch(e) { toast(e.message, 'error'); }
}
async function deletePlan(id) {
    if (!confirm('确定删除？')) return;
    try { await api.del('/admin/plans/'+id); toast('删除成功', 'success'); loadPlans(); }
    catch(e) { toast(e.message, 'error'); }
}

/* ========== 系统配置 ========== */
async function loadConfig() {
    try {
        const r = await api.get('/admin/config');
        const cfg = r.data || {};
        const rows = Object.entries(cfg).map(([k,v]) => `
            <tr>
                <td><code>${k}</code></td>
                <td>${v}</td>
                <td class="actions"><button class="btn btn-sm btn-secondary" onclick="editConfig('${k}','${v.replace(/'/g,"\\'")}')">编辑</button></td>
            </tr>`).join('');
        $('configTableBody').innerHTML = rows || '<tr><td colspan="3" class="text-center text-muted">暂无配置</td></tr>';
    } catch(e) { toast(e.message, 'error'); }
}
function editConfig(key, val) {
    $('configKey').value = key;
    $('configKey').readOnly = true;
    $('configValue').value = val;
    showModal('modalConfig');
}
function showAddConfig() {
    $('configKey').value = '';
    $('configKey').readOnly = false;
    $('configValue').value = '';
    showModal('modalConfig');
}
async function saveConfig() {
    try {
        await api.put('/admin/config', {key: $('configKey').value, value: $('configValue').value});
        toast('保存成功', 'success');
        hideModal('modalConfig');
        loadConfig();
    } catch(e) { toast(e.message, 'error'); }
}

/* ========== 订单管理 ========== */
async function loadOrders() {
    const st = $('orderStatus')?.value || '';
    try {
        const r = await api.get('/admin/orders?page='+_currentPage+'&page_size='+_pageSize+'&status='+st);
        const orders = r.data.records || [];
        const rows = orders.map(o => `
            <tr>
                <td>${o.OrderNo||o.order_no}</td>
                <td>${o.Username||o.username}</td>
                <td><span class="tag tag-info">${o.Type||o.type}</span></td>
                <td>${o.PlanName||o.plan_name||'-'}</td>
                <td>${formatNum(o.Amount||o.amount)}</td>
                <td>${formatNum(o.ActualAmount||o.actual_amount)}</td>
                <td><span class="tag tag-${(o.Status||o.status)==='paid'?'success':(o.Status||o.status)==='pending'?'warning':'danger'}">${o.Status||o.status}</span></td>
                <td>${o.PaymentType||o.payment_type||'-'}</td>
                <td>${formatDate(o.CreatedAt||o.created_at)}</td>
            </tr>`).join('');
        $('orderTableBody').innerHTML = rows || '<tr><td colspan="9" class="text-center text-muted">暂无订单</td></tr>';
        $('orderPagination').innerHTML = renderPagination(r.data.total, 'loadOrders');
    } catch(e) { toast(e.message, 'error'); }
}
function filterOrders() { _currentPage = 1; loadOrders(); }
