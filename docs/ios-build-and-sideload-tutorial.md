# Windows 构建 iOS + 免 App Store 安装教程

> 适用于：回响 Flutter 项目（Bundle ID `com.aichat.aichat`，iOS 13.0+）
> 适用人群：Windows 开发者，无 Mac 设备
> 最后更新：2026-07-13

---

## 目录

- [一、Windows 构建 iOS 的可行方案对比](#一windows-构建-ios-的可行方案对比)
- [二、方案 A：Codemagic 云端构建（推荐）](#二方案-acodemagic-云端构建推荐)
- [三、方案 B：GitHub Actions macOS runner](#三方案-bgithub-actions-macos-runner)
- [四、方案 C：租用远程 Mac](#四方案-c租用远程-mac)
- [五、构建前的项目准备](#五构建前的项目准备)
- [六、iOS 免 App Store 安装方案对比](#六ios-免-app-store-安装方案对比)
- [七、安装方案 A：Sideloadly 自签（推荐）](#七安装方案-asideloadly-自签推荐)
- [八、安装方案 B：AltStore 自签](#八安装方案-baltstore-自签)
- [九、安装方案 C：TestFlight](#九安装方案-ctestflight)
- [十、常见问题与故障排查](#十常见问题与故障排查)
- [附录 A：Apple ID 类型与限制](#附录-aapple-id-类型与限制)
- [附录 B：项目 iOS 权限说明清单](#附录-b项目-ios-权限说明清单)

---

## 一、Windows 构建 iOS 的可行方案对比

Flutter 官方要求：**构建 iOS 必须使用 macOS**（Xcode 只能在 macOS 上运行）。Windows 本机永远无法直接构建 iOS。以下三种方案都是"远程使用 Mac"的不同形式。

| 方案 | 是否需要 Mac | 月度成本 | 配置难度 | 适合场景 |
|---|---|---|---|---|
| **A. Codemagic** | 否（云端） | 免费 500 Linux 分钟 / 250 Mac 分钟 | 低 | 个人开发、偶尔构建 |
| **B. GitHub Actions** | 否（云端） | 公开仓库免费；私有仓库 200 Mac 分钟 | 中 | 已用 GitHub、需自动化 |
| **C. 远程 Mac 租用** | 是（远程） | $20–$50/月 | 中 | 频繁构建、需要 Xcode GUI |
| ~~D. Hackintosh/VM~~ | — | — | — | **不推荐**：违反 Apple EULA，性能差，不稳定 |

> 推荐选择：**方案 A（Codemagic）** —— 配置最简单，免费额度足够个人项目使用。

---

## 二、方案 A：Codemagic 云端构建（推荐）

### 1. 准备工作

#### 1.1 注册 Apple ID（必需）

若仅自签测试：使用现有 Apple ID 即可（双因素必须开启）。
若要长期使用（1 年签名）：注册 [Apple Developer Program](https://developer.apple.com/programs/)（$99/年）。

#### 1.2 注册 Codemagic 账号

访问 [https://codemagic.io/signup](https://codemagic.io/signup)，使用 GitHub / GitLab / Bitbucket 账号登录（推荐 GitHub）。

#### 1.3 将项目推送到 GitHub

如果项目还未上传到 GitHub：

```powershell
# 在项目根目录 d:\window\Desktop\AIchat
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<你的用户名>/aichat.git
git push -u origin main
```

> 注意：`lib/config/server_config.dart` 已 gitignore，需要在 Codemagic 后台通过环境变量配置。

### 2. 在 Codemagic 添加项目

1. 登录 [https://codemagic.io](https://codemagic.io)
2. 点击 **Add application** → 选择 **GitHub** → 授权 Codemagic 访问你的仓库
3. 选择 `aichat` 仓库 → 点击 **Add application**
4. 选择项目类型：**Flutter App**
5. 选择构建平台：**iOS**

### 3. 配置 iOS 代码签名

Codemagic 支持两种签名方式：

#### 方式 1：自动签名（推荐，需要 Apple Developer Program $99/年）

1. 在 Codemagic 项目设置 → **Code signing → iOS**
2. 选择 **Automatic**
3. 点击 **Connect Apple Developer Portal**
4. 输入 Apple Developer 账号（需为付费会员）
5. Codemagic 会自动创建并管理证书和 Provisioning Profile

#### 方式 2：免费 Apple ID 自签（无需付费会员）

1. 在 Codemagic 项目设置 → **Code signing → iOS**
2. 选择 **Manual**
3. **不需要上传证书**，构建时勾选 `--no-codesign` 选项
4. 构建产物为未签名的 `.ipa`，下载到本地后用 [Sideloadly](#七安装方案-asideloadly-自签推荐) 自签

> 免费方案的关键：在 `codemagic.yaml` 中设置 `flutter build ipa --no-codesign`，得到 unsigned IPA 后本地签名。

### 4. 创建 codemagic.yaml 配置文件

在项目根目录创建 `codemagic.yaml`：

```yaml
workflows:
  ios-workflow:
    name: iOS Build
    instance_type: mac_mini_m1
    max_build_duration: 60
    environment:
      flutter: stable
      vars:
        # 配置 server_config.dart 的内容（避免敏感信息进仓库）
        SERVER_CONFIG: |
          // 这里粘贴 lib/config/server_config.dart 的完整内容
    scripts:
      - name: Restore server config
        script: |
          echo "$SERVER_CONFIG" > lib/config/server_config.dart
      - name: Get Flutter packages
        script: |
          flutter packages pub get
      - name: Flutter analyze
        script: |
          flutter analyze
        ignore_failure: true
      - name: Build iOS IPA (unsigned, for sideload)
        script: |
          flutter build ipa --no-codesign --release
    artifacts:
      - build/ios/ipa/*.ipa
      - build/ios/ipa/*.dYSM.zip
    publishing:
      email:
        recipients:
          - your-email@example.com
```

> 说明：
> - `instance_type: mac_mini_m1` 使用 M1 Mac mini（免费额度内）
> - `--no-codesign` 输出未签名 IPA，配合 Sideloadly 本地签名（适合免费 Apple ID）
> - 若已订阅 Apple Developer Program，去掉 `--no-codesign` 并在 environment 配置证书

### 5. 触发构建

1. 提交 `codemagic.yaml` 到仓库
2. 在 Codemagic 后台点击 **Start new build**
3. 选择 `ios-workflow` → 点击 **Start new build**
4. 等待构建完成（约 15-25 分钟首次，后续缓存后约 8-12 分钟）

### 6. 下载构建产物

构建完成后：
- Codemagic 后台 → 找到对应 build → **Artifacts**
- 下载 `ios_runner.ipa`（或类似名称的 IPA 文件）
- 保存到 Windows 本地，例如 `D:\releases\huixiang-v5.0.0-beta.ipa`

---

## 三、方案 B：GitHub Actions macOS runner

适合已经在用 GitHub 且仓库为公开（公开仓库免费无限分钟）的项目。

### 1. 创建 GitHub Actions workflow

在项目根目录创建 `.github/workflows/build-ios.yml`：

```yaml
name: Build iOS IPA

on:
  workflow_dispatch:  # 手动触发
  push:
    tags:
      - 'v*'  # 推送 v 开头的 tag 时触发

jobs:
  build-ios:
    runs-on: macos-latest  # 使用 GitHub 提供的 macOS runner
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Restore server config
        env:
          SERVER_CONFIG: ${{ secrets.SERVER_CONFIG }}
        run: |
          echo "$SERVER_CONFIG" > lib/config/server_config.dart

      - name: Get dependencies
        run: flutter pub get

      - name: Build IPA (unsigned)
        run: flutter build ipa --no-codesign --release

      - name: Upload IPA artifact
        uses: actions/upload-artifact@v4
        with:
          name: huixiang-ios-ipa
          path: build/ios/ipa/*.ipa
          retention-days: 30
```

### 2. 配置 Secrets

1. GitHub 仓库 → Settings → Secrets and variables → Actions
2. 点击 **New repository secret**
3. Name: `SERVER_CONFIG`
4. Value: 粘贴 `lib/config/server_config.dart` 的完整内容
5. 点击 **Add secret**

### 3. 触发构建

- **手动触发**：仓库 → Actions → 选择 `Build iOS IPA` → Run workflow
- **Tag 触发**：
  ```powershell
  git tag v5.0.0-beta
  git push origin v5.0.0-beta
  ```

### 4. 下载产物

构建完成后：
- Actions 页面 → 点击对应的 run → 滚动到底部 **Artifacts**
- 下载 `huixiang-ios-ipa.zip`，解压得到 IPA 文件

> **免费额度提醒**：
> - 公开仓库：完全免费
> - 私有仓库：每月 2000 分钟总额度，但 macOS runner 按 **10 倍** 计算，即实际可用 200 分钟 macOS 时间
> - 一次 iOS 构建约 25-40 分钟 = 消耗 250-400 分钟额度（私有仓库）

---

## 四、方案 C：租用远程 Mac

适合需要频繁构建、需要 Xcode GUI 调试的场景。

### 主流服务商

| 服务商 | 价格起 | 特点 | 链接 |
|---|---|---|---|
| **MacinCloud** | $20/月 | 按小时/月租用，远程桌面访问 | [macincloud.com](https://www.macincloud.com/) |
| **MacStadium** | $50/月起 | 专属 Mac，企业级稳定 | [macstadium.com](https://www.macstadium.com/) |
| **FlowDrive** | $25/月 | 专为 CI/CD 设计 | [flowdrive.io](https://flowdrive.io/) |
| **HostMyApple** | $25/月 | 性价比高 | [hostmyapple.com](https://hostmyapple.com/) |

### 操作步骤（以 MacinCloud 为例）

1. 注册 MacinCloud 账号并订阅方案
2. 通过远程桌面（RDP/VNC）连接到租用的 Mac
3. 在 Mac 上安装 Xcode + Flutter + CocoaPods
4. 从 GitHub 克隆项目
5. 在 Mac 上执行：
   ```bash
   cd aichat
   flutter pub get
   flutter build ipa --no-codesign --release
   ```
6. 通过 FTP/网盘将 IPA 下载回 Windows

---

## 五、构建前的项目准备

### 1. 检查 iOS 配置

当前项目 iOS 配置：

| 项 | 当前值 | 文件 |
|---|---|---|
| Bundle ID | `com.aichat.aichat` | `ios/Runner.xcodeproj/project.pbxproj` |
| Display Name | 回响 | `ios/Runner/Info.plist` |
| iOS 部署目标 | 13.0 | `project.pbxproj` |
| 代码签名风格 | Automatic | `project.pbxproj` |

### 2. 修改 Bundle ID（如果需要）

如果使用 Apple Developer Program 的开发者账号，需要将 Bundle ID 改为你自己的：

1. 编辑 `ios/Runner.xcodeproj/project.pbxproj`
2. 将 `PRODUCT_BUNDLE_IDENTIFIER = com.aichat.aichat;` 改为你的标识符（3 处，包括 RunnerTests）
3. 例如：`PRODUCT_BUNDLE_IDENTIFIER = com.yourname.huixiang;`

> 注意：免费 Apple ID 自签时，Sideloadly 会自动改 Bundle ID 为 `com.yourname.app.xxx`，所以原 Bundle ID 不冲突即可。

### 3. 配置 iOS 权限说明

回响项目目前 `Info.plist` 中**没有声明任何权限说明**。若后续使用相机、相册、定位等功能，必须添加权限说明，否则 iOS 会崩溃。

参考 [附录 B：项目 iOS 权限说明清单](#附录-b项目-ios-权限说明清单) 添加对应 key。

### 4. 检查 iOS 网络配置

回响需要访问 HTTP API（`http://...` 或自签名 HTTPS）。iOS 默认不允许 HTTP 请求，需要在 `Info.plist` 中添加 ATS 例外：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> 检查 `lib/services/real_info_service.dart` 是否使用了明文 HTTP（AGENTS.md 中标注的已知 bug）。生产环境建议改为 HTTPS。

### 5. 配置 server_config.dart

确保 `lib/config/server_config.dart` 配置了正确的服务器地址。这个文件被 gitignore，需要在构建时通过环境变量注入（见上方 Codemagic/GitHub Actions 配置）。

---

## 六、iOS 免 App Store 安装方案对比

| 方案 | 签名有效期 | 应用数限制 | 是否需审核 | 适合场景 |
|---|---|---|---|---|
| **A. Sideloadly + 免费 Apple ID** | 7 天 | 3 个 | 否 | 个人测试 |
| **A. Sideloadly + Apple Developer ($99/年)** | 1 年（365 天） | 无限 | 否 | 长期自用、内部分发 |
| **B. AltStore** | 7 天 | 3 个 | 否 | 同 A，自动刷新 |
| **C. TestFlight** | 90 天 | 10000 测试者 | 是（Beta 审核） | 公测、邀请测试 |
| ~~D. 企业证书 ($299/年)~~ | 1 年 | 无限 | 否 | **仅企业内部**，个人使用有封号风险 |
| ~~E. 越狱安装~~ | 永久 | 无限 | 否 | 需越狱，不推荐 |

> 推荐选择：
> - **个人自用（最省钱）**：方案 A + Apple Developer Program $99/年 → 1 年签名，无需每周刷新
> - **个人测试（完全免费）**：方案 A + 免费 Apple ID → 7 天签名，每周重新签名
> - **多人测试**：方案 C（TestFlight）→ 上限 10000 人

---

## 七、安装方案 A：Sideloadly 自签（推荐）

### 1. 准备工作

#### 1.1 安装 Sideloadly

1. 访问 [https://sideloadly.io/](https://sideloadly.io/) 下载 Windows 版（最新版 v0.55+）
2. 安装时勾选 **iTunes** 组件（如果未安装）
3. **重要**：必须安装 32 位版本的 iTunes（不是 Microsoft Store 版本）
   - 下载地址：[https://www.apple.com/itunes/](https://www.apple.com/itunes/)（点击"Looking for other versions" → Windows 32-bit）
   - Microsoft Store 版本的 iTunes 缺少 Sideloadly 需要的 Mobile Device Support 组件

#### 1.2 准备 IPA 文件

从 [Codemagic](#二方案-acodemagic-云端构建推荐) 或 [GitHub Actions](#三方案-bgithub-actions-macos-runner) 下载 `.ipa` 文件，保存到本地。

#### 1.3 准备 Apple ID

- **免费方案**：使用你的个人 Apple ID（需开启两步验证）
- **付费方案**：使用 Apple Developer Program 账号

> 安全建议：可以注册一个专用 Apple ID 用于自签，避免主账号风险。免费 Apple ID 自签不会泄露密码，Sideloadly 是直接与 Apple 服务器通信。

### 2. 签名并安装（免费 Apple ID 方案）

#### 2.1 连接 iPhone

1. 用数据线将 iPhone 连接到电脑
2. 解锁 iPhone，如果弹出"信任此电脑"对话框，点击**信任**
3. 打开 Sideloadly，应能在左侧看到你的设备

#### 2.2 配置签名

1. 在 Sideloadly 左侧的 IPA 框中，拖入 `.ipa` 文件，或点击 **IPA** 按钮选择文件
2. **Apple ID**：输入你的 Apple ID 邮箱
3. **Password**：输入 Apple ID 密码（应用专用密码，见下方说明）
4. **Bundle ID**：保持默认（Sideloadly 会自动加前缀，避免冲突）
5. **Options** 选项：
   - 勾选 `Force file based signing`（推荐）
   - 其他保持默认

#### 2.3 应用专用密码（必须）

由于 Apple ID 开启了两步验证，必须使用**应用专用密码**：

1. 访问 [https://appleid.apple.com/account/manage](https://appleid.apple.com/account/manage)
2. 登录你的 Apple ID
3. 在"安全"部分找到**应用专用密码**
4. 点击**生成应用专用密码**
5. 输入标签（如 "Sideloadly"）
6. 复制生成的 16 位密码
7. 在 Sideloadly 的密码框中粘贴这个专用密码（**不是** Apple ID 密码）

#### 2.4 开始签名安装

1. 点击右下角 **Start** 按钮
2. 等待签名完成（约 1-3 分钟）
3. 看到提示 "Done" 表示安装成功
4. iPhone 桌面会出现"回响"应用图标

#### 2.5 信任开发者证书（首次安装必做）

1. iPhone 上打开：**设置 → 通用 → VPN 与设备管理**
2. 找到你的 Apple ID 对应的"开发者 App"条目
3. 点击进入 → 点击**信任 `<你的Apple ID>`**
4. 弹出确认对话框 → 点击**信任**

现在可以打开"回响"应用正常使用了。

### 3. 续签（7 天后必做）

免费 Apple ID 签名的应用 **7 天后失效**，需要重新签名：

1. 重新连接 iPhone 到电脑
2. 打开 Sideloadly，重复 2.2-2.4 步骤
3. Sideloadly 会覆盖安装（保留应用数据）

> 数据保留：Sideloadly 覆盖安装时会保留应用数据，无需担心聊天记录丢失。

### 4. 使用 Apple Developer 付费账号（1 年签名）

如果你购买了 Apple Developer Program（$99/年）：

1. 在 Sideloadly 中**不要**输入 Apple ID 密码
2. 改为：点击 **Advanced** → 选择 **Apple Developer Account**
3. 上传 `.p12` 证书文件和 `.mobileprovision` 配置文件
4. 这些文件从 [Apple Developer Portal](https://developer.apple.com/account/resources) 创建并下载
5. 签名后的应用 1 年有效，无需每周续签

证书创建步骤（需要 Mac 或租用 Mac，在 apple.developer.com 网页无法创建）：

> 简化方案：用方案 C（租用 Mac）创建一次证书（约 30 分钟），下载到 Windows，之后一年都用 Sideloadly + 这个证书签名即可。

---

## 八、安装方案 B：AltStore 自签

AltStore 是 Sideloadly 的同类工具，优势是可以**自动刷新签名**（每周自动续签 7 天）。

### 1. 安装 AltServer

1. 访问 [https://altstore.io/](https://altstore.io/) 下载 AltServer for Windows
2. 安装 AltServer
3. 同样需要安装 32 位 iTunes + iCloud（非 Microsoft Store 版本）

### 2. 安装 AltStore 到 iPhone

1. iPhone 连接电脑
2. 点击 Windows 任务栏右下角 AltServer 图标
3. 选择 **Install AltStore → 你的 iPhone**
4. 输入 Apple ID 和应用专用密码
5. 等待安装完成

### 3. 使用 AltStore 安装回响 IPA

1. 将 `.ipa` 文件通过 AirDrop / 网盘 / 邮件传到 iPhone
2. 在 iPhone 上点击 IPA 文件 → 选择 **用 AltStore 打开**
3. AltStore 自动签名并安装

### 4. 自动刷新签名

- AltStore 会在 iPhone 与电脑同一 WiFi 时自动刷新签名
- 需要 AltServer 在电脑后台运行
- 每周至少让 iPhone 与电脑在同一 WiFi 一次

> 优点：无需每周手动插数据线
> 缺点：需要电脑长期开机并运行 AltServer

---

## 九、安装方案 C：TestFlight

适合多人测试（最多 10000 人）。需要 Apple Developer Program 会员。

### 1. 准备工作

- Apple Developer Program 会员（$99/年）
- 在 [App Store Connect](https://appstoreconnect.apple.com/) 创建 App
- 准备好已签名的 IPA（用 Apple Developer 证书签名）

### 2. 创建 App

1. 登录 [App Store Connect](https://appstoreconnect.apple.com/)
2. 我的 App → **+** → 新建 App
3. 填写：平台 iOS / 名称 回响 / 主语言 简体中文 / Bundle ID（在 Developer Portal 注册的）
4. SKU：任意唯一字符串

### 3. 上传构建

需要 Mac 或租用 Mac 上传（Xcode 或 `xcrun altool`）：

```bash
xcrun altool --upload-app --type ios -f huixiang.ipa \
  --apiKey XXXXX --apiIssuer YYYYY \
  --verbose
```

或用 Xcode → Window → Organizer → Distribute App → TestFlight

### 4. 添加测试者

1. App Store Connect → 你的 App → TestFlight 选项卡
2. 等待构建处理完成（约 10-30 分钟）
3. 添加内部测试者（同 Developer 团队成员，无需审核）
4. 或添加外部测试者（最多 10000 人，需 Beta 审核，通常 1-2 天）

### 5. 测试者安装

测试者收到邮件邀请 → 接受邀请 → 安装 TestFlight app → 在 TestFlight 中安装回响 Beta

> TestFlight 安装的应用 90 天有效，过期后需要上传新构建。

---

## 十、常见问题与故障排查

### Q1: Sideloadly 报错 "Device not found"

**原因**：iTunes 驱动未正确安装，或 iPhone 未信任电脑

**解决**：
1. 卸载 Microsoft Store 版 iTunes
2. 安装 32 位 iTunes（从 apple.com 下载）
3. 重启电脑
4. iPhone 连接后弹窗点击"信任"，输入解锁密码

### Q2: Sideloadly 报错 "Verification failed" 或 "Anisette data"

**原因**：Sideloadly 需要 Anisette 数据服务

**解决**：
1. Sideloadly 设置 → **Anisette Server** → 切换为 `Sideloading Roan server` 或 `Custom`
2. 或尝试自定义服务器：`https://armelyamoneytools.com/`

### Q3: 安装后打开应用闪退 "Untrusted Enterprise Developer"

**原因**：未信任开发者证书

**解决**：设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID

### Q4: 7 天后应用打不开

**原因**：免费 Apple ID 签名有效期 7 天

**解决**：重新连接电脑，用 Sideloadly 重新签名安装

### Q5: Codemagic 构建失败 "No profiles for com.aichat.aichat were found"

**原因**：Bundle ID 未在 Apple Developer Portal 注册

**解决**：
- 免费方案：在 codemagic.yaml 中使用 `--no-codesign`
- 付费方案：登录 Apple Developer Portal → Identifiers → 注册 Bundle ID

### Q6: GitHub Actions macOS runner 配额超限

**原因**：macOS runner 按 10 倍计费

**解决**：
- 改用 Codemagic（免费 250 Mac 分钟）
- 或将仓库设为公开（公开仓库免费无限分钟）
- 或购买 GitHub Actions 额外额度

### Q7: IPA 安装失败 "This app is not compatible with your device"

**原因**：iOS 版本过低或架构不匹配

**解决**：
- 项目要求 iOS 13.0+，确认 iPhone 系统版本 ≥ 13.0
- 构建命令加 `--no-codesign` 时输出 universal IPA，应该兼容所有 64 位 iOS 设备

### Q8: 免费签名能否推送通知

**不能**。免费 Apple ID 签名的应用无法使用 APNs 推送通知。需要 Apple Developer Program 会员。

### Q9: 如何避免每周续签

购买 Apple Developer Program（$99/年）→ 用 Sideloadly + `.p12` 证书签名 → 1 年有效。

### Q10: 回响 Android 版和 iOS 版功能差异

iOS 版因系统限制：
- 无法后台保活（影响"主动关心"功能实时性）
- 推送通知需要 Apple Developer 会员
- 文件系统访问受限（部分文件管理功能可能不工作）
- 应用内支付必须走 Apple IAP（30% 抽成）

---

## 附录 A：Apple ID 类型与限制

| 类型 | 价格 | 签名有效期 | 应用数限制 | 推送通知 | TestFlight |
|---|---|---|---|---|---|
| 免费 Apple ID | 免费 | 7 天 | 3 个 | ❌ | ❌ |
| Apple Developer Program | $99/年 | 365 天 | 无限 | ✅ | ✅（含内测+公测） |
| Apple Developer Enterprise | $299/年 | 365 天 | 无限 | ✅ | ❌（仅企业内部） |

> 注意：Apple Developer Enterprise Program 仅适用于员工数 ≥ 100 的企业内部应用分发。个人或小团队使用企业证书分发有封号风险，**不推荐**。

---

## 附录 B：项目 iOS 权限说明清单

回响项目当前 `Info.plist` 未声明任何权限。如果未来用到以下功能，必须添加对应描述：

| 功能 | Info.plist Key | 建议描述（中文） |
|---|---|---|
| 相机 | `NSCameraUsageDescription` | 回响需要使用相机来拍摄头像和发送图片消息 |
| 相册 | `NSPhotoLibraryUsageDescription` | 回响需要访问相册来选择头像和发送图片 |
| 相册添加（保存） | `NSPhotoLibraryAddUsageDescription` | 回响需要保存图片到相册 |
| 麦克风 | `NSMicrophoneUsageDescription` | 回响需要使用麦克风来录制语音消息 |
| 定位 | `NSLocationWhenInUseUsageDescription` | 回响需要获取您的位置来提供天气等服务 |
| 通知 | `Push Notification` Capability | 需在 Xcode 中启用 Push Notifications capability |
| 网络请求 | `NSAppTransportSecurity` | 见下方说明 |

### 网络配置（必须）

回响需要访问后端 API，如果使用 HTTP（非 HTTPS）或自签名 HTTPS 证书，必须在 `Info.plist` 添加 ATS 例外：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> 生产环境推荐使用受信任 CA 签发的 HTTPS 证书，移除 ATS 例外。

### 示例：添加权限描述后的 Info.plist 片段

在 `ios/Runner/Info.plist` 的 `<dict>` 中添加：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>NSCameraUsageDescription</key>
<string>回响需要使用相机来拍摄头像和发送图片消息</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>回响需要访问相册来选择头像和发送图片</string>
<key>NSMicrophoneUsageDescription</key>
<string>回响需要使用麦克风来录制语音消息</string>
```

---

## 流程总结

### 最省钱的完整流程（推荐）

1. 注册 Apple Developer Program（$99/年）→ 获得 1 年签名权限
2. 项目推送到 GitHub
3. 注册 Codemagic 账号，配置 `codemagic.yaml`
4. 在 Codemagic 构建未签名 IPA（`--no-codesign`）
5. 下载 IPA 到 Windows
6. 用 Sideloadly + Apple Developer `.p12` 证书签名安装
7. 一年内无需重新签名

### 完全免费的流程

1. 准备好免费 Apple ID（开启两步验证）
2. 项目推送到 GitHub
3. 用 GitHub Actions（公开仓库）或 Codemagic（免费额度）构建未签名 IPA
4. 下载 IPA 到 Windows
5. 用 Sideloadly + 免费 Apple ID 签名安装
6. 每 7 天重新签名一次（应用数据保留）

### 测试分发流程（多人）

1. 购买 Apple Developer Program（$99/年）
2. 在 App Store Connect 创建 App
3. 用 Codemagic 构建 + 签名 + 上传到 TestFlight
4. 邀请测试者（最多 10000 人）
5. 测试者通过 TestFlight 安装，90 天有效
