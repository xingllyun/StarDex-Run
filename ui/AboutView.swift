/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 全新设计的关于页
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
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.white.opacity(0.05))
                                    .frame(width: 120, height: 120)
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 60, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(spacing: 6) {
                                Text("StarDex-Run")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("版本 \(appVersion)")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                    }

                    Section("协议与版权") {
                        labelRow("开源协议", "MIT License")
                        labelRow("版权所有", "星云云络科技")
                    }

                    Section("支持系统") {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)
                            Text("iOS 16 ~ 19")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                        
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)
                            Text("iOS 26 ~ 27")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                        
                        HStack {
                            Text("当前系统")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(appState.versionAdapter.systemDescription())
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }

                    Section("已知限制") {
                        limitation("不支持加固后的 APK（不脱壳、不破解）")
                        limitation("纯解释执行，无 JIT / AOT 编译")
                        limitation("仅兼容简单无依赖原生 SO 库")
                        limitation("安卓 API 按需映射，非全量复刻")
                    }

                    Section("部署要求") {
                        HStack(spacing: 10) {
                            Image(systemName: "shield.lefthalf.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange.opacity(0.8))
                            Text("侧载签名证书需开启「大地址空间」「大内存」两项权限。")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
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
            Text(key)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private func limitation(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange.opacity(0.8))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .listRowBackground(Color.white.opacity(0.05))
    }
}
