/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UIKit

// 全新设计的日志页
struct LogView: View {
    @EnvironmentObject var appState: AppState

    @State private var packageFilter = ""
    @State private var keywordFilter = ""
    @State private var levelFilter: LogLevel? = nil
    @State private var exportURL: ExportURLBox?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                logList
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .safeAreaInset(edge: .top, spacing: 0) {
                StarDexTopBar(title: "运行日志",
                              trailingIcon: "square.and.arrow.up",
                              trailingAction: { exportLog() })
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(item: $exportURL) { box in
                ShareSheet(items: [box.url])
            }
        }
    }

    private var filteredEntries: [LogEntry] {
        appState.log.entries.filter { entry in
            let passLevel = (levelFilter == nil) || (entry.level == levelFilter)
            let passPackage = packageFilter.isEmpty || entry.package.contains(packageFilter)
            let passKeyword = keywordFilter.isEmpty || entry.message.contains(keywordFilter)
            return passLevel && passPackage && passKeyword
        }
    }

    private var filterBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))
                    TextField("关键词", text: $keywordFilter)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                
                HStack {
                    Image(systemName: "cube.box.fill")
                        .foregroundColor(.white.opacity(0.5))
                    TextField("包名", text: $packageFilter)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
            }
            
            Picker("等级", selection: $levelFilter) {
                Text("全部").tag(LogLevel?.none)
                ForEach(LogLevel.allCases) { level in
                    Text(level.title).tag(LogLevel?.some(level))
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(red: 0.03, green: 0.03, blue: 0.05).opacity(0.95))
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.05))
            .onChange(of: filteredEntries.count) { _ in
                if let last = filteredEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func entryRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(timeString(entry.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("[模块]")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                Text(entry.module)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.cyan)
                
                Text("[包名]")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.mint.opacity(0.8))
                Text(entry.package)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.mint)
            }
            
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color(for: entry.level))
                .lineLimit(nil)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .white.opacity(0.5)
        case .info:  return .white
        case .warn:  return .yellow
        case .error: return .red.opacity(0.9)
        case .fatal: return .orange
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    private func exportLog() {
        let text = appState.exportLogText()
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("StarDex-Run-log.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            appState.log.info("日志已导出：\(url.lastPathComponent)")
            exportURL = ExportURLBox(url: url)
        } catch {
            appState.log.error("日志导出失败：\(error.localizedDescription)")
        }
    }
}

// 供 sheet 使用的文件 URL 包装。
struct ExportURLBox: Identifiable {
    let id = UUID()
    let url: URL
}

// 系统分享面板（UIActivityViewController 的 SwiftUI 包装）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
