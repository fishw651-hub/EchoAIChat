# AIchat API 调用文档

## 基础信息

| 项目 | 值 |
|------|-----|
| 基础URL | `http://localhost:8080/api/v1` |
| 认证方式 | `Authorization: Bearer <token>` |
| 内容类型 | `application/json` |
| 统一响应 | `{"code": 0, "message": "success", "data": {}}` |

### 响应码

| Code | 含义 |
|------|------|
| 0 | 成功 |
| 40000 | 参数错误 |
| 40100 | 未登录 / Token过期 |
| 40300 | 无权限 |
| 40400 | 资源不存在 |
| 42900 | 请求频繁 |
| 50000 | 服务器错误 |

---

## 一、公开接口（无需 Token）

### 1.1 用户注册

```
POST /auth/register
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| username | string | ✅ | 用户名，3-64字符 |
| email | string | ✅ | 邮箱 |
| password | string | ✅ | 密码，最少6位 |

**请求示例：**
```json
{
  "username": "testuser",
  "email": "test@example.com",
  "password": "123456"
}
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 2,
    "username": "testuser",
    "nickname": "testuser"
  }
}
```

---

### 1.2 用户登录

```
POST /auth/login
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| username | string | ✅ | 用户名 |
| password | string | ✅ | 密码 |

**请求示例：**
```json
{
  "username": "testuser",
  "password": "123456"
}
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "id": 2,
    "username": "testuser",
    "nickname": "testuser",
    "avatar_url": "",
    "role": "user",
    "balance": 0
  }
}
```

> `token` 请在后续请求中加入 Header：`Authorization: Bearer <token>`

---

### 1.3 获取可用模型列表

```
GET /models
```

无需参数。

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "models": [
      {
        "id": "deepseek-v4-flash",
        "name": "deepseek-v4-flash",
        "input_price_per_1m": 1.5,
        "input_cache_hit_price_per_1m": 0.03,
        "output_price_per_1m": 3
      },
      {
        "id": "deepseek-v4-pro",
        "name": "deepseek-v4-pro",
        "input_price_per_1m": 4.5,
        "input_cache_hit_price_per_1m": 0.0375,
        "output_price_per_1m": 9
      }
    ]
  }
}
```

> 价格单位为 **每百万 tokens**。此处价格已含利润加价（后台可调）。

---

### 1.4 支付异步回调（小时光推送）

```
POST /payment/notify
GET  /payment/notify
```

此为小时光支付平台服务器回调地址，**无需调用方主动请求**。流程：
1. 用户支付成功 → 小时光POST/GET到 `notify_url`
2. 后端验签 `trade_status==TRADE_SUCCESS` + MD5签名比对
3. 一致则更新订单状态、激活订阅或充值余额
4. 返回 `success` 给小时光

---

### 1.5 支付同步跳转

```
GET /payment/return
```

用户支付完成后浏览器跳转地址，展示简单结果页。

---

## 二、用户接口（需要 Token）

> 所有接口携带 Header：`Authorization: Bearer <token>`

### 2.1 获取个人信息

```
GET /user/profile
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "user": {
      "id": 2,
      "username": "testuser",
      "email": "test@example.com",
      "nickname": "小明",
      "avatar_url": "/uploads/avatars/xxx.png",
      "balance": 10.5,
      "daily_quota_used": 0.2,
      "daily_quota_left": 1.3,
      "role": "user",
      "status": 1
    }
  }
}
```

---

### 2.2 修改个人信息

```
PUT /user/profile
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| nickname | string | ❌ | 昵称 |
| avatar_url | string | ❌ | 头像路径 |

**请求示例：**
```json
{
  "nickname": "小明",
  "avatar_url": "/uploads/avatars/abc.png"
}
```

---

### 2.3 修改密码

```
PUT /user/password
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| old_password | string | ✅ | 原密码 |
| new_password | string | ✅ | 新密码，最少6位 |

```json
{
  "old_password": "123456",
  "new_password": "newpass123"
}
```

---

### 2.4 头像上传

```
POST /user/avatar
Content-Type: multipart/form-data
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| avatar | file | ✅ | 图片文件，最大5MB，支持jpg/jpeg/png/gif/webp |

**curl示例：**
```bash
curl -X POST http://localhost:8080/api/v1/user/avatar \
  -H "Authorization: Bearer <token>" \
  -F "avatar=@C:\Users\me\avatar.png"
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "avatar_url": "/uploads/avatars/a1b2c3d4.png"
  }
}
```

