/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UIKit

// 日志页：实时滚动、按等级着色、按包名/等级/关键词筛选、一键导出。
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
            .background(Color.black)
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { exportLog() } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }
            }
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
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("关键词", text: $keywordFilter)
                    .textFieldStyle(.roundedBorder)
                TextField("包名", text: $packageFilter)
                    .textFieldStyle(.roundedBorder)
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
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.9))
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .background(Color.black)
            .onChange(of: filteredEntries.count) { _ in
                if let last = filteredEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func entryRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeString(entry.timestamp))
                .foregroundColor(.gray)
            Text("[\(entry.module)]")
                .foregroundColor(.cyan)
            Text("[\(entry.package)]")
                .foregroundColor(.mint)
            Text(entry.message)
                .foregroundColor(color(for: entry.level))
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
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