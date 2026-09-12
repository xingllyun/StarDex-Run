/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 应用运行状态页：实时展示启动链路各阶段进度，解决「点击启动无反应、卡死」问题。
// 阶段顺序：校验文件 → 解析 DEX → 创建虚拟机 → 加载类与资源 → 查找入口 → 启动 Activity → 运行中。
struct RunStateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    // 正常推进阶段（不含 failed，failed 单独作为错误态处理）。
    private let stages: [RunStage] = [.verifyFile, .parseDex, .createVM, .loadClass, .findEntry, .startActivity, .running]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection
                        progressBar
                        stageList
                        recentLogSection
                    }
                    .padding()
                }
                bottomBar
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("应用运行状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("启动失败", isPresented: Binding<Bool>(
                get: { appState.launchError != nil },
                set: { if !$0 { appState.launchError = nil } }
            )) {
                Button("确定", role: .cancel) { appState.launchError = nil }
            } message: {
                Text(appState.launchError ?? "")
            }
            .onAppear {
                appState.log.info("打开运行状态页（\(app.packageName)）", module: "ui", package: app.packageName)
            }
        }
        .preferredColorScheme(.dark)
    }

    // 头部：应用信息 + 当前阶段。
    private var headerSection: some View {
        HStack(spacing: 14) {
            if let icon = app.icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color(white: 0.2))
                    .frame(width: 52, height: 52)
                    .cornerRadius(8)
                    .overlay(Image(systemName: "app.fill").foregroundColor(.secondary))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayTitle).font(.headline).foregroundColor(.white).lineLimit(1)
                Text(app.packageName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Text(currentStageTitle)
                    .font(.subheadline)
                    .foregroundColor(appState.runStage == .failed ? .red : .blue)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    // 当前阶段标题。
    private var currentStageTitle: String {
        if appState.runStage == .failed {
            return "启动失败"
        }
        if appState.isRunning {
            return "正在「\(appState.runStage.title)」"
        }
        return "已「\(appState.runStage.title)」"
    }

    // 线性进度条。
    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progressValue)
                .progressViewStyle(.linear)
                .tint(appState.runStage == .failed ? .red : .blue)
            HStack {
                Text("\(Int(progressValue * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if appState.runStage == .failed {
                    Text("失败").font(.caption).foregroundColor(.red)
                } else if appState.isRunning {
                    Text("进行中…").font(.caption).foregroundColor(.blue)
                } else {
                    Text("完成").font(.caption).foregroundColor(.green)
                }
            }
        }
    }

    // 进度值（0.0 ~ 1.0）。
    private var progressValue: Double {
        if appState.runStage == .failed { return 1.0 }
        let idx = stages.firstIndex(of: appState.runStage) ?? 0
        return Double(idx) / Double(max(stages.count - 1, 1))
    }

    // 阶段列表。
    private var stageList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stages, id: \.self) { stage in
                stageRow(stage)
            }
        }
    }

    private func stageRow(_ stage: RunStage) -> some View {
        let stageIdx = stages.firstIndex(of: stage)!
        // 失败态：定位到失败前最后到达的阶段（卡点），其前视为已完成、卡点标红。
        let failedIdx: Int? = appState.runStage == .failed
            ? stages.firstIndex(of: appState.lastProgressStage)
            : nil
        let currentIdx = stages.firstIndex(of: appState.runStage)
        let isDone: Bool
        if let failedIdx = failedIdx {
            isDone = stageIdx < failedIdx
        } else {
            isDone = currentIdx.map { stageIdx < $0 } ?? false
        }
        let isCurrent = stage == appState.runStage && appState.runStage != .failed
        let isFailedStage = appState.runStage == .failed && stageIdx == failedIdx

        return HStack(spacing: 12) {
            // 状态图标
            Group {
                if isDone || (appState.runStage == .running && stage != .running) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else if isCurrent {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.7)
                } else if isFailedStage {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                } else {
                    Image(systemName: "circle").foregroundColor(Color(white: 0.35))
                }
            }
            .frame(width: 20, height: 20)

            Text("\(stageIndexText(stageIdx)). \(stage.title)")
                .font(.subheadline)
                .foregroundColor(isCurrent ? .white : (isDone ? .green.opacity(0.8) : (isFailedStage ? .red : .secondary)))

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func stageIndexText(_ idx: Int) -> String {
        String(format: "%02d", idx + 1)
    }

    // 最近日志（按当前运行包过滤）。
    private var recentLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近日志").font(.headline).foregroundColor(.white)
            let logs = appState.log.entries.filter { $0.package == app.packageName }.suffix(20)
            if logs.isEmpty {
                Text("暂无日志").font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(logs)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(shortTime(entry.timestamp)).foregroundColor(.gray)
                            Text(entry.message)
                                .foregroundColor(color(for: entry.level))
                                .lineLimit(2)
                        }
                        .font(.system(.caption2, design: .monospaced))
                    }
                }
            }
        }
    }

    // 底部操作栏。
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.stopRun()
                dismiss()
            } label: {
                Label("停止运行", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button {
                dismiss()
            } label: {
                Label("查看实时日志", systemImage: "terminal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.9))
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info:  return .white
        case .warn:  return .yellow
        case .error: return .red
        case .fatal: return .orange
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}