---

### 2.5 查询余额

```
GET /user/balance
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "balance": 10.5,
    "daily_quota_used": 0.2,
    "daily_quota_left": 1.3
  }
}
```

| 字段 | 说明 |
|------|------|
| balance | 账户余额（元），永久有效 |
| daily_quota_used | 今日已用额度 |
| daily_quota_left | 今日剩余可用额度（配额+订阅合计，次日清零） |

---

### 2.5.1 刷新每日额度

```
POST /user/daily-allowance/refresh
```

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "can_checkin": true,
    "checked_in_today": false,
    "has_subscription": false
  }
}
```

| 字段 | 说明 |
|------|------|
| can_checkin | 是否可以签到 |
| checked_in_today | 今日是否已签到 |
| has_subscription | 是否有有效订阅 |

---

### 2.5.2 每日额度规则

```
POST /user/daily-allowance/refresh
```

无需请求体。

**响应示例（成功）：**
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "balance": 10.70,
    "reward": 0.20,
    "has_subscription": false
  }
}
```

| 字段 | 说明 |
|------|------|
| balance | 签到后账户余额 |
| reward | 本次签到奖励金额（默认0.2元） |
| has_subscription | 是否有有效订阅 |

**规则：**
- 仅有**无有效订阅**的用户可以签到
- 每天仅可签到一次
- 奖励金额由后台 `checkin_reward` 配置控制，默认 0.2 元
- 已订阅用户签到返回 `"已订阅用户无需签到，您已享受每日配额"`
- 重复签到返回 `"今日已签到，明天再来"`

---

### 2.6 我的订阅列表

```
GET /user/subscriptions
```

**响应示例：**
```json
{
  "code": 0,
  "message": "success",
  "data": [
    {
      "id": 1,
      "user_id": 2,
      "plan_id": 1,
      "plan_name": "基础会员",
      "daily_quota": 2,
      "started_at": "2026-06-18",
      "expires_at": "2026-07-18",
      "status": 1,
      "created_at": "2026-06-18T10:00:00Z"
    }
  ]
}
```

---

### 2.7 用量历史

```
GET /user/usage?page=1&page_size=20
```

| 参数 | 类型 | 必填 | 默认 | 说明 |
|------|------|------|------|------|
| page | int | ❌ | 1 | 页码 |
| page_size | int | ❌ | 20 | 每页条数，最大100 |

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "total": 156,
    "page": 1,
    "page_size": 20,
    "records": [
      {
        "id": 1001,
        "user_id": 2,
        "username": "testuser",
        "model": "deepseek-v4-flash",
        "prompt_tokens": 150,
        "prompt_cache_hit": 50,
        "prompt_cache_miss": 100,
        "completion_tokens": 200,
        "cost": 0.00075,
        "balance_after": 10.49925,
        "created_at": "2026-06-18T12:30:00Z"
      }
    ]
  }
}
```

> `cost` 是此次调用的实际扣费金额（元）

---

### 2.8 订阅计划列表

```
GET /plans
```

**响应示例：**
```json
{
  "code": 0,
  "data": [
    {
      "id": 1,
      "name": "基础会员",
      "description": "每日2元额度，适合轻度使用",
      "price": 9.9,
      "daily_quota": 2,
      "duration_days": 30,
      "status": 1,
      "sort_order": 1
    },
    {
      "id": 2,
      "name": "高级会员",
      "description": "每日10元额度，畅快使用",
      "price": 29.9,
      "daily_quota": 10,
      "duration_days": 30,
      "status": 1,
      "sort_order": 2
    }
  ]
}
```

---

### 2.9 发起订阅支付

```
POST /payment/subscribe
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| plan_id | uint | ✅ | 订阅计划ID |
| payment_type | string | ✅ | 支付通道：`alipay` / `wxpay` / `qqpay` / `tenpay` |

**请求示例：**
```json
{
  "plan_id": 1,
  "payment_type": "alipay"
}
```

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "pay_url": "https://api.xiaoshiguang.com/pay/submit?money=9.90&name=基础会员&notify_url=..."
  }
}
```

> 将用户引导到 `pay_url` 完成支付。支付成功后小时光会异步通知后端，自动激活订阅。

---

### 2.10 发起零落支付（余额充值）

```
POST /payment/zero-drop
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| amount | float64 | ✅ | 充值金额（元），>0 |
| payment_type | string | ✅ | 支付通道：`alipay` / `wxpay` / `qqpay` / `tenpay` |

