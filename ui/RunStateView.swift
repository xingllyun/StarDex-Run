/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 全新设计的应用运行状态页
struct RunStateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    // 正常推进阶段（不含 failed，failed 单独作为错误态处理）。
    private let stages: [RunStage] = [.verifyFile, .parseDex, .createVM, .loadClass, .findEntry, .startActivity, .running]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            headerSection
                            progressSection
                            stageList
                            recentLogSection
                        }
                        .padding()
                    }
                    bottomBar
                }
            }
            .navigationTitle("应用运行状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("关闭")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.blue)
                    }
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
        HStack(spacing: 16) {
            if let icon = app.icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(16)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "app.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(app.displayTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(app.packageName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Text(currentStageTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(appState.runStage == .failed ? .red.opacity(0.9) : .blue)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
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

    // 进度条区域。
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("启动进度")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 10)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(appState.runStage == .failed ? Color.red.opacity(0.9) : Color.blue)
                            .frame(width: max(0, geometry.size.width * progressValue), height: 10)
                    }
                }
                .frame(height: 10)
                
                HStack {
                    Text("\(Int(progressValue * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    if appState.runStage == .failed {
                        Text("失败")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.red.opacity(0.9))
                    } else if appState.isRunning {
                        Text("进行中…")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.blue)
                    } else {
                        Text("完成")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.green.opacity(0.9))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
            )
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
        VStack(alignment: .leading, spacing: 12) {
            Text("启动阶段")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(stages, id: \.self) { stage in
                    stageRow(stage)
                }
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

        return HStack(spacing: 14) {
            // 状态图标
            Group {
                if isDone || (appState.runStage == .running && stage != .running) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .frame(width: 24, height: 24)
                } else if isCurrent {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                    .frame(width: 24, height: 24)
                } else if isFailedStage {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.red.opacity(0.9))
                    }
                    .frame(width: 24, height: 24)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                        Image(systemName: "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .frame(width: 24, height: 24)
                }
            }

            Text("\(stageIndexText(stageIdx)). \(stage.title)")
                .font(.system(size: 15, weight: isCurrent ? .semibold : .medium, design: .rounded))
                .foregroundColor(isCurrent ? .white : (isDone ? .green.opacity(0.8) : (isFailedStage ? .red.opacity(0.9) : .white.opacity(0.4))))

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Color.blue.opacity(0.1) : (isFailedStage ? Color.red.opacity(0.1) : Color.white.opacity(0.03)))
        )
    }

    private func stageIndexText(_ idx: Int) -> String {
        String(format: "%02d", idx + 1)
    }

    // 最近日志（按当前运行包过滤）。
    private var recentLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近日志")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            
            let logs = appState.log.entries.filter { $0.package == app.packageName }.suffix(20)
            if logs.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.2))
                    Text("暂无日志")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.03))
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(logs)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(shortTime(entry.timestamp))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(color(for: entry.level))
                                .lineLimit(2)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.03))
                        )
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
                HStack(spacing: 8) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("停止运行")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.15))
            )
            .foregroundColor(.red.opacity(0.9))

            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("查看实时日志")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.15))
            )
            .foregroundColor(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .background(
            Color(red: 0.05, green: 0.05, blue: 0.1)
                .opacity(0.95)
        )
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .white.opacity(0.4)
        case .info:  return .white
        case .warn:  return .yellow
        case .error: return .red.opacity(0.9)
        case .fatal: return .orange
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}
