import Foundation
import Darwin
import Metal
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CFNetwork)
import CFNetwork
#endif

/// iOS 设备与应用系统 40+ 项全景指标安全采集器（对齐 Android `AppDeviceInfoCollector.java`）。
/// 为什么这样做：
/// 1. 100% 采用 Apple 公开 API 与 Darwin `sysctl`/`mach` 内核只读查询，0 私有 API、0 权限弹窗，通过 App Store 机审无风险；
/// 2. 每一项指标采集均具备独立容错兜底，确保任何极端越狱环境或沙盒限制下绝不崩溃；
/// 3. 按「应用画像」、「操作系统」、「硬件屏幕」、「运行性能」四大维度组织，支持实时刷新。
@objcMembers
public final class AppDeviceInfoCollector: NSObject {

    private static let processLaunchDate = Date()

    private override init() {
        super.init()
    }

    public static func collect() -> AppDeviceInfo {
        var items: [AppDeviceInfo.InfoItem] = []
        collectAppProfile(&items)
        collectOSInfo(&items)
        collectHardwareAndDisplay(&items)
        collectRuntimePerformance(&items)
        return AppDeviceInfo(items: items)
    }

    // MARK: - 1. 应用画像 (App Profile)

    private static func collectAppProfile(_ items: inout [AppDeviceInfo.InfoItem]) {
        let cat = AppDeviceInfo.CATEGORY_APP
        let bundle = Bundle.main
        let infoDict = bundle.infoDictionary ?? [:]

        let appName = (infoDict["CFBundleDisplayName"] as? String)
            ?? (infoDict["CFBundleName"] as? String)
            ?? ProcessInfo.processInfo.processName
        items.append(.init(category: cat, key: "应用名称", value: appName, isImportant: true))

        let bundleId = bundle.bundleIdentifier ?? "unknown.bundle.id"
        items.append(.init(category: cat, key: "应用包名 (Bundle ID)", value: bundleId, isImportant: true))

        let shortVersion = (infoDict["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        items.append(.init(category: cat, key: "版本名称 (Version)", value: shortVersion, isImportant: true))

        let buildVersion = (infoDict["CFBundleVersion"] as? String) ?? "1"
        items.append(.init(category: cat, key: "构建版本号 (Build)", value: buildVersion))

        let minOS = (infoDict["MinimumOSVersion"] as? String) ?? "13.0"
        items.append(.init(category: cat, key: "最低系统版本 (MinimumOS)", value: "iOS \(minOS)"))

        #if DEBUG
        let buildType = "DEBUG (可调试包)"
        #else
        let buildType = "RELEASE (正式生产包)"
        #endif
        items.append(.init(category: cat, key: "构建类型 (Build Type)", value: buildType, isImportant: true))

        items.append(.init(category: cat, key: "签名与分发环境", value: detectSigningEnvironment(), isImportant: true))
        items.append(.init(category: cat, key: "可执行指令架构", value: currentArchitecture()))

        let bundlePath = bundle.bundlePath
        let bundleSize = directorySize(atPath: bundlePath, maxDepth: 2)
        items.append(.init(category: cat, key: "App Bundle 目录体积", value: formatBytes(bundleSize)))

        let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        let docSize = directorySize(atPath: docPath, maxDepth: 3)
        items.append(.init(category: cat, key: "沙盒 Documents 占用", value: formatBytes(docSize)))

        let cachePath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""
        let cacheSize = directorySize(atPath: cachePath, maxDepth: 3)
        items.append(.init(category: cat, key: "沙盒 Caches 缓存占用", value: formatBytes(cacheSize)))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let launchStr = formatter.string(from: processLaunchDate)
        let runningSec = Int(max(0, Date().timeIntervalSince(processLaunchDate)))
        items.append(.init(category: cat, key: "本次进程启动时间", value: "\(launchStr) (已运行 \(formatDuration(seconds: runningSec)))"))
    }

    // MARK: - 2. 操作系统 (OS & Runtime)

    private static func collectOSInfo(_ items: inout [AppDeviceInfo.InfoItem]) {
        let cat = AppDeviceInfo.CATEGORY_OS
        let procInfo = ProcessInfo.processInfo

        #if canImport(UIKit)
        let osVersion = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let osVersion = procInfo.operatingSystemVersionString
        #endif
        items.append(.init(category: cat, key: "操作系统版本", value: osVersion, isImportant: true))

        let bitness = MemoryLayout<Int>.size == 8 ? "64-bit" : "32-bit"
        items.append(.init(category: cat, key: "系统指令位数", value: bitness))

        items.append(.init(category: cat, key: "Darwin 内核版本", value: unameKernelVersion()))

        let preferredLang = Locale.preferredLanguages.first ?? Locale.current.identifier
        items.append(.init(category: cat, key: "系统首选语言", value: preferredLang))

        let tz = TimeZone.current
        let regionCode = Locale.current.regionCode ?? "CN"
        items.append(.init(category: cat, key: "当前时区与地区", value: "\(tz.identifier) (\(tz.abbreviation() ?? "GMT")) / \(regionCode)"))

        let isJailbroken = detectJailbreakIndicators()
        items.append(.init(
            category: cat,
            key: "越狱特征检测 (Root/JB)",
            value: isJailbroken ? "⚠️ 检测到越狱环境特征" : "安全 (未检测到越狱特征)",
            isImportant: isJailbroken
        ))

        let lowPower: String
        if #available(iOS 9.0, macOS 12.0, *) {
            lowPower = procInfo.isLowPowerModeEnabled ? "已开启 (低电量省电中)" : "未开启 (标准模式)"
        } else {
            lowPower = "未开启"
        }
        items.append(.init(category: cat, key: "低电量模式状态", value: lowPower))

        let uptimeSec = Int(procInfo.systemUptime)
        items.append(.init(category: cat, key: "系统持续开机时长", value: formatDuration(seconds: uptimeSec)))
    }

    // MARK: - 3. 硬件屏幕 (Hardware & Display)

    private static func collectHardwareAndDisplay(_ items: inout [AppDeviceInfo.InfoItem]) {
        let cat = AppDeviceInfo.CATEGORY_HARDWARE
        let machineCode = hardwareMachineIdentifier()
        let friendlyName = mapDeviceModelName(machineCode)
        items.append(.init(category: cat, key: "设备型号标识", value: "\(friendlyName) (\(machineCode))", isImportant: true))

        #if canImport(UIKit)
        let idiom: String
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: idiom = "iPhone"
        case .pad: idiom = "iPad"
        case .tv: idiom = "Apple TV"
        case .carPlay: idiom = "CarPlay"
        case .mac: idiom = "Mac (Catalyst)"
        default: idiom = "iOS Device"
        }
        #if targetEnvironment(simulator)
        let deviceTypeStr = "\(idiom) (Simulator 模拟器)"
        #else
        let deviceTypeStr = "\(idiom) (真机)"
        #endif
        items.append(.init(category: cat, key: "终端设备形态", value: deviceTypeStr))

        let screenBounds = UIScreen.main.bounds
        let nativeBounds = UIScreen.main.nativeBounds
        let scale = UIScreen.main.scale
        items.append(.init(
            category: cat,
            key: "物理分辨率 (Pixels)",
            value: "\(Int(nativeBounds.width)) × \(Int(nativeBounds.height)) px",
            isImportant: true
        ))
        items.append(.init(
            category: cat,
            key: "逻辑分辨率 (Points)",
            value: "\(Int(screenBounds.width)) × \(Int(screenBounds.height)) pt (@\(Int(scale))x)"
        ))
        items.append(.init(category: cat, key: "屏幕缩放因子 (Scale)", value: String(format: "%.1fx (@%dx)", scale, Int(scale))))
        items.append(.init(category: cat, key: "屏幕最大刷新率", value: "\(UIScreen.main.maximumFramesPerSecond) Hz"))

        let isLandscape = screenBounds.width > screenBounds.height
        items.append(.init(category: cat, key: "当前屏幕方向", value: isLandscape ? "横屏 (Landscape)" : "竖屏 (Portrait)"))

        let safeInsets = currentSafeAreaInsets()
        items.append(.init(
            category: cat,
            key: "安全区域边距 (SafeArea)",
            value: String(format: "Top:%.0f, Bottom:%.0f, Left:%.0f, Right:%.0f pt", safeInsets.top, safeInsets.bottom, safeInsets.left, safeInsets.right)
        ))

        let wasBatteryEnabled = UIDevice.current.isBatteryMonitoringEnabled
        if !wasBatteryEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let stateDesc: String
        switch state {
        case .charging: stateDesc = "充电中"
        case .full: stateDesc = "已充满"
        case .unplugged: stateDesc = "未充电 (放电中)"
        default: stateDesc = "模拟器 / 状态未知"
        }
        let levelStr = level >= 0 ? "\(Int(level * 100))% (\(stateDesc))" : stateDesc
        items.append(.init(category: cat, key: "电池电量与状态", value: levelStr))
        #else
        items.append(.init(category: cat, key: "终端设备形态", value: "macOS Host"))
        items.append(.init(category: cat, key: "物理分辨率 (Pixels)", value: "N/A"))
        items.append(.init(category: cat, key: "逻辑分辨率 (Points)", value: "N/A"))
        #endif

        let (totalDisk, freeDisk) = queryDiskSpace()
        items.append(.init(
            category: cat,
            key: "磁盘容量 (可用 / 总计)",
            value: "\(formatBytes(freeDisk)) 可用 / 共 \(formatBytes(totalDisk))",
            isImportant: true
        ))

        let netInfo = queryLocalIPAndNetworkInterfaces()
        items.append(.init(category: cat, key: "网络连接通道", value: netInfo.interfaceSummary, isImportant: true))
        items.append(.init(category: cat, key: "本机局域网 / 蜂窝 IP", value: netInfo.ipAddress))
        items.append(.init(category: cat, key: "系统代理与 VPN 状态", value: detectProxyAndVPNStatus(hasUtun: netInfo.hasVpnTunnel)))
    }

