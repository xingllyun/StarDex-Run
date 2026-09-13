/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UniformTypeIdentifiers

// 主视图：已安装应用列表（网格布局）、长按编辑模式、右上角「+」导入 APK。
struct MainView: View {
    @EnvironmentObject var appState: AppState

    @State private var showImporter = false
    @State private var editing = false
    @State private var selectedToDelete: Set<UUID> = []
    @State private var showRunStateSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 星空背景
                StarFieldBackground()
                
                VStack(spacing: 0) {
                    // 自定义顶栏
                    StarDexTopBar(
                        title: "应用",
                        statusText: appState.isRunning ? "运行中：\(appState.runningPackageName ?? "未知")" : (appState.installedApps.isEmpty ? "未安装应用" : "已安装 \(appState.installedApps.count) 个应用"),
                        statusDot: appState.isRunning,
                        statusDotColor: .green,
                        trailingIcon: "plus",
                        trailingAction: { showImporter = true }
                    )
                    
                    if appState.installedApps.isEmpty {
                        emptyState
                    } else {
                        appGrid
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data]) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showRunStateSheet) {
                if let app = appState.runningApp {
                    RunStateView(app: app)
                }
            }
            .onChange(of: appState.runningApp) { newValue in
                showRunStateSheet = newValue != nil
            }
        }
    }

    // 空状态：引导导入。
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.dashed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("还没有安装应用")
                .font(.headline)
            Text("点击右上角「+」导入 APK，或使用「签名工具」为未签名包签名")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 应用网格。
    private var appGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                ForEach(appState.installedApps) { app in
                    appCard(app)
                }
            }
            .padding()
        }
    }

    // 单个应用卡片。
    private func appCard(_ app: InstalledApp) -> some View {
        VStack(spacing: 8) {
            // 图标
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
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            // 标题与包名
            VStack(spacing: 2) {
                Text(app.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(app.packageName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .onTapGesture {
            if editing {
                if selectedToDelete.contains(app.id) {
                    selectedToDelete.remove(app.id)
                } else {
                    selectedToDelete.insert(app.id)
                }
            } else {
                launchApp(app)
            }
        }
        .onLongPressGesture {
            if !editing {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    editing = true
                }
            }
        }
        .overlay(
            editing ?
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selectedToDelete.contains(app.id) ? Color.red : Color.blue, lineWidth: 3)
            : nil
        )
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let outcome = appState.importApk(at: url)
            switch outcome {
            case .success:
                break
            case .hardened(let name):
                appState.noticeMessage = "检测到加固（\(name)），暂不支持，请使用原始未加固安装包。"
            case .unsigned:
                appState.noticeMessage = "该 APK 未签名或签名失效，请先使用「签名工具」处理。"
            case .invalid(let reason):
                appState.noticeMessage = "导入失败：\(reason)"
            }
        case .failure(let error):
            appState.noticeMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func launchApp(_ app: InstalledApp) {
        appState.launchApp(app)
    }
}

// 星空背景动画
struct StarFieldBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // 深空背景
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.0, green: 0.0, blue: 0.05)
                ]),
                center: .topLeading,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()
            
            // 星星
            ForEach(0..<50, id: \.self) { index in
                let x = CGFloat.random(in: -100...400)
                let y = CGFloat.random(in: -100...800)
                let size = CGFloat.random(in: 1...3)
                let opacity = Double.random(in: 0.3...0.8)
                let scale = animate ? CGFloat.random(in: 1.0...1.5) : CGFloat.random(in: 0.5...1.0)
                
                Circle()
                    .fill(Color.white.opacity(opacity))
                    .frame(width: size, height: size)
                    .position(x: x, y: y)
                    .scaleEffect(scale)
                    .opacity(animate ? 0.5 : 1.0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
