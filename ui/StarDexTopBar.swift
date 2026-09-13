/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 全新设计的自定义顶栏：保持接口不变，视觉风格全面升级
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
                                    .shadow(color: statusDotColor.opacity(0.7), radius: 6, x: 0, y: 0)
                            }
                            Text(statusText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .overlay(alignment: .trailing) {
                    if let trailingIcon = trailingIcon, let trailingAction = trailingAction {
                        Button(action: trailingAction) {
                            Image(systemName: trailingIcon)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
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
                                .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 16)
                    }
                }
            }

            HStack {
                Text(title)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 4)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.2), Color.clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.06, green: 0.06, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.08)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
