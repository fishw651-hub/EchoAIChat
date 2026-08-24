# Admin UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将生产管理后台升级为回响品牌化、响应式运营工作台，并展示 DAU 趋势。

**Architecture:** 保留现有原生 HTML/JS 和全部业务 DOM ID；通过共享 CSS token 重建页面骨架，通过静态 SVG 图标和原生 SVG 图表替代 Emoji 与外部图表库。

**Tech Stack:** HTML5、CSS3、原生 JavaScript、SVG。

## Global Constraints

- 只修改 `website/API/admin/`，不修改弃用目录。
- 所有用户数据进入 HTML 前继续使用 `escHtml`/`escAttr`。
- 图表不引入 CDN 或第三方依赖。
- 手机触控目标至少 44px，支持键盘焦点和减少动画。
- 不提交 Git commit。

---

### Task 1: 共享设计 token 与响应式骨架

**Files:**
- Modify: `website/API/admin/css/common.css`
- Modify: `website/API/admin/css/admin.css`
- Modify: `website/API/admin/index.html`

**Interfaces:**
- Produces: `--echo-*` 颜色、间距、圆角、阴影和动效 token。
- Preserves: `.sidebar`、`.main-area`、`.topbar`、`.section-panel` 及所有现有 ID。

- [ ] **Step 1: 重建 token 与基础控件**

定义浅色雾蓝表面、深海侧栏、珊瑚点缀、44px 控件高度、三档阴影与 8px 间距节奏；统一按钮、输入框、标签、弹窗、Toast 和焦点状态。

- [ ] **Step 2: 重构导航骨架**

把品牌图标改为真实 favicon，结构图标改为静态 SVG；桌面侧栏 248px，`<=1024px` 紧凑，`<=760px` 抽屉 + 遮罩。顶部栏增加当前页副标题与服务状态但保留原有退出入口。

- [ ] **Step 3: 优化数据页面**

表格容器提供横向滚动、粘性表头、操作按钮换行和窄屏安全宽度；工具栏在手机纵向堆叠；弹窗最大高度使用 `min(86vh, ...)` 并保持操作区可见。

- [ ] **Step 4: 静态回归检查**

Run: `rg -n "id=\"(section-dashboard|dashboardContent|sidebar|topbarTitle)\"" website/API/admin/index.html`

Expected: 原有业务入口 ID 全部存在。

### Task 2: DAU 仪表盘与原生 SVG 图表

**Files:**
- Modify: `website/API/admin/js/app.js`
- Modify: `website/API/admin/css/admin.css`

**Interfaces:**
- Consumes: `GET /admin/dashboard?days=N`
- Produces: `loadDashboard(days = dashboardRange)`
- Produces: `renderDauChart(points, summary)`

- [ ] **Step 1: 重构 Dashboard 渲染**

建立静态 `iconSvg(name)` 白名单，指标卡不再输出 Emoji。增加 7/30/90 天分段按钮、加载骨架、错误重试和今日 DAU/昨日对比/峰值/平均值摘要。

- [ ] **Step 2: 实现 SVG 折线图**

`renderDauChart` 将数据映射到 `viewBox="0 0 760 280"`，输出网格、面积、折线、数据点和日期标签；零数据输出水平基线；每个点使用可聚焦 `<button>` 外层或 `tabindex="0"` SVG 元素与 `<title>`。

- [ ] **Step 3: 增加图表响应式样式**

桌面图表高度 320px，手机 240px；范围按钮可横向滚动；`prefers-reduced-motion` 下关闭折线入场动画。

- [ ] **Step 4: 前端语法检查**

Run: `node --check website/API/admin/js/app.js`

Expected: 无输出，退出码 0。

### Task 3: 登录页和全后台视觉收口

**Files:**
- Modify: `website/API/admin/login.html`
- Modify: `website/API/admin/css/common.css`
- Modify: `website/API/admin/css/admin.css`

**Interfaces:**
- Preserves: `/api/v1/auth/login` 与 `admin_token` 登录流程。

- [ ] **Step 1: 重构登录页**

使用品牌背景、真实 logo、明确标签、密码自动填充属性、加载状态和内联错误；不改变接口参数。

- [ ] **Step 2: 清理结构 Emoji**

导航与仪表盘全部使用 SVG；业务文本中的 Emoji 不做无关修改。

- [ ] **Step 3: 完整静态检查**

Run: `node --check website/API/admin/js/app.js && node --check website/API/admin/js/api.js`

Expected: 两个脚本语法通过。

