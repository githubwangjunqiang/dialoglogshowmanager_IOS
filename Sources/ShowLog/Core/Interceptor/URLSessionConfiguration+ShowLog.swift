import Foundation
import ObjectiveC.runtime

/// `URLSessionConfiguration` 自动注入与防重辅助扩展。
/// 为什么这样做：
/// 1. `URLProtocol.registerClass(ShowLogURLProtocol.self)` 仅对 `URLSession.shared` 生效；
/// 2. 第三方网络库（如 Alamofire、AFNetworking）或自定义 `URLSession(configuration: .default)` 会读取 `URLSessionConfiguration.default`；
/// 3. 提供安全防重注入与可选 Getter Swizzle，让宿主既能零侵入自动拦截，也能显式调用 `ShowLog.inject(into:)`。
@objcMembers
public final class URLSessionConfigurationInjector: NSObject {

    private static var hasSwizzled = false
    private static let lock = NSLock()

    /// 将 `ShowLogURLProtocol` 注入到指定的 `URLSessionConfiguration`（内部防重复注入）。
    public static func inject(into configuration: URLSessionConfiguration) {
        var classes = configuration.protocolClasses ?? []
        let alreadyContains = classes.contains { $0 == ShowLogURLProtocol.self }
        if !alreadyContains {
            classes.insert(ShowLogURLProtocol.self, at: 0)
            configuration.protocolClasses = classes
        }
    }

    /// 启用全局 `URLProtocol` 注册与 `URLSessionConfiguration.default` / `.ephemeral` 自动注入。
    public static func enableAutomaticInterception(swizzleConfiguration: Bool) {
        URLProtocol.registerClass(ShowLogURLProtocol.self)
        guard swizzleConfiguration else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !hasSwizzled else { return }
        hasSwizzled = true

        swizzleClassSelector(
            cls: URLSessionConfiguration.self,
            original: #selector(getter: URLSessionConfiguration.default),
            swizzled: #selector(URLSessionConfiguration.showlog_defaultSessionConfiguration)
        )
        swizzleClassSelector(
            cls: URLSessionConfiguration.self,
            original: #selector(getter: URLSessionConfiguration.ephemeral),
            swizzled: #selector(URLSessionConfiguration.showlog_ephemeralSessionConfiguration)
        )
    }

    private static func swizzleClassSelector(cls: AnyClass, original: Selector, swizzled: Selector) {
        guard let metaClass = object_getClass(cls),
              let origMethod = class_getClassMethod(cls, original),
              let swizMethod = class_getClassMethod(cls, swizzled) else {
            return
        }
        let didAdd = class_addMethod(
            metaClass,
            original,
            method_getImplementation(swizMethod),
            method_getTypeEncoding(swizMethod)
        )
        if didAdd {
            class_replaceMethod(
                metaClass,
                swizzled,
                method_getImplementation(origMethod),
                method_getTypeEncoding(origMethod)
            )
        } else {
            method_exchangeImplementations(origMethod, swizMethod)
        }
    }
}

extension URLSessionConfiguration {

    @objc class func showlog_defaultSessionConfiguration() -> URLSessionConfiguration {
        let config = showlog_defaultSessionConfiguration()
        if ShowLog.isEnabled() {
            URLSessionConfigurationInjector.inject(into: config)
        }
        return config
    }

    @objc class func showlog_ephemeralSessionConfiguration() -> URLSessionConfiguration {
        let config = showlog_ephemeralSessionConfiguration()
        if ShowLog.isEnabled() {
            URLSessionConfigurationInjector.inject(into: config)
        }
        return config
    }
}
