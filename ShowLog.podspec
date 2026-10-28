Pod::Spec.new do |s|
  s.name             = 'ShowLog'
  s.version          = '6.0.0'
  s.summary          = '企业级 iOS 全景研发诊断与调试中枢 SDK（网络监控 + 设备看板 + 自定义扩展 + 沙盒文件浏览）'
  s.description      = <<-DESC
  ShowLog iOS SDK 1:1 复刻 Android ShowLog v6.0 全景研发诊断中枢：
  - URLSession / Alamofire 零侵入自动网络拦截、强契约非标准网络库上报、自定义业务成功裁决
  - 内存缓冲队列 + 500ms 批量单事务 SQLite WAL 落盘 + 双层 Hybrid-Read 混合读取
  - 40+ 项 iOS 设备与应用全景指标看板与 Markdown 报告一键导出
  - 业务自定义扩展面板与防路径穿越的只读沙盒文件浏览/流式预览
  - 免权限全局吸边悬浮球与生产环境零开销直通模式
  DESC
  s.homepage         = 'https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'githubwangjunqiang' => '19901021qiang@gmail.com' }
  s.source           = { :git => 'https://github.com/githubwangjunqiang/dialoglogshowmanager_IOS.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.9'
  s.source_files          = 'Sources/ShowLog/**/*.swift'
  s.libraries             = 'sqlite3', 'z'
  s.frameworks            = 'UIKit', 'Foundation', 'SystemConfiguration', 'Metal', 'ImageIO', 'Security'
end
