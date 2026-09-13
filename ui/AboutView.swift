/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 关于页：版权、免责声明。
struct AboutView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.02, green: 0.02, blue: 0.08)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        appIconAndInfo
                        disclaimerSection
                        copyrightSection
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    StarDexTopBar(title: "关于")
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // 应用图标和信息
    private var appIconAndInfo: some View {
        VStack(spacing: 20) {
            // 应用图标
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple, .pink]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .shadow(color: .purple.opacity(0.4), radius: 20, x: 0, y: 12)
                
                Image(systemName: "app.gift.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("StarDex-Run")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("iOS 侧载 APK 运行时")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.secondary)
                
                Text("v\(SDRVersion.current.description)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.tertiary)
            }
        }
        .padding(.vertical, 20)
    }

    // 免责声明
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("免责声明", icon: "exclamationmark.shield")
            
            VStack(alignment: .leading, spacing: 12) {
                Text("本项目仅供学习与研究使用。使用时请遵守当地法律法规，不得用于任何非法用途。")
                
                Text("我们不对因使用本工具产生的任何直接或间接损失负责。")
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundColor(.secondary)
            .padding(20)
            .background(.ultraThinMaterial.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // 版权信息
    private var copyrightSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("版权信息", icon: "c.circle")
            
            VStack(alignment: .leading, spacing: 12) {
                Text("© \(Calendar.current.component(.year, from: Date())) 星云云络科技")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("MIT License")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.blue)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.8))
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
                .foregroundColor(.orange)
            Text(title)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
        }
    }
}