**请求示例：**
```json
{
  "amount": 10,
  "payment_type": "wxpay"
}
```

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "pay_url": "https://api.xiaoshiguang.com/pay/submit?money=10.00&name=余额充值&..."
  }
}
```

---

### 2.11 公开智能体列表

```
GET /agents
```

**响应示例：**
```json
{
  "code": 0,
  "data": [
    {
      "id": 1,
      "name": "编程助手",
      "description": "精通各种编程语言的AI助手",
      "avatar_url": "",
      "model": "deepseek-v4-pro",
      "is_official": true,
      "download_count": 128
    }
  ]
}
```

---

### 2.12 智能体详情（含提示词）

```
GET /agents/:id
```

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "id": 1,
    "name": "编程助手",
    "description": "精通各种编程语言的AI助手",
    "avatar_url": "",
    "system_prompt": "你是一个专业的编程助手，精通Python、Go、Java等语言...",
    "model": "deepseek-v4-pro",
    "temperature": 0.7,
    "max_tokens": 4096,
    "thinking_enabled": true,
    "reasoning_effort": "high",
    "is_official": true,
    "download_count": 128
  }
}
```

---

### 2.13 下载智能体（计数+1）

```
POST /agents/:id/download
```

返回内容同详情接口，`download_count` 会 +1。

---

### 2.14 AI对话（非流式）

```
POST /chat/completions
```

服务端向模型供应商发起非流式请求，等待完整结果后再返回 JSON。客户端应在收到完整响应后自行实现打字动画；动画过程中不得再次请求补全接口。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| model | string | ✅ | 模型ID，如 `deepseek-v4-flash` |
| messages | array | ✅ | 对话消息 |
| max_tokens | int | ❌ | 最大token数 |
| temperature | float64 | ❌ | 随机性 0-2，默认1 |
| top_p | float64 | ❌ | 核采样 0-1 |
| thinking | object | ❌ | `{"type": "enabled"}` 开启思考模式 |
| reasoning_effort | string | ❌ | `high` 或 `max`（需 thinking 开启） |

**基础对话请求：**
```json
{
  "model": "deepseek-v4-flash",
  "messages": [
    {"role": "user", "content": "你好，请介绍一下自己"}
  ]
}
```

**思考模式请求：**
```json
{
  "model": "deepseek-v4-pro",
  "messages": [
    {"role": "user", "content": "9.11和9.8哪个更大？"}
  ],
  "thinking": {"type": "enabled"},
  "reasoning_effort": "high"
}
```

> ⚠️ 思考模式下 `temperature` / `top_p` 参数无效。

**响应示例（思考模式）：**
```json
{
  "code": 0,
  "data": {
    "id": "chatcmpl-xxx",
    "model": "deepseek-v4-pro",
    "choices": [
      {
        "index": 0,
        "message": {
          "role": "assistant",
          "content": "9.8 小于 9.11，因为 9.11 的十分位是1而9.8的十分位是8...",
          "reasoning_content": "首先比较整数部分：都是9。比较十分位：9.8的十分位是8，9.11的十分位是1..."
        },
        "finish_reason": "stop"
      }
    ],
    "usage": {
      "prompt_tokens": 20,
      "completion_tokens": 150,
      "total_tokens": 170,
      "prompt_cache_hit_tokens": 0,
      "prompt_cache_miss_tokens": 20
    },
    "cost": 0.00051,
    "balance_after": 10.49949
  }
}
```

| 字段 | 说明 |
|------|------|
| `message.content` | 最终回答 |
| `message.reasoning_content` | 思维链内容（仅思考模式返回） |
| `usage.prompt_cache_hit_tokens` | 缓存命中的token数 |
| `usage.prompt_cache_miss_tokens` | 缓存未命中的token数 |
| `cost` | 此次调用扣费金额（元） |
| `balance_after` | 扣费后账户余额（元） |

**常见错误响应：**