    // MARK: - 4. 运行性能 (Runtime Performance)

    private static func collectRuntimePerformance(_ items: inout [AppDeviceInfo.InfoItem]) {
        let cat = AppDeviceInfo.CATEGORY_PERFORMANCE
        let procInfo = ProcessInfo.processInfo

        let footprint = queryAppMemoryFootprint()
        let resident = queryAppResidentMemory()
        let totalMem = Int64(procInfo.physicalMemory)
        let freeMem = querySystemAvailableMemory()

        let ratio = totalMem > 0 ? Double(footprint) / Double(totalMem) * 100.0 : 0.0
        items.append(.init(
            category: cat,
            key: "App 物理内存占用 (Footprint)",
            value: String(format: "%@ (占总内存 %.2f%%)", formatBytes(footprint), ratio),
            isImportant: true
        ))
        items.append(.init(
            category: cat,
            key: "进程驻留内存 (Resident)",
            value: formatBytes(resident)
        ))
        items.append(.init(
            category: cat,
            key: "系统物理内存 (可用 / 总计)",
            value: "\(formatBytes(freeMem)) 可用 / 共 \(formatBytes(totalMem))",
            isImportant: true
        ))
        items.append(.init(
            category: cat,
            key: "CPU 逻辑核心数",
            value: "共 \(procInfo.processorCount) 核 (当前活跃 \(procInfo.activeProcessorCount) 核)"
        ))
        items.append(.init(
            category: cat,
            key: "当前进程活跃线程数",
            value: "\(queryProcessThreadCount()) 个线程",
            isImportant: true
        ))
        items.append(.init(
            category: cat,
            key: "设备散热状态 (Thermal)",
            value: thermalStateDescription(procInfo.thermalState)
        ))

        let gpuName = MTLCreateSystemDefaultDevice()?.name ?? "Apple Integrated GPU"
        items.append(.init(category: cat, key: "Metal 图形处理器 (GPU)", value: gpuName))
        items.append(.init(category: cat, key: "主线程状态", value: Thread.isMainThread ? "正常响应 (MainThread)" : "后台采样中"))
    }

