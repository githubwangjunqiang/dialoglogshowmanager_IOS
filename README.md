# ShowLog iOS SDK 开发者接入指南

[![CocoaPods](https://img.shields.io/cocoapods/v/DialogLogShowManager.svg?style=flat)](https://cocoapods.org/pods/DialogLogShowManager)
[![Platform](https://img.shields.io/badge/platform-iOS%2013.0%2B-blue.svg)](https://cocoapods.org/pods/DialogLogShowManager)
[![SPM](https://img.shields.io/badge/SPM-supported-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **1:1 像素级对标 Android ShowLog v6.0**  
> 纯原生 Swift 5.9+ / UIKit 构建，零第三方依赖，专为 iOS 研发、测试与自动化诊断打造的轻量级全景可视化调试工具。

---

## 目录
1. [SDK 能力一览](#1-sdk-能力一览)
2. [快速接入（10 行搞定）](#2-快速接入10-行搞定)
3. [功能怎么用（入口与手势速查）](#3-功能怎么用入口与手势速查)
4. [依赖引入与初始化配置详解](#4-依赖引入与初始化配置详解)
5. [URLSession / Alamofire 网络日志自动拦截与业务裁决](#5-urlsession--alamofire-网络日志自动拦截与业务裁决)
6. [非 URLSession / 自定义网络库手动上报（强契约）](#6-非-urlsession--自定义网络库手动上报强契约)
7. [ShowLog Hub 调试中枢、自定义面板与沙盒文件浏览](#7-showlog-hub-调试中枢自定义面板与沙盒文件浏览)
8. [生产包安全、App Store 提审合规与零开销保障](#8-生产包安全app-store-提审合规与零开销保障)
9. [Swift / Objective-C 混编与符号说明](#9-swift--objective-c-混编与符号说明)
10. [代码混淆与安全加固配置（Anti-Obfuscation Rules）](#10-代码混淆与安全加固配置anti-obfuscation-rules)
11. [API 核心参考速查表](#11-api-核心参考速查表)
12. [版本历史与更新记录](#12-版本历史与更新记录)

---

## 1. SDK 能力一览

ShowLog iOS 是一款专为 iOS 应用设计的嵌入式全景调试套件，1:1 还原 Android 平台的成熟体验与视觉设计语言：

* **全景暗黑科技风**：基于精算高斯模糊（`UIBlurEffect`）、16 进制主题色板与二次贝塞尔曲线内凹切角，带来统一的视觉美感。
* **免权限多场景吸边悬浮球**：重写 `UIWindow.point(inside:with:)` 实现穿透点击，支持手指拖拽、惯性吸边与边缘停靠，完美适配多 `UIWindowScene`。
* **透明网络捕获引擎**：
  * 基于 `URLProtocol` + Method Swizzling 机制无侵入拦截原生 `URLSession`、`Alamofire`、`AFNetworking`。
  * 内置 **HTTP 业务裁决器（`HttpLogBusinessJudger`）**，支持开发者根据业务 JSON 报文（如 `code == 200`）自定义判定成功与失败。
  * 自动支持 Gzip 流式透明解压、超长报文防御性截断、图片/音频/二进制嗅探。
* **双层混合读写仓储（Hybrid-Read SQLite）**：
  * 高性能 SQLite3 C 原生封装 + WAL 预写日志模式。
  * 500ms 定时聚合与单事务批量刷盘（`BEGIN IMMEDIATE`），退后台自动刷新。
  * 内存未落盘日志与 SQLite 分页数据毫秒级无缝合并。
* **沙盒文件只读浏览器**：
  * 支持一键穿梭 Documents / Library / Caches / tmp 沙盒目录。
  * 32KB 分页流式加载，BOM 头检测，彻底告别超大日志文件 OOM。
  * 严格的 `isWithinRoot` 防路径穿越与符号链接逃逸安全防护。
* **全景设备与环境诊断看板**：
  * 40+ 项设备/系统/运行期指标（CPU 使用率、物理内存分配、存储空间、电池状态、屏幕参数、沙盒路径等）。
  * 2 秒自适应节流动态刷新，一键导出标准格式 Markdown 诊断报告。
* **无限业务扩展（CustomPanelProvider）**：
  * 面向接口编程，支持开发者将业务私有调试工具（如切换网关环境、清理缓存、Mock 数据）注册为 Hub 顶部 Tab。
* **零开销直通模式（Zero-Overhead Pass-Through）**：
  * 当 `enabled = false` 时，所有公开 API 为空实现，网络拦截彻底短路，悬浮球完全销毁，生产包 CPU/内存零额外损耗。

---

## 2. 快速接入（10 行搞定）

### 2.1 Swift 接入（推荐）

在 `AppDelegate.swift` 或 `App.swift` 中初始化：

```swift
import UIKit
import ShowLog

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        #if DEBUG
        // 1. 构建配置
        let config = ShowLogConfig.Builder()
            .enabled(true)                                   // 开启调试功能
            .showFloatingView(true)                          // 显示吸边悬浮球
            .enableURLSessionSwizzling(true)                 // 自动拦截 URLSession 网络请求
            .maxDatabaseLogLimit(10000)                      // 数据库最大保留条数（默认 10000）
            .maxBodyBytes(256 * 1024)                        // 单条报文截断保护（256KB）
            .addRedactHeader("Authorization")                // 敏感请求头脱敏
            .build()

        // 2. 初始化 ShowLog
        ShowLog.initialize(config: config)
        #endif

        return true
    }
}
```

### 2.2 Objective-C 接入

```objc
@import UIKit;
@import ShowLog;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    #if DEBUG
    ShowLogConfigBuilder *builder = [[ShowLogConfigBuilder alloc] init];
    [builder enabled:YES];
    [builder showFloatingView:YES];
    [builder enableURLSessionSwizzling:YES];
    [builder maxDatabaseLogLimit:10000];
    
    ShowLogConfig *config = [builder build];
    [ShowLog initializeWithConfig:config];
    #endif
    return YES;
}
```

---

## 3. 功能怎么用（入口与手势速查）

| 入口 / 手势 | 触发动作 | 功能说明 |
|:---|:---|:---|
| **单指轻触悬浮球** | 打开 ShowLog Hub | 展开主调试控制台抽屉，查看网络、设备、文件与扩展面板 |
| **单指拖拽悬浮球** | 屏幕吸附停靠 | 手指松开后，悬浮球自动附带弹簧阻尼动画吸附至左右屏幕边缘，不遮挡主业务 UI |
| **长按悬浮球 (0.8s)** | 隐藏悬浮球 | 快速隐藏当前屏幕上的悬浮球，保持界面清爽 |
| **摇一摇手势 (Shake)** | 呼出 / 收起 Hub | 摇晃设备快速打开或关闭调试面板，免去寻找悬浮球的步骤 |
| **三指轻点屏幕两次** | 唤醒悬浮球 | 当悬浮球被长按隐藏后，三指双击屏幕任意位置即可重新召回悬浮球 |
| **快捷代码调用** | `ShowLog.openHub()` | 支持在业务代码（如隐藏调试彩蛋）中直接弹出调试面板 |

---

## 4. 依赖引入与初始化配置详解

### 4.1 引入依赖

#### 方式一：CocoaPods（官方公共源 - 推荐）
ShowLog 已正式发布至 CocoaPods 官方 Specs 中心，在工程的 `Podfile` 中添加：
```ruby
pod 'DialogLogShowManager', '~> 6.0.2'
```
随后在终端执行：
```bash
pod install --repo-update
```

> **注意**：由于 CocoaPods 官方源全局名称唯一性，Pod 注册库名为 `DialogLogShowManager`。  
> 内部已显式绑定 `s.module_name = 'ShowLog'`，因此在 Swift 代码中均直接使用统一模块名：
> ```swift
> import ShowLog
> ```

#### 方式二：Swift Package Manager (SPM 原生接入)
在 Xcode 中选择 `File` -> `Add Package Dependencies...`，填入 Git 仓库地址：
```text
https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git
```
在版本规则选择 **Exact: 6.0.2** 或 **Up to Next Major**。  
若使用 `Package.swift` 管理依赖，请添加：
```swift
dependencies: [
    .package(url: "https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git", from: "6.0.2")
]
```

#### 方式三：CocoaPods Git 直引方式
如果不需要公共源索引，也可以直接指向 GitHub 仓库：
```ruby
pod 'ShowLog', :git => 'https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git', :tag => '6.0.2'
```

### 4.2 配置参数全解 (`ShowLogConfig.Builder`)

| 方法 | 类型 | 默认值 | 说明 |
|:---|:---|:---|:---|
| `enabled(Bool)` | `Bool` | `true` | 全局总开关。设为 `false` 则激活零开销直通模式，悬浮球与拦截器全部静默 |
| `showFloatingView(Bool)` | `Bool` | `true` | 是否在应用启动时自动在屏幕上展示免权限吸边悬浮球 |
| `enableURLSessionSwizzling(Bool)` | `Bool` | `true` | 是否自动将拦截器注入至 `URLSessionConfiguration.default` 与 `.ephemeral` |
| `maxDatabaseLogLimit(Int)` | `Int` | `10000` | SQLite 数据库最多保留的历史日志条数（范围 100 ~ 50,000，超出自动 LRU 清理） |
| `maxBodyBytes(Int)` | `Int` | `262,144` | 单条请求/响应 Body 截断保护上限（字节），默认 256KB（最低钳制 1024 字节） |
| `addRedactHeader(String)` | `String` | 常见 Auth 头 | 添加需要打码脱敏的敏感 Header（默认已包含 Authorization, Cookie, Token 等） |
| `fileBrowserRootPath(String?)` | `String?` | `nil` | 沙盒文件浏览 Tab 的根目录路径；若为 `nil` 或空字符串则不展示文件浏览 Tab |
| `fileBrowserTabTitle(String?)` | `String?` | `nil` | 文件浏览 Tab 的自定义显示标题；若为 `nil` 回退展示“文件浏览” |

---

## 5. URLSession / Alamofire 网络日志自动拦截与业务裁决

### 5.1 自动拦截原理
初始化 `ShowLog` 时，若 `enableURLSessionSwizzling` 为 `true`（默认），SDK 会自动将 `ShowLogURLProtocol` 注入至 `URLSessionConfiguration.default` 与 `ephemeral` 中。

使用 `URLSession.shared` 或默认配置初始化的 `Alamofire.Session` 无需任何额外配置，网络日志会自动落盘并展示。

> **注意（自定义 URLSessionConfiguration）**：  
> 若业务代码构建了独立的 `URLSessionConfiguration`，只需单行注入协议：
> ```swift
> let config = URLSessionConfiguration.default
> config.protocolClasses = [ShowLogURLProtocol.self] + (config.protocolClasses ?? [])
> let customSession = URLSession(configuration: config)
> ```

### 5.2 业务成功/失败裁决器 (`HttpLogBusinessJudger`)

在移动端接口中，HTTP 状态码往往是 `200 OK`，但 JSON 报文内部可能返回 `{"code": 40101, "msg": "Token 已过期"}`。  
ShowLog 支持自定义业务裁决器，将这类报文在列表中直接标红显示：

```swift
let judger: HttpLogBusinessJudger = { context in
    // 检查响应内容是否包含业务失败码
    if let body = context.responseBody, body.contains("\"code\": 40101") {
        return .businessFailure(businessCode: "40101", errorMessage: "用户 Token 过期")
    }
    if context.statusCode >= 200 && context.statusCode < 300 {
        return .businessSuccess(businessCode: "200")
    }
    return .systemError(errorCode: "\(context.statusCode)", message: "HTTP 异常状态码")
}

let config = ShowLogConfig.Builder()
    .businessJudger(judger)
    .build()

ShowLog.initialize(config: config)
```

---

## 6. 非 URLSession / 自定义网络库手动上报（强契约）

若应用采用 C++ 网络内核、Rust 底层库、gRPC 或 WebSocket，无法走 `URLProtocol` 拦截时，可通过实现强契约协议 `HttpLogPayload` 手动上报：

```swift
import ShowLog

// 1. 自定义结构体遵循 HttpLogPayload 协议
struct CustomNetworkEvent: HttpLogPayload {
    var logId: String { UUID().uuidString }
    var requestUrl: String { "https://grpc.api.example.com/stream" }
    var requestMethod: String { "POST" }
    var requestHeaders: [String : String] { ["Content-Type": "application/grpc"] }
    var requestBody: String? { "{\"payload\": \"binary-data\"}" }
    var responseHeaders: [String : String]? { ["grpc-status": "0"] }
    var responseBody: String? { "{\"result\": \"success\"}" }
    var httpStatusCode: Int { 200 }
    var requestTimestamp: Int64 { Int64(Date().timeIntervalSince1970 * 1000) - 120 }
    var responseTimestamp: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    var errorMessage: String? { nil }
}

// 2. 手动将日志推入 ShowLog 仓储管道
ShowLog.record(payload: CustomNetworkEvent())
```

---

## 7. ShowLog Hub 调试中枢、自定义面板与沙盒文件浏览

### 7.1 调试中枢概览
ShowLog Hub 包含四个原生模块，并在交互与视觉上深度优化：
* **智能滑动居中页签（Tab Auto-Center）**：顶部页签栏在点击或切换时，自动将目标 Tab 平滑滑动至视口正中央，完美适配带岛机型与各种紧凑屏幕；
* **灵动岛与安全区精确避让**：全面适配 `safeAreaLayoutGuide`，悬浮框与弹窗彻底避开系统状态栏与灵动岛，杜绝误触通知中心；
* **一体化无缝暗黑背景**：自研 `ShowLogHubTabPanelBackgroundView` 贝塞尔双曲线闭合轮廓 + 暗黑轨道底槽，未选中 Tab 绝无底层透光与文字重影；
* **高辨识度状态 Badge 与耗时直显**：网络列表项采用墨绿/深红胶囊 Badge 直显业务状态码，右上角直标响应耗时（如 `142ms`），排查异常一目了然；
* **原生模块矩阵**：
  1. **Network（网络控制台）**：支持扁平列表与 Path 路径分组切换、实时关键字模糊检索、日期日历筛选、一键清空日志。点选任意请求可查看 Request / Response / Headers / cURL 命令复制。
  2. **Device（设备诊断看板）**：展示设备型号、系统版本、屏幕物理分辨率、CPU 核心数与瞬时负载、当前 App 物理内存驻留（Resident Memory）、沙盒磁盘空间、电量等。点击顶部“导出诊断报告”可一键生成 Markdown 格式报告并调用系统分享。
  3. **FileBrowser（沙盒只读浏览）**：可视化浏览 App 沙盒目录，32KB 分页流式加载纯文本与 JSON，防止读取大日志文件撑爆内存。
  4. **Custom Panels（自定义面板）**：业务方自由注入的扩展工具集合。

### 7.2 注册自定义调试面板 (`CustomPanelProvider`)

您可以轻松将团队私有的调试工具（例如：环境切换、埋点抓取、Mock 桩）注册到 ShowLog 中：

```swift
import UIKit
import ShowLog

class EnvironmentSwitcherPanel: NSObject, CustomPanelProvider {
    var panelTitle: String { "环境切换" }
    var panelIcon: UIImage? { UIImage(systemName: "server.rack") }

    func createPanelView() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        
        let label = UILabel()
        label.text = "当前环境: 测试环境 (UAT)\n点击切换到预发环境"
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }
}

// 在 SDK 初始化后注册
ShowLog.registerCustomPanel(EnvironmentSwitcherPanel())
```

---

## 8. 生产包安全、App Store 提审合规与零开销保障

### 8.1 100% 零私有 API（App Store 提审绝对安全）
ShowLog 严守 Apple App Store 审核准则：
* 设备信息均使用 Darwin 内核标准 POSIX 接口（`sysctl`、`host_statistics64`、`statvfs`、`task_info`）与 `UIDevice` 公开 API。
* 不包含任何私有头文件（Private Frameworks）调用，不读取敏感硬件唯一标识符。
* 不访问相册、通讯录、定位等隐私权限，集成时**无需在 `Info.plist` 中声明任何额外权限描述**。

### 8.2 生产包零开销直通模式
若希望在生产环境完全剔除调试开销，建议通过编译标志控制：

```swift
#if DEBUG
let isDebug = true
#else
let isDebug = false
#endif

ShowLog.initialize(config: ShowLogConfig.Builder()
    .enabled(isDebug)
    .showFloatingView(isDebug)
    .enableURLSessionSwizzling(isDebug)
    .build())
```

当 `enabled = false` 时：
1. 悬浮球完全销毁并释放内存。
2. Method Swizzling 拦截逻辑直接返回原始实现，零性能损耗。
3. 数据库连接与批处理定时器彻底挂起关闭。
4. 所有 API 变为直通空操作。

---

## 9. Swift / Objective-C 混编与符号说明

ShowLog 采用纯 Swift 编写，并对所有核心入口标注了 `@objc` 属性，与 Objective-C 工程具有 100% 的互操作性。

### 9.1 类名映射表
| Swift 类名 | Objective-C 映射类名 | 说明 |
|:---|:---|:---|
| `ShowLog` | `ShowLog` | 顶层统一门面类 |
| `ShowLogConfig` | `ShowLogConfig` | 运行时不可变配置模型 |
| `ShowLogConfig.Builder` | `ShowLogConfigBuilder` | 链式配置构建器 |
| `HttpLogPayload` | `HttpLogPayload` | 强契约协议 |
| `CustomPanelProvider` | `CustomPanelProvider` | 自定义面板协议 |

### 9.2 Objective-C 初始化与调用范例
```objc
#import <ShowLog/ShowLog-Swift.h>

// 1. 初始化
ShowLogConfigBuilder *builder = [[ShowLogConfigBuilder alloc] init];
[builder enabled:YES];
[builder showFloatingView:YES];
[builder enableURLSessionSwizzling:YES];
[ShowLog initializeWithConfig:[builder build]];

// 2. 调出调试中枢
[ShowLog openHub];

// 3. 隐藏/展示悬浮球
[ShowLog setFloatWindowVisible:NO];
```

---

## 10. 代码混淆与安全加固配置（Anti-Obfuscation Rules）

### 10.1 SDK 内部抗混淆设计
* **零运行时字符串反射**：SDK 内部完全杜绝 `NSClassFromString`、`NSSelectorFromString` 及 Swift `Mirror`，网络日志数据层使用强类型原生 `libsqlite3` C API 显式参数绑定，天然免疫因类名、字段名混淆导致的反序列化或反射崩溃。
* **强类型静态绑定**：所有核心模型采用强类型属性，不受 Swift 编译器优化或 Name Mangling 剥离影响。

### 10.2 宿主 App 使用混淆工具时的白名单配置（Keep 规则）

如果宿主工程使用了**符号混淆工具**（如 SwiftShield、Hikari、OLLVM 或自研基于宏定义的符号替换工具），请按以下规则配置白名单：

#### 1. SwiftShield 混淆忽略
在 SwiftShield 配置文件中排除 `ShowLog` 模块：
```text
--ignore-modules ShowLog
```

#### 2. 自研宏混淆 / 符号混淆（Symbol Obfuscation 白名单）
ShowLog 在自动网络拦截中使用了针对 `URLSessionConfiguration` 的 Method Swizzling，请**严禁混淆以下选择器与核心入口类名**：
```c
// 保持 ShowLog 核心门面与配置类
ShowLog
ShowLogConfig
ShowLogConfigBuilder
HttpLogRecord
HttpLogPayload

// 保持网络 Swizzling 方法签名（避免 Method Swizzling 交换失败）
showlog_defaultSessionConfiguration
showlog_ephemeralSessionConfiguration
```

### 10.3 生产环境安全与代码剥离最佳实践
ShowLog 专为内部研发、QA 测试与灰度诊断设计。在正式上架 App Store 时，推荐通过编译宏确保 SDK 零侵入与零符号泄露：
```swift
#if DEBUG
import ShowLog
#endif

// 业务调用处
#if DEBUG
ShowLog.initialize(...)
#endif
```

---

## 11. API 核心参考速查表

### 顶层门面方法 (`ShowLog`)

| 方法签名 | 说明 |
|:---|:---|
| `ShowLog.initialize(config: ShowLogConfig)` | 全局单例初始化，建议在 `AppDelegate` 中调用 |
| `ShowLog.openHub()` | 编程式呼出 ShowLog 全景调试中枢界面 |
| `ShowLog.closeHub()` | 编程式收起 ShowLog 调试中枢 |
| `ShowLog.isHubPresented` | 判断当前 Hub 界面是否正处于展开显示状态 |
| `ShowLog.setFloatWindowVisible(_ visible: Bool)` | 动态控制吸边悬浮球的显示与隐藏 |
| `ShowLog.isFloatWindowVisible` | 查询当前悬浮球是否正处于可见状态 |
| `ShowLog.record(payload: HttpLogPayload)` | 手动向 SDK 管道中推入一条 HTTP 强契约日志记录 |
| `ShowLog.registerCustomPanel(_ provider: CustomPanelProvider)` | 动态注册业务自定义扩展调试面板 |
| `ShowLog.clearAllLogs()` | 清空本地已捕获的全部 HTTP 网络日志 |
| `ShowLog.destroy()` | 销毁并释放 ShowLog 所占用的全部视图、定时器与数据库连接 |

---

## 12. 版本历史与更新记录

| 版本号 | 发布日期 | 最低系统 | 核心特性与变更说明 |
|:---|:---|:---|:---|
| **`6.0.2`** | 2026-10-29 | iOS 13.0+ | **体验与交互升级版**：<br>1. **顶部 Tab 智能滑动居中**：点击或切换任意页签（网络/设备/自定义/文件），该 Tab 自动平滑滚动至视口正中央，完美适配带岛机型与各种紧凑屏幕；<br>2. **全景 Hub 安全区适配**：全面约束至 `safeAreaLayoutGuide`（上下避让 6pt、左右 8pt），彻底避开 iPhone 灵动岛和系统状态栏，杜绝误触；<br>3. **一体化视觉微重构**：底部增加深色暗黑轨道槽，彻底消除未选中 Tab 区域底层文字透光与重影；右上角关闭按钮重构为暗黑微边框胶囊样式（`#2C2C36` + `#33333D` 描边）；<br>4. **网络列表 Badge 与耗时直显**：状态码重构为墨绿（`200 OK`）与深红（`500/ERR`）胶囊 Badge，右上角直标请求耗时（如 `142ms`）；<br>5. **CocoaPods Trunk 官方发布**：已正式发布至 CocoaPods 官方源 `DialogLogShowManager`。 |
| **`6.0.1`** | 2026-10-29 | iOS 13.0+ | **高稳定性修复版**：<br>1. **避免 ObjC 运行时方法命名冲突**：修复 `@objcMembers` 导致 `CustomPanelPageView.release()` / `FileBrowserView.release()` 意外重载 Objective-C `-[NSObject release]`，引发无限递归爆栈崩溃（SIGSEGV / EXC_BAD_ACCESS），规范重构为 `teardown()`；<br>2. **耗电优化**：`AppDeviceInfoCollector` 电池状态采集完成后主动恢复初始监控状态，杜绝后台无谓耗电；<br>3. **强拆包安全防御**：移除 SQLite 助手与详情页多处潜在强拆包，改用安全可选合并 `??`；<br>4. **iPad 弹窗锚点安全**：修复系统分享面板在 iPad 上因 presenter.view 强拆包可能导致的隐患。 |
| **`6.0.0`** | 2026-10-28 | iOS 13.0+ | **首发企业级全景研发诊断中枢**：<br>1. **1:1 像素级对标 Android ShowLog v6.0**：原生 Swift 5.9+ / UIKit 编写，零第三方依赖；<br>2. **透明网络拦截与自定义业务裁决**：支持 URLSession / Alamofire 自动拦截与强契约 `HttpLogPayload` 手动上报，支持根据业务 JSON 自定义成功/失败判定；<br>3. **高性能 Hybrid-Read 仓储**：SQLite3 WAL 预写日志 + 500ms 定时聚合与单事务批量刷盘，支持多维检索与 cURL 导出；<br>4. **40+ 项设备全景看板**：实时监控硬件、系统、内存、CPU、磁盘并支持一键导出 Markdown 报告；<br>5. **沙盒文件只读浏览器**：防路径穿越安全校验 + 32KB 流式分页预览，支持 Documents/Library/Caches/tmp；<br>6. **业务自定义扩展**：开放 `CustomPanelProvider`，支持将业务私有调试工具无缝嵌入 Hub。 |

---

## 许可证
本项目采用 MIT 许可证，详情请参阅 LICENSE 文件。