```json
// 上游限流（HTTP 429；响应可能携带 Retry-After）
{
  "code": 42900,
  "message": "上游请求过于频繁，请稍后重试",
  "data": null
}

// 其他上游失败或上游配置不可用（HTTP 502）
{
  "code": 50200,
  "message": "上游服务暂时不可用，请稍后重试",
  "data": null
}

// 模型不被订阅允许（如只允许flash但用了pro）
{
  "code": 40000,
  "message": "当前订阅不支持模型 deepseek-v4-pro",
  "data": {
    "mistake": "model_not_allowed",
    "model": "deepseek-v4-pro",
    "allowed_models": ["deepseek-v4-flash"],
    "thinking": false
  }
}

// 无订阅用户使用Pro模型
{
  "code": 40000,
  "message": "当前订阅不支持模型 deepseek-v4-pro",
  "data": {
    "mistake": "model_not_allowed",
    "model": "deepseek-v4-pro",
    "allowed_models": [],
    "thinking": false
  }
}

// 模型允许但禁止思考模式
{
  "code": 40000,
  "message": "当前订阅不支持模型 deepseek-v4-flash",
  "data": {
    "mistake": "thinking_not_allowed",
    "model": "deepseek-v4-flash",
    "allowed_models": ["deepseek-v4-flash", "deepseek-v4-pro"],
    "thinking": true
  }
}

// 余额不足
{
  "code": 50000,
  "message": "余额不足，需要0.000510元，当前余额0.000100元",
  "data": {
    "mistake": "balance_insufficient",
    "required": 0.00051,
    "current": 0.0001
  }
}
```

| `data.mistake` 值 | 含义 | 客户端处理建议 |
|------|------|------|
| `model_not_allowed` | 订阅套餐不允许此模型，或无订阅用户使用了Pro模型 | 提示用户升级套餐或切换模型 |
| `thinking_not_allowed` | 不允许在此模型上使用思考模式 | 关闭思考模式重试 |
| `balance_insufficient` | 余额不足 | 引导用户充值 |

> **客户端可根据 `data.mistake` 精确判断错误类型，无需解析 `message` 字符串。**

---

### 2.15 AI对话（旧版 SSE 兼容端点）

```
POST /chat/completions/stream
```

参数同 `2.14`。该端点仅用于旧客户端兼容：服务端仍以非流式方式请求模型供应商，完成计费与配额提交后，再把完整结果一次性编码为 SSE 外形返回。因此它不提供实时上游增量，也不会逐字延迟输出。

新客户端必须使用 `POST /chat/completions`，收到完整 JSON 后在本地模拟打字。若上游在输出前返回 429 或其他错误，本端点会直接返回与 `2.14` 相同的 HTTP 429/502 JSON，不会提前写入 SSE 200 响应头。

**curl示例：**
```bash
curl -X POST http://localhost:8080/api/v1/chat/completions/stream \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"你好"}]}'
```

**兼容 SSE 响应格式：**
```
data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","model":"deepseek-v4-flash","choices":[{"index":0,"delta":{"role":"assistant","content":"你好，我能为你做什么？"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":9,"prompt_cache_hit_tokens":5,"prompt_cache_miss_tokens":5}}

data: [DONE]

data: {"finish_reason":"stop","cost":0.000123}
```

> 完整响应只会输出一个补全数据帧；`[DONE]` 后的计费帧为旧客户端兼容格式。计费与配额提交在开始输出这些帧之前已经完成。

---

## 三、管理后台接口（需要 Token + Admin 角色）

> 管理员角色：`admin` 或 `super_admin`
>
> 默认超级管理员：`admin` / `admin123`

### 3.1 仪表盘

```
GET /admin/dashboard
```

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "user_count": 125,
    "agent_count": 8,
    "plan_count": 3,
    "order_pending": 5,
    "total_usage_cost": 1234.56,
    "today_usage": 45.67,
    "today_new_users": 3
  }
}
```

---

### 3.2 用户管理

#### 3.2.1 用户列表

```
GET /admin/users?page=1&page_size=20&keyword=test
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| page | int | ❌ | 页码 |
| page_size | int | ❌ | 每页条数 |
| keyword | string | ❌ | 搜索用户名/邮箱/昵称 |

#### 3.2.2 用户详情

```
GET /admin/users/:id
```

#### 3.2.3 修改用户

```
PUT /admin/users/:id
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| status | int | ❌ | 0禁用 / 1正常 |
| role | string | ❌ | user / admin / super_admin |
| balance | float64 | ❌ | 直接设置余额 |

```json
{
  "status": 0,
  "role": "user",
  "balance": 100
}
```

---

#### 3.2.4 创建用户

```
POST /admin/users
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| username | string | ✅ | 用户名 |
| password | string | ✅ | 密码，最少6位 |
| email | string | ❌ | 邮箱 |
| nickname | string | ❌ | 昵称（默认同用户名） |
| role | string | ❌ | user/admin/super_admin（默认user） |
| balance | float64 | ❌ | 初始余额（默认0） |