    // MARK: - Low-Level System Queries

    private static func detectSigningEnvironment() -> String {
        #if targetEnvironment(simulator)
        return "Simulator (模拟器调试)"
        #else
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            return "Development / Enterprise (含描述文件)"
        }
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            if receiptURL.lastPathComponent == "sandboxReceipt" {
                return "TestFlight / Sandbox (沙盒内测包)"
            }
            if FileManager.default.fileExists(atPath: receiptURL.path) {
                return "App Store (正式商店分发)"
            }
        }
        return "Local / Ad-Hoc Build"
        #endif
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64 (64位 Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (64位 Intel Simulator)"
        #else
        return "unknown"
        #endif
    }

    private static func unameKernelVersion() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let release = withUnsafePointer(to: &sysinfo.release) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let sysname = withUnsafePointer(to: &sysinfo.sysname) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return "\(sysname) \(release)"
    }

    private static func hardwareMachineIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simModel.isEmpty {
            return simModel
        }
        #endif
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "iPhone" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    private static func mapDeviceModelName(_ identifier: String) -> String {
        let map: [String: String] = [
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus"
        ]
        if let mapped = map[identifier] {
            return mapped
        }
        if identifier.hasPrefix("iPhone") { return "iPhone" }
        if identifier.hasPrefix("iPad") { return "iPad" }
        return identifier
    }

    private static func detectJailbreakIndicators() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
        #endif
    }

    #if canImport(UIKit)
    private static func currentSafeAreaInsets() -> UIEdgeInsets {
        if Thread.isMainThread {
            if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first {
                return window.safeAreaInsets
            }
        }
        return .zero
    }
    #endif

    private static func queryDiskSpace() -> (total: Int64, free: Int64) {
        let home = NSHomeDirectory()
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home) {
            let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            return (total, free)
        }
        return (0, 0)
    }

    private static func queryLocalIPAndNetworkInterfaces() -> (ipAddress: String, interfaceSummary: String, hasVpnTunnel: Bool) {
        var wifiIP: String?
        var cellularIP: String?
        var hasUtun = false

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            defer { freeifaddrs(ifaddr) }
            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let current = ptr {
                let interface = current.pointee
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                    hasUtun = true
                }
                if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostname)
                        if name == "en0" {
                            wifiIP = ip
                        } else if name.hasPrefix("pdp_ip") {
                            cellularIP = ip
                        }
                    }
                }
                ptr = interface.ifa_next
            }
        }

        if let wifi = wifiIP {
            return (wifi, "Wi-Fi 无线局域网 (en0)", hasUtun)
        } else if let cell = cellularIP {
            return (cell, "蜂窝移动数据网络 (pdp_ip)", hasUtun)
        } else {
            return ("127.0.0.1 (未连接外部网络)", "无活动外部网络连接", hasUtun)
        }
    }

    private static func detectProxyAndVPNStatus(hasUtun: Bool) -> String {
        var parts: [String] = []
        #if canImport(CFNetwork)
        if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let httpProxy = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
               !httpProxy.isEmpty {
                let port = settings[kCFNetworkProxiesHTTPPort as String] ?? ""
                parts.append("HTTP代理: \(httpProxy):\(port)")
            }
        }
        #endif
        if hasUtun {
            parts.append("VPN/虚拟网卡已激活 (utun)")
        }
        return parts.isEmpty ? "直连 (无 HTTP 代理 / 无 VPN)" : parts.joined(separator: " | ")
    }

    private static func queryAppMemoryFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Int64(info.phys_footprint)
        }
        return queryAppResidentMemory()
    }

    private static func queryAppResidentMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        }
        return 0
    }

    private static func querySystemAvailableMemory() -> Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let pageSize = Int64(vm_kernel_page_size)
            let freePages = Int64(stats.free_count) + Int64(stats.inactive_count)
            return freePages * pageSize
        }
        return 0
    }

    private static func queryProcessThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kerr == KERN_SUCCESS, let list = threadList else {
            return 1
        }
        let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
        return Int(threadCount)
    }

    private static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "正常 (Nominal · 温控良好)"
        case .fair: return "轻度温升 (Fair)"
        case .serious: return "⚠️ 发热严重 (Serious · 系统可能降频)"
        case .critical: return "🔥 极度过热 (Critical · 严重降频保护)"
        @unknown default: return "未知状态"
        }
    }

    private static func directorySize(atPath path: String, maxDepth: Int) -> Int64 {
        guard !path.isEmpty else { return 0 }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard maxDepth > 0, let children = try? fm.contentsOfDirectory(atPath: path) else {
            return 0
        }
        var total: Int64 = 0
        for child in children.prefix(200) {
            let childPath = (path as NSString).appendingPathComponent(child)
            total += directorySize(atPath: childPath, maxDepth: maxDepth - 1)
        }
        return total
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: "%.2f MB", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    private static func formatDuration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return "\(h)小时\(m)分\(s)秒"
        } else if m > 0 {
            return "\(m)分\(s)秒"
        } else {
            return "\(s)秒"
        }
    }
}
