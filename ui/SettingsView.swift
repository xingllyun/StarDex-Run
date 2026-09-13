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

    var body: some View {
        NavigationStack {
            ZStack {
                // 渐变背景
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.08, blue: 0.18),
                        Color(red: 0.02, green: 0.02, blue: 0.08)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        runConfigSection
                        entitlementSection
                        generalSection
                        donationSection
                    }
                    .padding(20)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    StarDexTopBar(title: "设置")
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // 运行配置。
    private var runConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("运行配置", icon: "gearshape.2")
            
            VStack(spacing: 20) {
                // 线程数设置
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("执行线程数")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(appState.threadCount)")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: Binding(
                        get: { Double(appState.threadCount) },
                        set: { appState.threadCount = Int($0) }
                    ), in: 1...16, step: 1)
                    .tint(.blue)
                }
                
                Divider().background(.white.opacity(0.1))
                
                // 内存限制设置
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("单应用内存上限")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(appState.memoryLimitMB) MB")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: Binding(
                        get: { Double(appState.memoryLimitMB) },
                        set: { appState.memoryLimitMB = Int($0) }
                    ), in: 64...4096, step: 64)
                    .tint(.blue)
                }
                
                Divider().background(.white.opacity(0.1))
                
                // 日志等级选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("日志等级")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                    
                    Picker("日志等级", selection: $appState.logLevel) {
                        ForEach(LogLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // 权限状态：缺失红色高亮。
    private var entitlementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("签名权限状态", icon: "lock.shield")
            
            let report = appState.entitlementReport
            
            VStack(spacing: 16) {
                entitlementRow("大地址空间", status: report.largeAddressSpace)
                Divider().background(.white.opacity(0.1))
                entitlementRow("大内存", status: report.largeMemory)
                
                if !report.fullySatisfied {
                    if let tip = report.degradedTipText() {
                        Divider().background(.white.opacity(0.1))
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                            Text(tip)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // 通用管理。
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("通用管理", icon: "wrench.adjustable")
            
            VStack(spacing: 12) {
                settingButton("清理全局缓存", icon: "trash", color: .blue) {
                    _ = try? SDRSandboxCache.shared().clearAllCaches()
                    appState.log.info("已清理全局缓存")
                    appState.noticeMessage = "已清理全局缓存"
                }
                
                settingButton("沙盒目录管理", icon: "folder", color: .purple) {
                    let pkgs = SDRSandboxDirectory.shared().installedPackageNames()
                    appState.noticeMessage = "已安装沙盒：\(pkgs.joined(separator: "、"))"
                }
                
                settingButton("重置应用列表", icon: "arrow.counterclockwise", color: .red, role: .destructive) {
                    appState.resetAllApps()
                    appState.noticeMessage = "已重置应用列表"
                }
            }
        }
    }

    // 赞赏入口。
    private var donationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("支持开发", icon: "heart.fill")
            
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.pink, .purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 8) {
                    Text("支持 StarDex-Run")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                    Text("自愿支持开发，不解锁任何功能")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // 区块标题
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.blue)
            Text(title)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
        }
    }

    // 设置按钮
    private func settingButton(_ title: String, icon: String, color: Color, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func entitlementRow(_ title: String, status: SDREntitlementStatus) -> some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.medium)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(status == .present ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(entitlementText(status))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(status == .present ? .green : .red)
            }
        }
    }

    private func entitlementText(_ status: SDREntitlementStatus) -> String {
        if status == .present { return "已开启" }
        if status == .missing { return "缺失" }
        return "无法检测"
    }
}