```json
{
  "username": "newuser",
  "password": "123456",
  "email": "new@example.com",
  "nickname": "新用户",
  "role": "user",
  "balance": 10
}
```

#### 3.2.5 删除用户

```
DELETE /admin/users/:id
```

> 无法删除超级管理员账户。

#### 3.2.6 分配订阅

```
POST /admin/users/:id/subscription
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| plan_id | uint | ✅ | 订阅计划ID |
| daily_quota | float64 | ❌ | 每日配额（默认取计划值） |
| duration_days | int | ❌ | 有效期天数（默认取计划值） |

```json
{
  "plan_id": 1,
  "daily_quota": 5,
  "duration_days": 30
}
```

---

### 3.3 智能体管理

#### 3.3.1 全部智能体列表

```
GET /admin/agents
```

#### 3.3.2 创建智能体

```
POST /admin/agents
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | ✅ | 名称 |
| system_prompt | string | ✅ | 系统提示词 |
| description | string | ❌ | 描述 |
| avatar_url | string | ❌ | 头像URL |
| model | string | ❌ | 默认模型（默认 deepseek-v4-flash） |
| temperature | float64 | ❌ | 温度（默认1） |
| max_tokens | int | ❌ | 最大token（默认2048） |
| thinking_enabled | bool | ❌ | 开启思考模式 |
| reasoning_effort | string | ❌ | high / max |
| is_public | bool | ❌ | 公开可见（默认true） |
| is_official | bool | ❌ | 官方智能体（默认false） |
| sort_order | int | ❌ | 排序 |

```json
{
  "name": "翻译专家",
  "system_prompt": "你是一个专业的翻译助手，精通中英日韩四语...",
  "description": "多语种翻译专家",
  "model": "deepseek-v4-pro",
  "thinking_enabled": true,
  "reasoning_effort": "high",
  "is_official": true,
  "sort_order": 10
}
```

#### 3.3.3 编辑智能体

```
PUT /admin/agents/:id
```

参数同创建。

#### 3.3.4 删除智能体

```
DELETE /admin/agents/:id
```

---

### 3.4 API Key 管理

#### 3.4.1 API Key 列表（脱敏）

```
GET /admin/api-keys
```

**响应示例：**
```json
{
  "code": 0,
  "data": [
    {
      "id": 1,
      "provider": "deepseek",
      "name": "我的Key",
      "masked_key": "abcd****",
      "is_active": true
    }
  ]
}
```

> `api_key` 原文永远不会返回，仅返回脱敏标识。

#### 3.4.2 添加 API Key

```
POST /admin/api-keys
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| provider | string | ✅ | 供应商（如 `deepseek`） |
| name | string | ✅ | 标识名 |
| api_key | string | ✅ | DeepSeek API Key 原文 |

```json
{
  "provider": "deepseek",
  "name": "主Key",
  "api_key": "sk-xxxxxxxxxxxxxxxx"
}
```

> Key 以 AES-256-GCM 加密存储，永不泄密。

#### 3.4.3 编辑 API Key

```
PUT /admin/api-keys/:id
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | ❌ | 新标识名 |
| api_key | string | ❌ | 新Key原文（会加密更新） |
| is_active | bool | ❌ | 是否启用 |

#### 3.4.4 删除 API Key

```
DELETE /admin/api-keys/:id
```

---

### 3.5 模型定价管理

#### 3.5.1 定价列表

```
GET /admin/model-prices
```

#### 3.5.2 修改定价

