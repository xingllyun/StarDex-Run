/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 关于页：版本号、开源协议、版权、支持系统、已知限制。
struct AboutView: View {
    @EnvironmentObject var appState: AppState

    // 从 Info.plist 读取真实版本号（CFBundleShortVersionString），避免硬编码过期。
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short = short, !short.isEmpty {
            if let build = build, !build.isEmpty, build != short {
                return "\(short) (\(build))"
            }
            return short
        }
        return "未知"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)
                        Text("StarDex-Run")
                            .font(.title2.bold())
                        Text("版本 \(appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section("协议与版权") {
                    labelRow("开源协议", "MIT License")
                    labelRow("版权所有", "星云云络科技")
                }

                Section("支持系统") {
                    Label("iOS 16 ~ 19", systemImage: "checkmark.circle")
                    Label("iOS 26 ~ 27", systemImage: "checkmark.circle")
                    Text("当前系统：\(appState.versionAdapter.systemDescription())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("已知限制") {
                    limitation("不支持加固后的 APK（不脱壳、不破解）")
                    limitation("纯解释执行，无 JIT / AOT 编译")
                    limitation("仅兼容简单无依赖原生 SO 库")
                    limitation("安卓 API 按需映射，非全量复刻")
                }

                Section("部署要求") {
                    Text("侧载签名证书需开启「大地址空间」「大内存」两项权限。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StarDexTopBar(title: "关于")
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    private func labelRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func limitation(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
}