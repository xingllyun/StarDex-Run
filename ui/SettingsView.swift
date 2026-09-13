/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 全新设计的设置页
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var noticeMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                Form {
                    runConfigSection
                    entitlementSection
                    generalSection
                    donationSection
                }
                .scrollContentBackground(.hidden)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StarDexTopBar(title: "设置")
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .alert(item: Binding<IdentifiableString?>(
                get: { noticeMessage.map(IdentifiableString.init) },
                set: { noticeMessage = $0?.value }
            )) { item in
                Alert(title: Text("提示"), message: Text(item.value), dismissButton: .default(Text("确定")))
            }
        }
    }

    // 运行配置
    private var runConfigSection: some View {
        Section("运行配置") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("执行线程数")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text("\(appState.threadCount)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                Stepper("", value: $appState.threadCount, in: 1...16)
                    .labelsHidden()
            }
            .listRowBackground(Color.white.opacity(0.05))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("单应用内存上限")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text("\(appState.memoryLimitMB) MB")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                }
                Stepper("", value: $appState.memoryLimitMB, in: 64...4096, step: 64)
                    .labelsHidden()
            }
            .listRowBackground(Color.white.opacity(0.05))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("日志等级")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Picker("", selection: $appState.logLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.title)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
    }

    // 权限状态：缺失红色高亮
    private var entitlementSection: some View {
        Section("签名权限状态") {
            let report = appState.entitlementReport
            entitlementRow("大地址空间", status: report.largeAddressSpace)
                .listRowBackground(Color.white.opacity(0.05))
            entitlementRow("大内存", status: report.largeMemory)
                .listRowBackground(Color.white.opacity(0.05))

            if !report.fullySatisfied {
                if let tip = report.degradedTipText() {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(tip)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.red.opacity(0.9))
                    }
                    .listRowBackground(Color.red.opacity(0.1))
                }
            }
        }
    }

    // 通用管理
    private var generalSection: some View {
        Section("通用管理") {
            Button(action: {
                _ = try? SDRSandboxCache.shared().clearAllCaches()
                appState.log.info("已清理全局缓存")
                noticeMessage = "已清理全局缓存"
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    Text("清理全局缓存")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .listRowBackground(Color.white.opacity(0.05))
            
            Button(action: {
                let pkgs = SDRSandboxDirectory.shared().installedPackageNames()
                noticeMessage = "已安装沙盒：\(pkgs.joined(separator: "、"))"
            }) {
                HStack {
                    Image(systemName: "folder.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                    Text("沙盒目录管理")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .listRowBackground(Color.white.opacity(0.05))
            
            Button(role: .destructive, action: {
                appState.resetAllApps()
                noticeMessage = "已重置应用列表"
            }) {
                HStack {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 18))
                    Text("重置应用列表")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
    }

    // 赞赏入口
    private var donationSection: some View {
        Section("赞赏") {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 160)
                    Image(systemName: "qrcode")
                        .font(.system(size: 90))
                        .foregroundColor(.white.opacity(0.6))
                }
                Text("自愿支持开发，不解锁任何功能")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
        }
    }

    private func entitlementRow(_ title: String, status: SDREntitlementStatus) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(entitlementText(status))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(status == .present ? .green : .red)
        }
    }

    private func entitlementText(_ status: SDREntitlementStatus) -> String {
        if status == .present { return "已开启" }
        if status == .missing { return "缺失" }
        return "无法检测"
    }
}
