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

// 运行阶段（与 ObjC 侧 SDRLaunchStage 对齐，rawValue 一致）。
enum RunStage: Int, CaseIterable {
    case verifyFile = 0
    case parseDex
    case createVM
    case loadClass
    case findEntry
    case startActivity
    case running
    case failed

    var title: String {
        switch self {
        case .verifyFile:   return "校验文件"
        case .parseDex:     return "解析 DEX"
        case .createVM:     return "创建虚拟机"
        case .loadClass:    return "加载类与资源"
        case .findEntry:    return "查找入口"
        case .startActivity: return "启动 Activity"
        case .running:      return "运行中"
        case .failed:       return "启动失败"
        }
    }
}

// 全局应用状态：已导入应用、运行配置、日志、权限报告、运行状态页进度。
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

    // 运行状态页进度
    @Published var runStage: RunStage = .verifyFile
    @Published var runStageDetail: String = ""
    @Published var launchError: String? = nil
    @Published var runningApp: InstalledApp? = nil   // 用于弹出运行状态页（sheet item）

    // 启动超时保护（15 秒）
    private var launchTimeoutWorkItem: DispatchWorkItem?

    // MARK: - 导入流程（前置预检 → 加固检测 → 签名校验 → 解析 → 分类解压）

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

        // 0. 前置预检：存在性 / 大小 / ZIP 魔数，非法包直接拦截，杜绝解析崩溃。
        if let precheckError = Self.precheckApk(data) {
            log.error("前置预检失败：\(precheckError)", module: "apk-tool", package: url.lastPathComponent)
            return .invalid(precheckError)
        }

        // 1. 加固检测：命中即拦截。
        let detector = SDRHardeningDetector()
        if let hardenedName = detector.detect(inRawData: data) {
            log.error("检测到加固：\(hardenedName)，已拒绝导入", module: "apk-tool", package: url.lastPathComponent)
            return .hardened(hardenedName)
        }

        // 2. 签名校验：未签名 / 签名失效 → 拒绝并引导前往签名。
        guard let sigResult = try? SDRSignatureVerifier().verifyApkData(data, error: nil) else {
            return .invalid("签名校验失败")
        }
        guard sigResult.isSigned else {
            log.error("未签名或签名失效，已拒绝导入", module: "apk-tool", package: url.lastPathComponent)
            return .unsigned
        }

        // 3. 解析 APK 元数据（全链路异常捕获，失败仅返回错误不崩溃）。
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
            log.info("已按类型分类解压：\(installed.dexFiles.count) 个 DEX / \(installed.nativeLibs.count) 个 SO",
                     module: "apk-tool", package: info.packageName)
        } else {
            log.warn("自动分类解压未完成（不影响导入）", module: "apk-tool", package: info.packageName)
        }

        let app = InstalledApp(info: info,
                               signatureSummary: sigResult.summaryMessage,
                               fileSize: Int64(data.count),
                               apkStoredPath: storedPath)
        installedApps.append(app)

        // 准备沙盒目录。
        _ = SDRSandboxDirectory.shared().ensureDataRoot(forPackage: info.packageName)
        log.info("导入成功：\(info.packageName)（\(app.formattedSize)，\(info.activities.count) 个 Activity）",
                 module: "apk-tool", package: info.packageName)
        return .success(app)
    }

    // APK 前置预检：存在性 / 最小大小 / ZIP 魔数校验。
    private static func precheckApk(_ data: Data) -> String? {
        // 存在性：空数据。
        if data.isEmpty { return "文件内容为空" }
        // 最小大小：ZIP EOCD 记录至少 22 字节。
        if data.count < 22 { return "文件过小，不是有效的 APK 容器" }
        // ZIP 魔数：本地文件头 / 空归档 EOCD / 分卷归档。
        let pk = [UInt8](data.prefix(4))
        let isZip = pk == [0x50, 0x4B, 0x03, 0x04] ||
                    pk == [0x50, 0x4B, 0x05, 0x06] ||
                    pk == [0x50, 0x4B, 0x07, 0x08]
        if !isZip { return "文件格式无效（非 ZIP / APK 容器）" }
        return nil
    }

    // MARK: - 启动执行

    func launch(_ app: InstalledApp) {
        guard !isRunning else {
            log.warn("已有应用运行中，无法重复启动", module: "ui", package: app.packageName)
            return
        }
        isRunning = true
        runningPackageName = app.packageName
        runningApp = app
        runStage = .verifyFile
        runStageDetail = "准备启动"
        launchError = nil
        log.info("正在启动 \(app.packageName)（DEX 解释执行）", module: "ui", package: app.packageName)

        // 15 秒启动超时保护：避免解释执行卡死导致「无反应」。
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.log.warn("启动超时（15 秒），已强制终止等待", module: "ui", package: app.packageName)
            self.launchError = "启动超时（15 秒），可能卡在某一阶段，请查看运行日志排查。"
            self.runStage = .failed
            self.isRunning = false
            self.runningPackageName = nil
        }
        launchTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)

        let runtime = SDRAppRuntime.sharedInstance()
        DispatchQueue.global(qos: .userInitiated).async {
            runtime.launchApk(atPath: app.apkStoredPath,
                              packageName: app.packageName,
                              progress: { [weak self] stage, detail in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.runStage = RunStage(rawValue: stage.rawValue) ?? .failed
                    self.runStageDetail = detail ?? ""
                    if stage == .failed {
                        self.launchError = detail
                    }
                    self.log.info("启动阶段：\(detail ?? "")", module: "framework", package: app.packageName)
                }
            },
            completion: { [weak self] summary, steps, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.launchTimeoutWorkItem?.cancel()
                    self.launchTimeoutWorkItem = nil
                    if let error = error {
                        self.log.error("启动失败：\(error.localizedDescription)", module: "framework", package: app.packageName)
                        self.launchError = error.localizedDescription
                        self.runStage = .failed
                    } else {
                        if let steps = steps, !steps.isEmpty {
                            for step in steps { self.log.info(step, module: "framework", package: app.packageName) }
                        }
                        if let summary = summary, !summary.isEmpty {
                            self.log.info(summary, module: "framework", package: app.packageName)
                        }
                        if self.runStage != .failed {
                            self.runStage = .running
                        }
                    }
                    self.isRunning = false
                    self.runningPackageName = nil
                }
            })
        }
    }

    // 停止运行：取消超时、清理任务栈、关闭运行状态页。
    func stopRun() {
        launchTimeoutWorkItem?.cancel()
        launchTimeoutWorkItem = nil
        SDRActivityStack.sharedStack().removeAll()
        isRunning = false
        runningPackageName = nil
        if let pkg = runningApp?.packageName {
            log.info("已停止运行", module: "ui", package: pkg)
        }
        runningApp = nil
        launchError = nil
    }

    // MARK: - 应用管理

    func delete(_ app: InstalledApp) {
        installedApps.removeAll { $0.id == app.id }
        _ = try? SDRSandboxDirectory.shared().removeDataRoot(forPackage: app.packageName)
        if !app.apkStoredPath.isEmpty {
            try? FileManager.default.removeItem(atPath: app.apkStoredPath)
        }
        log.info("已删除：\(app.packageName)", module: "ui", package: app.packageName)
    }

    func resetAllApps() {
        installedApps.removeAll()
        log.info("已重置应用列表", module: "ui")
    }

    func exportLogText() -> String { log.exportText() }

    // 导出完整运行时日志（磁盘持久化文件路径）。
    func runtimeLogFilePath() -> String? { log.logFilePath }
}