/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 运行状态页：全屏呈现，显示启动进度或当前应用信息，底部「停止」，关闭按钮在右上。
struct RunStateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let app: InstalledApp

    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.08, green: 0.05, blue: 0.18),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 内容
            VStack(spacing: 32) {
                // 顶部关闭按钮
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                Spacer()
                
                // 应用信息
                VStack(spacing: 24) {
                    // 应用图标
                    Group {
                        if let icon = app.icon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                Image(systemName: "app.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .purple.opacity(0.4), radius: 24, x: 0, y: 16)
                    
                    VStack(spacing: 12) {
                        Text(app.displayTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        
                        Text(app.packageName)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 状态和进度
                VStack(spacing: 20) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(.green)
                            .frame(width: 12, height: 12)
                            .shadow(color: .green, radius: 8, x: 0, y: 0)
                        Text("正在运行")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    
                    if let progress = appState.currentRunProgress, let message = appState.currentRunMessage {
                        VStack(spacing: 12) {
                            ProgressView(value: progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                .scaleEffect(x: 1, y: 2, anchor: .center)
                                .padding(.horizontal, 40)
                            
                            Text(message)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                
                Spacer()
                
                // 停止按钮
                Button(role: .destructive) {
                    appState.stopApp()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("停止运行")
                            .font(.system(.headline, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.red.opacity(0.9), .orange.opacity(0.9)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .red.opacity(0.4), radius: 16, x: 0, y: 8)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .task {
            appState.launchApp(app)
        }
    }
}