```
PUT /admin/model-prices/:id
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| input_price_per_1m | float64 | ❌ | 普通-输入每百万token价 |
| input_cache_hit_price_per_1m | float64 | ❌ | 普通-缓存命中每百万token价 |
| output_price_per_1m | float64 | ❌ | 普通-输出每百万token价 |
| thinking_input_price_per_1m | float64 | ❌ | 思考-输入每百万token价 |
| thinking_cache_hit_price_per_1m | float64 | ❌ | 思考-缓存命中每百万token价 |
| thinking_output_price_per_1m | float64 | ❌ | 思考-输出每百万token价 |
| status | int | ❌ | 普通模式 1启用/0停用 |
| thinking_status | int | ❌ | 思考模式 1启用/0停用 |
| pro_only | bool | ❌ | 是否为Pro模型（仅订阅用户可用） |

```json
{
  "input_price_per_1m": 1.5,
  "input_cache_hit_price_per_1m": 0.03,
  "output_price_per_1m": 3,
  "thinking_input_price_per_1m": 4.5,
  "thinking_cache_hit_price_per_1m": 0.04,
  "thinking_output_price_per_1m": 9,
  "status": 1,
  "thinking_status": 1,
  "pro_only": true
}
```

> - **普通模式与思考模式独立定价**，各自有独立的状态开关。思考模式价格通常高于普通模式（需要推理 token 成本）。
> - **`pro_only = true`** 的模型仅限有有效订阅的用户使用，无订阅用户调用时将返回 `model_not_allowed` 错误。

#### 3.5.3 从 DeepSeek 同步模型

```
POST /admin/model-prices/sync
```

> 自动调用 DeepSeek `/models` 接口获取最新模型列表，并创建对应定价条目（默认用原价）。已经存在的模型不会重复创建。

---

### 3.6 订阅计划管理

#### 3.6.1 计划列表

```
GET /admin/plans
```

#### 3.6.2 创建计划

```
POST /admin/plans
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | ✅ | 计划名称 |
| price | float64 | ✅ | 购买价格（元） |
| description | string | ❌ | 描述 |
| daily_quota | float64 | ❌ | 每日赠送额度（元） |
| duration_days | int | ❌ | 有效天数（默认30） |
| sort_order | int | ❌ | 排序 |

```json
{
  "name": "基础会员",
  "price": 9.9,
  "description": "每日2元额度，适合轻度使用",
  "daily_quota": 2,
  "duration_days": 30,
  "sort_order": 1
}
```

#### 3.6.3 编辑计划

```
PUT /admin/plans/:id
```

参数同创建。

#### 3.6.4 删除计划

```
DELETE /admin/plans/:id
```

---

### 3.7 系统配置

#### 3.7.1 查看配置

```
GET /admin/config
```

**响应示例：**
```json
{
  "code": 0,
  "data": {
    "default_daily_quota": "0.5",
    "site_name": "AIchat中继站",
    "xiaoshiguang_key": "***（已加密，不可查看）"
  }
}
```

#### 3.7.2 修改配置

```
PUT /admin/config
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| key | string | ✅ | 配置键 |
| value | string | ✅ | 配置值 |

```json
{
  "key": "default_daily_quota",
  "value": "1.0"
}
```

**常用配置键：**

| key | 说明 | 默认值 |
|-----|------|--------|
| `default_daily_quota` | 所有用户每日免费配额 | 0.5 |
| `site_name` | 站点名称 | AIchat中继站 |

---

### 3.8 订单列表

```
GET /admin/orders?page=1&page_size=20&status=pending
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| page | int | ❌ | 页码 |
| page_size | int | ❌ | 每页条数 |
| status | string | ❌ | pending / paid / failed |

---

## 四、计费说明

### 4.1 计费公式

```
费用 = (缓存命中token × 命中单价
     + 缓存未命中token × 未命中单价
     + 输出token × 输出单价) ÷ 1,000,000
```

### 4.2 扣费顺序

1. 先扣 **每日免费配额**（全局配置 + 有效订阅配额）
2. 配额不足部分从 **账户余额** 扣除
3. 余额不足则 **拒绝请求**

### 4.3 配额规则

- 每日免费配额 **次日零点清零**
- 订阅每日配额随订阅有效期生效，过期订阅自动失效
- 余额永久有效，不会过期

---

## 五、安全注意事项

1. **JWT Token** 有效期 24 小时，过期需重新登录
2. **API Key** 在数据库中 AES-256-GCM 加密，不会出现在任何日志中
3. **支付商户密钥** `xiaoshiguang.key` 同样加密存储，管理后台脱敏显示
4. 密码使用 **bcrypt (cost=12)** 加密，无法反向破解
5. 所有请求建议走 **HTTPS** 传输
6. 单 IP 限流 **60 次/秒**，登录接口 **5 次/分钟**

---

## 六、活动管理

管理后台可创建限时促销活动，对订阅支付、零落支付或聊天计费进行打折或加送。

### 6.1 获取当前有效活动

```
GET /activities
```

无需 Token。返回当前日期范围内所有 `status=1` 的活动。

### 6.2 管理接口（需 Admin）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/admin/activities` | 全部活动列表 |
| POST | `/admin/activities` | 创建活动 |
| PUT | `/admin/activities/:id` | 编辑活动 |
| DELETE | `/admin/activities/:id` | 删除活动 |
| GET | `/admin/activities/:id/rules` | 查看模型规则 |
| PUT | `/admin/activities/:id/rules` | 批量更新模型规则 |

#### 创建活动

