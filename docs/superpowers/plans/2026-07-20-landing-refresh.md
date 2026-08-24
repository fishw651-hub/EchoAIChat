# Landing Page Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重建回响官网落地页，使其具有沉浸式品牌感、清晰产品叙事和完整手机/电脑自适应。

**Architecture:** 使用语义 HTML、独立静态 CSS 和独立原生 JS；复用现有 favicon 与 `hero-main.jpg`，删除浏览器端 Tailwind 和 Lucide CDN。

**Tech Stack:** HTML5、CSS3、原生 JavaScript、内联静态 SVG。

## Global Constraints

- 保留 SEO 元数据、结构化数据、动态版本查询和平台下载逻辑。
- 页面不依赖 Tailwind 运行时或外部图标 CDN。
- 断点为 640px、1024px、1440px。
- 支持浅色/深色、键盘、减少动画和无 JavaScript 核心降级。
- 不提交 Git commit。

---

### Task 1: 语义页面结构

**Files:**
- Modify: `website/API/landing/index.html`
- Create: `website/API/landing/css/landing.css`
- Create: `website/API/landing/js/landing.js`

**Interfaces:**
- Preserves: `[data-app-version]`、`[data-download-link]`、`#themeToggle`、`#menuToggle`。
- Produces: `loadLatestAndroidVersion()` 与 `fetchLatestVersion(platform)`。

- [ ] **Step 1: 重写页面结构**

按导航、首屏、信任条、核心能力、三层记忆、群聊场景、隐私掌控、下载 CTA、页脚组织；首屏桌面双栏、手机单列。所有装饰 SVG 标记 `aria-hidden="true"`。

- [ ] **Step 2: 保留 SEO 和降级链接**

保留 canonical、Open Graph、Twitter Card 和 SoftwareApplication JSON-LD；静态下载链接继续指向当前 Android 下载端点，JS 成功后再替换为最新版本。

- [ ] **Step 3: 清除运行时 CDN**

删除 `@tailwindcss/browser`、Lucide CDN、`text/tailwindcss` 和所有 Tailwind utility class。

### Task 2: 品牌样式与响应式

**Files:**
- Modify: `website/API/landing/css/landing.css`

**Interfaces:**
- Produces: `.site-header`、`.hero`、`.bento-grid`、`.memory-flow`、`.conversation-stage`、`.download-panel`。

- [ ] **Step 1: 建立主题 token**

定义雾蓝、深海蓝、暖珊瑚、表面、文字、边框、状态层、8px 间距、14/20/28px 圆角和三档阴影；深色主题使用独立语义值。

- [ ] **Step 2: 实现桌面布局**

最大内容宽度 1180px；首屏 1.05fr/0.95fr；Bento 12 列；记忆流三列；群聊场景左右分栏。

- [ ] **Step 3: 实现平板与手机布局**

`<1024px` 首屏和场景改单列，Bento 双列；`<640px` 全部单列、CTA 全宽、导航抽屉、标题使用 `clamp`，无横向滚动。

- [ ] **Step 4: 可访问性与动效**

增加 `:focus-visible`、跳到主内容链接、44px 触控目标和 `prefers-reduced-motion`；仅对回声轨迹和进入视口元素使用 transform/opacity。

### Task 3: 交互脚本与验证

**Files:**
- Modify: `website/API/landing/js/landing.js`

**Interfaces:**
- Consumes: `/api/v1/update/versions?platform=android|ios`

- [ ] **Step 1: 实现主题、菜单和滚动交互**

主题默认跟随系统并允许持久化覆盖；菜单维护 `aria-expanded`；锚点使用原生平滑滚动并尊重减少动画。

- [ ] **Step 2: 实现版本和下载逻辑**

请求失败时静默保留静态版本；iOS 用户下载时优先查 iOS 版本，未发布则显示明确提示。

- [ ] **Step 3: 静态检查**

Run: `node --check website/API/landing/js/landing.js`

Expected: 无输出，退出码 0。

Run: `rg -n "tailwindcss|unpkg.com/lucide|text/tailwindcss" website/API/landing/index.html`

Expected: 无匹配。

