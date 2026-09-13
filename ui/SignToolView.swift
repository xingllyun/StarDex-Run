/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UniformTypeIdentifiers

// 签名工具页：导入未签名APK → 进度条 → 完成，可直接安装。
struct SignToolView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImporter = false
    @State private var signing = false
    @State private var progress: Double = 0
    @State private var progressText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.06, green: 0.06, blue: 0.16),
                        Color(red: 0.01, green: 0.01, blue: 0.06)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    if signing {
                        signingState
                    } else {
                        idleState
                    }
                    
                    Spacer()
                }
                .padding(24)
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data]) { r in
                    handleInput(r)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    StarDexTopBar(title: "签名工具")
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // 空闲状态。
    private var idleState: some View {
        VStack(spacing: 28) {
            // 图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "signature")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.white)
                    .shadow(color: .blue.opacity(0.5), radius: 16, x: 0, y: 8)
            }
            
            VStack(spacing: 12) {
                Text("APK 签名工具")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("为未签名 APK 补签后可直接导入使用")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                    Text("选择未签名 APK")
                        .font(.system(.headline, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .blue.opacity(0.4), radius: 12, x: 0, y: 6)
            }
        }
    }

    // 签名中状态。
    private var signingState: some View {
        VStack(spacing: 28) {
            // 进度动画
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 140, height: 140)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.green, .blue]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }
            
            VStack(spacing: 12) {
                Text("正在签名…")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.semibold)
                Text(progressText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func handleInput(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            appState.noticeMessage = "文件选择失败"
            return
        }
        signing = true
        progress = 0
        progressText = "准备中"

        let impl = SDRSignerImpl()
        impl.signApk(url, withFeedback: { p, msg in
            DispatchQueue.main.async {
                self.progress = p
                self.progressText = msg ?? "处理中"
            }
        }) { outUrl, err in
            DispatchQueue.main.async {
                signing = false
                progress = 0
                progressText = ""

                if let outUrl = outUrl {
                    switch appState.importApk(at: outUrl) {
                    case .success:
                        appState.noticeMessage = "签名成功，已导入应用"
                    case .unsigned:
                        appState.noticeMessage = "签名结果无效，请重试"
                    case .hardened(let n):
                        appState.noticeMessage = "检测到加固（\(n)），请使用无加固安装包"
                    case .invalid(let r):
                        appState.noticeMessage = "导入失败：\(r)"
                    }
                } else {
                    appState.noticeMessage = "签名失败：\(err?.localizedDescription ?? "未知")"
                }
            }
        }
    }
}
