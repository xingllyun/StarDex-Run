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

    var packageName: String { info.packageName }
    var versionName: String { info.versionName }
    var displayTitle: String { info.appLabel.isEmpty ? packageName : info.appLabel }
    var versionCode: Int64 { info.versionCode }
    var icon: UIImage? { info.iconData.flatMap { UIImage(data: $0) } }
    var permissionCount: Int { info.permissions.count }
    var dexCount: Int { info.dexFiles.count }
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
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .invalid("读取文件失败：\(error.localizedDescription)")
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
            return .invalid("无法解析 AndroidManifest.xml")
        }

        let app = InstalledApp(info: info, signatureSummary: sigResult.summaryMessage)
        installedApps.append(app)

        // 准备沙盒目录。
        _ = SDRSandboxDirectory.shared().ensureDataRoot(forPackage: info.packageName)
        log.info("导入成功：\(info.packageName)", package: info.packageName)
        return .success(app)
    }

    // MARK: - 应用管理

    func delete(_ app: InstalledApp) {
        installedApps.removeAll { $0.id == app.id }
        _ = try? SDRSandboxDirectory.shared().removeDataRoot(forPackage: app.packageName)
        log.info("已删除：\(app.packageName)", package: app.packageName)
    }

    func resetAllApps() {
        installedApps.removeAll()
        log.info("已重置应用列表")
    }

    func exportLogText() -> String { log.exportText() }
}