```
POST /admin/activities
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| name | string | ✅ | 活动名称 |
| description | string | ❌ | 活动描述 |
| type | string | ✅ | `discount` 打折 / `bonus` 加送 |
| apply_scope | string | ✅ | `subscribe` 订阅 / `zero_drop` 零落 / `chat` 聊天 |
| discount | float64 | ✅ | 折扣率：打折填 0~1（0.8=8折），加送填 >1（1.5=加送50%） |
| started_at | string | ✅ | 开始日期 `"2026-06-20"` |
| ended_at | string | ✅ | 结束日期 `"2026-06-30"` |
| rules | array | ❌ | 仅 `apply_scope=chat` 时有效，模型规则列表 |

**模型规则 `rules` 子字段：**

| 参数 | 说明 |
|------|------|
| model_id | 模型ID |
| input_discount | 输入折扣 |
| cache_hit_discount | 缓存命中折扣 |
| output_discount | 输出折扣 |
| thinking_input_discount | 思考模式-输入折扣 |
| thinking_cache_hit_discount | 思考模式-缓存命中折扣 |
| thinking_output_discount | 思考模式-输出折扣 |

```json
{
  "name": "618大促",
  "type": "discount",
  "apply_scope": "chat",
  "discount": 0.8,
  "started_at": "2026-06-18",
  "ended_at": "2026-06-20",
  "rules": [
    {
      "model_id": "deepseek-v4-flash",
      "input_discount": 0.8,
      "cache_hit_discount": 0.8,
      "output_discount": 0.8,
      "thinking_input_discount": 0.7,
      "thinking_cache_hit_discount": 0.7,
      "thinking_output_discount": 0.7
    }
  ]
}
```

> **同一 scope 只允许一个启用活动**，创建新活动时自动停用旧活动。

---

## 七、错误示例

```json
// 未登录
{"code": 40100, "message": "请先登录", "data": null}

// Token 过期
{"code": 40100, "message": "登录已过期，请重新登录", "data": null}

// 权限不足
{"code": 40300, "message": "需要管理员权限", "data": null}

// 参数错误
{"code": 40000, "message": "参数错误: Key: 'LoginRequest.username' Error:Field validation for 'username' failed on the 'required' tag", "data": null}

// 余额不足
{"code": 50000, "message": "余额不足，需要0.000510元，当前余额0.000100元", "data": null}

// 限流
{"code": 42900, "message": "请求过于频繁，请稍后再试", "data": null}

// DeepSeek错误
{"code": 50000, "message": "DeepSeek返回错误(401): {\"error\":{\"message\":\"Incorrect API key provided\"}}", "data": null}
```

---

## 八、软件更新接口

### 7.1 检查更新

```
GET /update/check?platform=android&version_code=10
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| platform | string | ✅ | 平台：android / ios / windows / linux |
| version_code | int | ✅ | 当前客户端版本号（数字） |

**响应（有更新）：**
```json
{
  "code": 0,
  "data": {
    "has_update": true,
    "version": "2.1.0",
    "version_code": 21,
    "file_size": 52428800,
    "release_notes": "- 新增签到功能\n- 修复若干Bug",
    "is_force": false,
    "download_url": "/api/v1/update/download/3"
  }
}
```

**响应（无更新）：**
```json
{"code": 0, "data": {"has_update": false}}
```

> 后端比较最新的 `version_code` 与传入值，若大于则返回新版本信息。

---

### 7.2 下载安装包

```
GET /update/download/:id
```

无需 Token。返回安装包文件流（`Content-Disposition: attachment`），下载计数自动 +1。

---

### 7.3 版本列表（公开）

```
GET /update/versions?platform=android
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| platform | string | ❌ | 筛选平台，不传则返回全部启用的 |

---

### 7.4 管理：版本列表

```
GET /admin/versions
Authorization: Bearer <token>  (需 admin 角色)
```

返回所有版本（含已停用）。

---

### 7.5 管理：上传新版本

```
POST /admin/versions
Content-Type: multipart/form-data
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| platform | string | ✅ | android / ios / windows / linux |
| version | string | ✅ | 版本名称（如 "2.1.0"） |
| version_code | int | ✅ | 版本号（整数，用于比较） |
| file | file | ✅ | 安装包文件 |
| release_notes | string | ❌ | 更新日志 |
| is_force | string | ❌ | "true" = 强制更新 |
| status | int | ❌ | 1启用（默认）/ 0停用 |

