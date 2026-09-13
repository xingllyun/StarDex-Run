/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 通用自定义顶栏：不依赖系统导航栏（iOS 16~27 渲染一致）。
// 结构：第一行（可选）运行状态居中 + 右上操作按钮；第二行大标题；第三行分隔线。
struct StarDexTopBar: View {
    let title: String
    var statusText: String? = nil          // 状态行中央文字（如 空闲 / 运行中）
    var statusDot: Bool = false            // 是否显示状态圆点
    var statusDotColor: Color = .gray
    var trailingIcon: String? = nil        // 右上操作图标（SF Symbol）
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if statusText != nil || trailingIcon != nil {
                ZStack {
                    if let statusText = statusText {
                        HStack(spacing: 8) {
                            if statusDot {
                                Circle()
                                    .fill(statusDotColor)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: statusDotColor, radius: 4, x: 0, y: 0)
                            }
                            Text(statusText)
                                .font(.system(.footnote, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .overlay(alignment: .trailing) {
                    if let trailingIcon = trailingIcon, let trailingAction = trailingAction {
                        Button(action: trailingAction) {
                            Image(systemName: trailingIcon)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: .blue.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .padding(.trailing, 16)
                    }
                }
            }

            HStack {
                Text(title)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // 渐变分隔线
            LinearGradient(
                gradient: Gradient(colors: [.clear, .white.opacity(0.2), .clear]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .background(.ultraThinMaterial.opacity(0.8))
    }
}
