/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UniformTypeIdentifiers

// 主界面：顶部导航 + 应用列表卡片 + 底部快捷操作。
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
            .navigationTitle("StarDex-Run")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    statusBar
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入", systemImage: "plus")
                    }
                }
            }
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无已导入应用")
                .font(.headline)
            Text("点击右上角「导入」选择 APK 文件")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("导入 APK") { showImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(appState.isRunning ? "运行中" : "空闲")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var appList: some View {
        List {
            ForEach(appState.installedApps) { app in
                AppCard(app: app)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedApp = app }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            appState.delete(app)
                        } label: { Label("删除", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
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

// 应用卡片：图标 + 包名 + 版本号。
struct AppCard: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 14) {
            if let icon = app.icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "app.fill").foregroundColor(.secondary))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayTitle).font(.headline).lineLimit(1)
                Text(app.packageName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Text("版本 \(app.versionName)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// 应用详情：完整元信息与操作入口。
struct AppDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    let app: InstalledApp

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        if let icon = app.icon {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 64, height: 64)
                                .overlay(Image(systemName: "app.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.displayTitle).font(.title3).bold().lineLimit(1)
                            Text(app.packageName).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("基本信息") {
                    row("应用名称", app.displayTitle)
                    row("包名", app.packageName)
                    row("版本名", app.versionName)
                    row("版本号", "\(app.versionCode)")
                    row("签名", app.signatureSummary)
                }
                Section("内容") {
                    row("文件大小", app.formattedSize)
                    row("权限数量", "\(app.permissionCount)")
                    row("DEX 文件", "\(app.dexCount)")
                    row("Activity", "\(app.activityCount)")
                    row("最低系统", androidVersionLabel(api: app.info.minSdkVersion))
                    row("目标系统", androidVersionLabel(api: app.info.targetSdkVersion))
                }
                Section {
                    Button("启动") {
                        appState.launch(app)
                    }
                    .disabled(appState.isRunning)
                    Button("导出运行日志") {
                        appState.log.info("导出日志（\(app.packageName)）共 \(appState.log.entries.count) 条", package: app.packageName)
                    }
                    Button("删除", role: .destructive) {
                        appState.delete(app)
                        dismiss()
                    }
                }
            }
            .navigationTitle(app.displayTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

// 供 Alert 使用的可识别字符串包装。
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// API 等级 → Android 版本名映射（API 0 表示 Manifest 未声明/未解析）。
func androidVersionLabel(api: UInt32) -> String {
    let name: String
    switch api {
    case 0: name = "未知"
    case 1: name = "1.0"
    case 2: name = "1.1"
    case 3: name = "1.5"
    case 4: name = "1.6"
    case 5...8: name = "2.0–2.2"
    case 9: name = "2.3"
    case 10: name = "2.3.3"
    case 11...13: name = "3.x"
    case 14: name = "4.0"
    case 15: name = "4.0.3"
    case 16: name = "4.1"
    case 17: name = "4.2"
    case 18: name = "4.3"
    case 19: name = "4.4"
    case 20: name = "4.4W"
    case 21: name = "5.0"
    case 22: name = "5.1"
    case 23: name = "6.0"
    case 24: name = "7.0"
    case 25: name = "7.1"
    case 26: name = "8.0"
    case 27: name = "8.1"
    case 28: name = "9"
    case 29: name = "10"
    case 30: name = "11"
    case 31: name = "12"
    case 32: name = "12L"
    case 33: name = "13"
    case 34: name = "14"
    case 35: name = "15"
    case 36: name = "16"
    default: name = "API \(api)"
    }
    return api == 0 ? "未知" : "Android \(name) (API \(api))"
}