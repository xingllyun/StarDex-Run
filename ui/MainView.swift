/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UniformTypeIdentifiers

// 主界面：全新的视觉风格设计
struct MainView: View {
    @EnvironmentObject var appState: AppState

    @State private var showImporter = false
    @State private var alertMessage: String?
    @State private var selectedApp: InstalledApp?

    var body: some View {
        NavigationStack {
            Group {
                if appState.installedApps.isEmpty {
                    emptyState
                } else {
                    appList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StarDexTopBar(
                    title: "StarDex-Run",
                    statusText: appState.isRunning ? "运行中" : "空闲",
                    statusDot: true,
                    statusDotColor: appState.isRunning ? .green : .gray,
                    trailingIcon: "plus",
                    trailingAction: { showImporter = true }
                )
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data]) { result in
                handleImport(result)
            }
            .alert(item: Binding<IdentifiableString?>(
                get: { alertMessage.map(IdentifiableString.init) },
                set: { alertMessage = $0?.value }
            )) { item in
                Alert(title: Text("提示"), message: Text(item.value), dismissButton: .default(Text("确定")))
            }
            .sheet(item: $selectedApp) { app in
                AppDetailView(app: app)
            }
            .sheet(item: $appState.runningApp) { app in
                RunStateView(app: app)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 120, height: 120)
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                VStack(spacing: 8) {
                    Text("暂无已导入应用")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("点击右上角「+」选择 APK 文件")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Button(action: { showImporter = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text("导入 APK")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 4)
                }
            }
        }
    }

    private var appList: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(appState.installedApps) { app in
                        AppCard(app: app)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedApp = app }
                            .contextMenu {
                                Button(role: .destructive) {
                                    appState.delete(app)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let outcome = appState.importApk(at: url)
            switch outcome {
            case .success:
                break
            case .hardened(let name):
                alertMessage = "不支持加固后的 APK（检测到：\(name)），请获取原始未加固安装包。"
            case .unsigned:
                alertMessage = "该 APK 未签名或签名失效，请先前往「签名」工具进行签名处理。"
            case .invalid(let reason):
                alertMessage = "导入失败：\(reason)"
            }
        case .failure(let error):
            alertMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }
}

// 应用卡片：全新的网格卡片样式设计
struct AppCard: View {
    let app: InstalledApp

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 100)
                
                if let icon = app.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(14)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.8))
                        )
                }
            }
            
            VStack(spacing: 4) {
                Text(app.displayTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(app.packageName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Text("版本 \(app.versionName)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// 应用详情：全新的设计风格
struct AppDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    let app: InstalledApp

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
                        HStack(spacing: 16) {
                            if let icon = app.icon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 72, height: 72)
                                    .cornerRadius(16)
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        Image(systemName: "app.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(.white.opacity(0.8))
                                    )
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(app.displayTitle)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text(app.packageName)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("版本 \(app.versionName) (v\(app.versionCode))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    Section("基本信息") {
                        LabeledContent("文件大小", value: app.formattedSize)
                            .listRowBackground(Color.white.opacity(0.05))
                        LabeledContent("包名", value: app.packageName)
                            .listRowBackground(Color.white.opacity(0.05))
                        LabeledContent("版本", value: "\(app.versionName) (v\(app.versionCode))")
                            .listRowBackground(Color.white.opacity(0.05))
                        LabeledContent("DEX 数量", value: "\(app.dexCount)")
                            .listRowBackground(Color.white.opacity(0.05))
                        LabeledContent("Activity 数量", value: "\(app.activityCount)")
                            .listRowBackground(Color.white.opacity(0.05))
                        LabeledContent("权限数量", value: "\(app.permissionCount)")
                            .listRowBackground(Color.white.opacity(0.05))
                        LabeledContent("签名信息", value: app.signatureSummary)
                            .listRowBackground(Color.white.opacity(0.05))
                    }

                    Section {
                        Button {
                            appState.launch(app)
                        } label: {
                            HStack {
                                Spacer()
                                Label("启动应用", systemImage: "play.fill")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Spacer()
                            }
                        }
                        .listRowBackground(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green.opacity(0.7), Color.green]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .tint(.white)

                        Button(role: .destructive) {
                            appState.delete(app)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("删除应用", systemImage: "trash.fill")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(app.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// 供 Alert 使用的可识别字符串包装（MainView / SettingsView / SignToolView 共用）。
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}
