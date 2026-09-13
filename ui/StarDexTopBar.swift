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
                        HStack(spacing: 6) {
                            if statusDot {
                                Circle()
                                    .fill(statusDotColor)
                                    .frame(width: 8, height: 8)
                            }
                            Text(statusText)
                                .font(.footnote)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .overlay(alignment: .trailing) {
                    if let trailingIcon = trailingIcon, let trailingAction = trailingAction {
                        Button(action: trailingAction) {
                            Image(systemName: trailingIcon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color(white: 0.12), in: Circle())
                        }
                        .padding(.trailing, 14)
                    }
                }
            }

            HStack {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color(white: 0.22))
                .frame(height: 0.5)
        }
        .background(Color.black)
    }
}
