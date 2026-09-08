/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 设置页：运行配置、权限状态、通用管理、赞赏入口。
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var noticeMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                runConfigSection
                entitlementSection
                generalSection
                donationSection
            }
            .navigationTitle("设置")
            .alert(item: Binding<IdentifiableString?>(
                get: { noticeMessage.map(IdentifiableString.init) },
                set: { noticeMessage = $0?.value }
            )) { item in
                Alert(title: Text("提示"), message: Text(item.value), dismissButton: .default(Text("确定")))
            }
        }
    }

    // 运行配置。
    private var runConfigSection: some View {
        Section("运行配置") {
            Stepper("执行线程数：\(appState.threadCount)", value: $appState.threadCount, in: 1...16)
            Stepper("单应用内存上限：\(appState.memoryLimitMB) MB", value: $appState.memoryLimitMB, in: 64...4096, step: 64)
            Picker("日志等级", selection: $appState.logLevel) {
                ForEach(LogLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
        }
    }

    // 权限状态：缺失红色高亮。
    private var entitlementSection: some View {
        Section("签名权限状态") {
            let report = appState.entitlementReport
            entitlementRow("大地址空间", status: report.largeAddressSpace)
            entitlementRow("大内存", status: report.largeMemory)

            if !report.fullySatisfied {
                if let tip = report.degradedTipText {
                    Text(tip)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // 通用管理。
    private var generalSection: some View {
        Section("通用管理") {
            Button("清理全局缓存") {
                _ = try? SDRSandboxCache.sharedCache().clearAllCaches()
                appState.log.info("已清理全局缓存")
                noticeMessage = "已清理全局缓存"
            }
            Button("沙盒目录管理") {
                let pkgs = SDRSandboxDirectory.sharedDirectory().installedPackageNames()
                noticeMessage = "已安装沙盒：\(pkgs.joined(separator: "、"))"
            }
            Button("重置应用列表", role: .destructive) {
                appState.resetAllApps()
                noticeMessage = "已重置应用列表"
            }
        }
    }

    // 赞赏入口。
    private var donationSection: some View {
        Section("赞赏") {
            VStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.system(size: 80))
                    .foregroundColor(.secondary)
                Text("自愿支持开发，不解锁任何功能")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func entitlementRow(_ title: String, status: SDREntitlementStatus) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(entitlementText(status))
                .foregroundColor(status == .present ? .green : .red)
        }
    }

    private func entitlementText(_ status: SDREntitlementStatus) -> String {
        if status == .present { return "已开启" }
        if status == .missing { return "缺失" }
        return "无法检测"
    }
}