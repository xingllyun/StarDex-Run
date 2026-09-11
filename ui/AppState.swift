/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import Foundation
import Combine
import UIKit

// 已导入应用的 UI 模型（包装 SDRApkInfo）。
struct InstalledApp: Identifiable {
    let id = UUID()
    let info: SDRApkInfo
    let signatureSummary: String
    let fileSize: Int64                    // APK 文件大小（字节）
    let apkStoredPath: String              // 沙盒内 APK 副本路径（供运行执行读取）

    var packageName: String { info.packageName }
    var versionName: String { info.versionName }
    var displayTitle: String { info.appLabel.isEmpty ? packageName : info.appLabel }
    var versionCode: Int64 { info.versionCode }
    var icon: UIImage? { info.iconData.flatMap { UIImage(data: $0) } }
    var permissionCount: Int { info.permissions.count }
    var dexCount: Int { max(info.dexFiles.count, 1) }
    var activityCount: Int { info.activities.count }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// 导入结果。
enum APKImportOutcome {
    case success(InstalledApp)
    case hardened(String)   // 命中的加固方案名
    case unsigned           // 未签名 / 签名失效
    case invalid(String)    // 解析失败原因
}

// 全局应用状态：已导入应用、运行配置、日志、权限报告。
final class AppState: ObservableObject {
    let log = LogStore()
    let entitlementReport: SDREntitlementReport = SDREntitlementChecker.checkCurrentProcess()
    let versionAdapter: SDRVersionAdapter = .shared()

    @Published var installedApps: [InstalledApp] = []

    // 运行配置
    @Published var threadCount: Int = 2
    @Published var memoryLimitMB: Int = 512
    @Published var logLevel: LogLevel = .info

    // 全局运行状态
    @Published var isRunning: Bool = false
    @Published var runningPackageName: String? = nil

    // MARK: - 导入流程（加固检测 → 签名校验 → 解析）

    func importApk(at url: URL) -> APKImportOutcome {
        // 安全作用域资源访问：文件选取器返回的外部 URL 必须先申请读取权限。
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            // 映射式读取：大体积 APK 不全量驻留物理内存，降低内存峰值。
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return .invalid("读取文件失败（无访问权限）：\(error.localizedDescription)")
        }

        // 1. 加固检测：命中即拦截。
        let detector = SDRHardeningDetector()
        if let hardenedName = detector.detect(inRawData: data) {
            log.error("检测到加固：\(hardenedName)，已拒绝导入", package: url.lastPathComponent)
            return .hardened(hardenedName)
        }

        // 2. 签名校验：未签名 / 签名失效 → 拒绝并引导前往签名。
        guard let sigResult = try? SDRSignatureVerifier().verifyApkData(data, error: nil) else {
            return .invalid("签名校验失败")
        }
        guard sigResult.isSigned else {
            log.error("未签名或签名失效，已拒绝导入", package: url.lastPathComponent)
            return .unsigned
        }

        // 3. 解析 APK 元数据。
        guard let parser = try? SDRApkParser(apkData: data) else {
            return .invalid("无法解包 APK")
        }
        guard let info = try? parser.parseInfo() else {
            return .invalid("无法解析 AndroidManifest.xml（可能为非常规编译或加固残留结构）")
        }
        guard !info.packageName.isEmpty else {
            return .invalid("Manifest 解析结果不完整（包名为空）")
        }

        // 4. 复制 APK 到沙盒，供「启动」执行时读取 DEX。
        let container = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let apkDir = container.appendingPathComponent("apks", isDirectory: true)
        var storedPath = ""
        do {
            try FileManager.default.createDirectory(at: apkDir, withIntermediateDirectories: true)
            let storedURL = apkDir.appendingPathComponent("\(info.packageName).apk")
            try data.write(to: storedURL, options: .atomic)
            storedPath = storedURL.path
        } catch {
            return .invalid("无法保存 APK 副本：\(error.localizedDescription)")
        }

        // 4b. 自动解压分类存放（DEX / SO / 资源 / Manifest → 沙盒对应子目录）。
        //     分类失败仅记录告警，不阻断导入（运行阶段可回退为按需解析）。
        let installInfo: SDRApkInfo? = (try? SDRPackageInstaller.shared().installApk(atPath: storedPath)) ?? nil
        if let installed = installInfo {
            log.info("已按类型分类解压：\(installed.dexFiles.count) 个 DEX / \(installed.nativeLibs.count) 个 SO", package: info.packageName)
        } else {
            log.warn("自动分类解压未完成（不影响导入）", package: info.packageName)
        }

        let app = InstalledApp(info: info,
                               signatureSummary: sigResult.summaryMessage,
                               fileSize: Int64(data.count),
                               apkStoredPath: storedPath)
        installedApps.append(app)

        // 准备沙盒目录。
        _ = SDRSandboxDirectory.shared().ensureDataRoot(forPackage: info.packageName)
        log.info("导入成功：\(info.packageName)（\(app.formattedSize)，\(info.activities.count) 个 Activity）", package: info.packageName)
        return .success(app)
    }

    // MARK: - 启动执行

    func launch(_ app: InstalledApp) {
        guard !isRunning else {
            log.warn("已有应用运行中，无法重复启动", package: app.packageName)
            return
        }
        isRunning = true
        runningPackageName = app.packageName
        log.info("正在启动 \(app.packageName)（DEX 解释执行）", package: app.packageName)

        let runtime = SDRAppRuntime.sharedInstance()
        DispatchQueue.global(qos: .userInitiated).async {
            runtime.launchApk(atPath: app.apkStoredPath,
                              packageName: app.packageName,
                              completion: { summary, steps, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.log.error("启动失败：\(error.localizedDescription)", package: app.packageName)
                    } else {
                        if let steps = steps, !steps.isEmpty {
                            for step in steps { self.log.info(step, package: app.packageName) }
                        }
                        if let summary = summary, !summary.isEmpty {
                            self.log.info(summary, package: app.packageName)
                        }
                    }
                    self.isRunning = false
                    self.runningPackageName = nil
                }
            })
        }
    }

    // MARK: - 应用管理

    func delete(_ app: InstalledApp) {
        installedApps.removeAll { $0.id == app.id }
        _ = try? SDRSandboxDirectory.shared().removeDataRoot(forPackage: app.packageName)
        if !app.apkStoredPath.isEmpty {
            try? FileManager.default.removeItem(atPath: app.apkStoredPath)
        }
        log.info("已删除：\(app.packageName)", package: app.packageName)
    }

    func resetAllApps() {
        installedApps.removeAll()
        log.info("已重置应用列表")
    }

    func exportLogText() -> String { log.exportText() }
}