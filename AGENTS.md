# AGENTS.md - ShowLog iOS 自动化交付与协同规则

本文件是专为 AI 编码助手（如 Antigravity / Cursor / Copilot 等）制定的项目级硬性执行规范。
在本仓库中，**凡是完成代码缺陷修复、功能迭代、性能优化或架构调整后，在向用户交付前必须严格按顺序完整执行以下 4 项闭环操作**，严禁遗漏任何环节。

---

## 交付闭环四步法则（必须依序执行）

```
[代码修改与验证通过]
       │
       ▼
1. 版本号自动 +1（语义化版本递增）
       │
       ▼
2. 同步更新接入指南与版本更新记录（README.md）
       │
       ▼
3. 提交改动、打 Tag 并推送至 Git 远程仓库
       │
       ▼
4. 发布到 CocoaPods 公共源（Trunk）
```

---

### 第一步：版本号自动 +1 (SemVer Bump)
按语义化版本规范对版本号执行小版本递增（例如修复 Bug 时从 `6.0.2` 升级为 `6.0.3`），且必须同时更新以下所有文件：
1. **`DialogLogShowManager.podspec`**：
   ```ruby
   s.version = '6.0.x'
   ```
2. **`ShowLog.podspec`**：
   ```ruby
   s.version = '6.0.x'
   ```
3. **`Example/ShowLogExample/Info.plist`**：
   ```xml
   <key>CFBundleShortVersionString</key>
   <string>6.0.x</string>
   ```

---

### 第二步：接入指南与版本更新记录同步更新 (`README.md`)
必须保持项目文档与实际发布的版本完全一致：
1. **更新依赖引入示例版本号**：
   - 方式一：CocoaPods 官方源引入版本 `pod 'DialogLogShowManager', '~> 6.0.x'`
   - 方式二：SPM 依赖版本 `.package(url: ..., from: "6.0.x")`
   - 方式三：Git 直引 Tag 声明 `:tag => '6.0.x'`
2. **更新第 12 节「版本历史与更新记录」表格**：
   在表格最顶行插入新版本条目，明确写出：
   - 版本号（如 `6.0.x`）
   - 发布日期（YYYY-MM-DD）
   - 最低兼容系统（iOS 13.0+）
   - 详细且专业的变更点（包括问题根因、修复方案、新增功能、UI 优化项）
3. **同步 API 变更**：若本次修改涉及公开方法、配置项增删改，必须同步更新文档对应章节与「11. API 核心参考速查表」。

---

### 第三步：执行同步 Git 仓库操作 (Git Sync & Tagging)
在推送前必须先在本地确保自动化测试通过（`swift test` 全部绿灯）：
1. **暂存并提交所有改动**：
   ```bash
   git add -A
   git commit -m "Release: bump version to 6.0.x with <修改摘要>"
   ```
2. **打上双版本 Tag**（保持兼容无 `v` 与带 `v` 两种习惯）：
   ```bash
   git tag 6.0.x
   git tag v6.0.x
   ```
3. **推送到 GitHub 远程仓库**：
   ```bash
   git push origin main
   git push origin 6.0.x v6.0.x
   ```
   > **注意**：若环境 SSH 22 端口受限，须使用 443 端口：`ssh -o Port=443 -o HostName=ssh.github.com`。

---

### 第四步：发布到 CocoaPods 公共源 (CocoaPods Trunk Push)
本项目已在 CocoaPods 官方中心注册库名 `DialogLogShowManager`（模块名为 `ShowLog`）。推送完远程 Tag 后，必须立即执行发布：
1. **执行 Trunk 发布命令**：
   ```bash
   pod trunk push DialogLogShowManager.podspec --allow-warnings
   ```
2. **验证结果**：
   确认控制台输出包含：
   ```text
   🎉 Congrats
   🚀 DialogLogShowManager (6.0.x) successfully published
   🌎 https://cocoapods.org/pods/DialogLogShowManager
   ```
3. 若发布失败，需排查网络、Tag 是否已生效或 podspec 语法警告并予以解决，确保发布成功闭环。
