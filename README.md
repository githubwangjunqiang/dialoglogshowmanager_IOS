# ShowLog iOS SDK 开发者接入指南

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
10. [API 核心参考速查表](#10-api-核心参考速查表)

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
            .enabled(true)                       // 开启调试功能
            .showFloatWindow(true)               // 显示吸边悬浮球
            .autoCaptureNetwork(true)            // 自动拦截网络请求
            .maxRecordCount(500)                 // 最大保留 500 条日志
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
    [builder showFloatWindow:YES];
    [builder autoCaptureNetwork:YES];
    
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

#### Swift Package Manager (SPM) - 推荐
在 Xcode 中选择 `File` -> `Add Package Dependencies...`，填入 Git 仓库地址：
```text
https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git
```
或在 `Package.swift` 中添加：
```swift
dependencies: [
    .package(url: "https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git", from: "6.0.0")
]
```

#### CocoaPods
在 `Podfile` 中添加（支持 Git 直引或官方源）：
```ruby
# Git 直引方式
pod 'ShowLog', :git => 'https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git', :tag => '6.0.0'

# 或发布至公共源后使用：
# pod 'ShowLog', '~> 6.0.0'
```
随后执行：
```bash
pod install
```

### 4.2 配置参数全解 (`ShowLogConfig.Builder`)

| 方法 | 类型 | 默认值 | 说明 |
|:---|:---|:---|:---|
| `enabled(Bool)` | `Bool` | `true` | 全局总开关。设为 `false` 则激活零开销直通模式 |
| `showFloatWindow(Bool)` | `Bool` | `true` | 是否在应用启动时自动展示悬浮球 |
| `autoCaptureNetwork(Bool)` | `Bool` | `true` | 是否自动拦截原生 `URLSession` 请求 |
| `maxRecordCount(Int)` | `Int` | `1000` | 数据库最大记录上限（100 ~ 10,000，超出自动 LRU 修剪） |
| `maxBodyLength(Int)` | `Int` | `262,144` | 单条请求/响应 Body 截断大小（字节），默认 256KB |
| `batchFlushIntervalMs(Int)` | `Int` | `500` | 内存待落盘队列定时刷盘间隔（100ms ~ 5,000ms） |
| `shakeToOpen(Bool)` | `Bool` | `true` | 是否监听设备物理摇一摇手势呼出 Hub |
| `enableAppInfo(Bool)` | `Bool` | `true` | 是否启用设备诊断信息面板 |
| `enableFileBrowser(Bool)` | `Bool` | `true` | 是否启用沙盒文件只读浏览器 |
| `enableCustomPanels(Bool)` | `Bool` | `true` | 是否启用开发者自定义面板注入能力 |
| `filterUrlPatterns([String])` | `[String]` | `[]` | 黑名单正则/包含匹配，匹配到的 URL 不记录日志 |
| `businessJudger(HttpLogBusinessJudger?)` | 闭包协议 | `nil` | 自定义 HTTP 业务成功/失败裁决器 |

---

## 5. URLSession / Alamofire 网络日志自动拦截与业务裁决

### 5.1 自动拦截原理
初始化 `ShowLog` 时，若 `autoCaptureNetwork` 为 `true`，SDK 会自动将 `ShowLogURLProtocol` 注入至 `URLSessionConfiguration.default` 与 `ephemeral` 中。

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
ShowLog Hub 包含四个原生模块：
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
    .showFloatWindow(isDebug)
    .autoCaptureNetwork(isDebug)
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
[builder showFloatWindow:YES];
[ShowLog initializeWithConfig:[builder build]];

// 2. 调出调试中枢
[ShowLog openHub];

// 3. 隐藏/展示悬浮球
[ShowLog setFloatWindowVisible:NO];
```

---

## 10. API 核心参考速查表

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

## 许可证
本项目采用 MIT 许可证，详情请参阅 LICENSE 文件。