**curl 示例：**
```bash
curl -X POST http://localhost:8080/api/v1/admin/versions \
  -H "Authorization: Bearer <token>" \
  -F "platform=android" \
  -F "version=1.0.0" \
  -F "version_code=1" \
  -F "release_notes=首个版本" \
  -F "file=@app.apk"
```

---

### 7.6 管理：编辑版本

```
PUT /admin/versions/:id
Content-Type: multipart/form-data
```

参数同上传，全部可选。若上传新 `file` 则替换安装包。

---

### 7.7 管理：删除版本

```
DELETE /admin/versions/:id
```

同时删除服务器上的安装包文件。

---

## 九、爱发电支付集成

### 9.1 概述

爱发电是一个赞助平台。管理后台可将爱发电的赞助方案映射到本系统的订阅计划或零落充值。

### 9.2 公开接口

#### 9.2.1 赞助方案列表

```
GET /payment/ifdian/plans
```

无需 Token。返回所有已启用且有映射的爱发电方案。

```json
{
  "code": 0,
  "data": [
    {
      "ifdian_plan_id": "plan_abc123",
      "name": "月度赞助",
      "price": 10,
      "plan_type": "subscription",
      "mapping_type": "subscribe"
    }
  ]
}
```

#### 9.2.2 验证赞助（查询模式）

```
POST /payment/ifdian/verify
Authorization: Bearer <token>
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| out_trade_no | string | ✅ | 爱发电订单号 |

**流程：**
1. 用户在爱发电赞助后获取订单号
2. 调用此接口提交订单号
3. 后端查询爱发电 API 确认支付状态
4. 支付成功 → 根据映射发放权益

**响应（成功发放订阅）：**
```json
{
  "code": 0,
  "data": {
    "granted": true,
    "mapping_type": "subscribe",
    "plan_name": "基础会员",
    "amount": 10
  }
}
```

**响应（成功充值余额）：**
```json
{
  "code": 0,
  "data": {
    "granted": true,
    "mapping_type": "zero_drop",
    "plan_name": "自定义赞助",
    "amount": 50
  }
}
```

**常见错误：**
```json
// 订单不存在
{"code": 40000, "message": "订单不存在: 20240620001"}

// 订单未支付
{"code": 40000, "message": "订单未支付成功，状态: 0"}

// 已领取
{"code": 40000, "message": "该订单已验证并发放权益"}

// 方案未配置映射
{"code": 40000, "message": "未配置该方案的映射: plan_xxx"}
```

#### 9.2.3 Webhook 回调

```
POST /payment/ifdian/webhook
```

爱发电支付成功后自动回调。无需 Token（需验签）。

| 参数 | 类型 | 说明 |
|------|------|------|
| out_trade_no | string | 订单号 |
| plan_id | string | 方案ID |
| total_amount | float64 | 支付金额 |
| status | int | 2=成功 |
| user_id | string | 爱发电用户ID |

---

### 9.3 管理接口（需 Admin）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/admin/ifdian/config` | 获取爱发电配置 |
| PUT | `/admin/ifdian/config` | 保存爱发电配置（user_id + token） |
| POST | `/admin/ifdian/sync-plans` | 从爱发电同步方案列表 |
| GET | `/admin/ifdian/plans` | 查看已同步方案 |
| PUT | `/admin/ifdian/plans/:id/mapping` | 配置方案映射 |
| GET | `/admin/ifdian/records` | 验证记录列表 |

#### 9.3.1 保存配置

```
PUT /admin/ifdian/config
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| user_id | string | ❌ | 爱发电开发者ID |
| token | string | ❌ | 爱发电API Token（加密存储，留空不修改） |

#### 9.3.2 配置方案映射

```
PUT /admin/ifdian/plans/:id/mapping
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| mapping_type | string | ❌ | `subscribe` / `zero_drop` / "" |
| local_plan_id | uint | ❌ | mapping_type=subscribe 时，本地订阅计划ID |
| amount | float64 | ❌ | mapping_type=zero_drop 时，充值金额 |
| daily_quota | float64 | ❌ | 订阅模式下覆盖每日配额 |
| duration_days | int | ❌ | 订阅模式下覆盖有效期 |
| status | int | ❌ | 1启用/0停用 |

---

### 9.4 签名算法

爱发电 API 签名（MD5 小写）：

```
sign = md5( token + "params" + JSON字符串 + "ts" + 时间戳 + "user_id" + 开发者ID )
```

请求格式：
```
GET /api/open/query-order?user_id=xxx&params=JSON&ts=1680000000&sign=xxx
```
