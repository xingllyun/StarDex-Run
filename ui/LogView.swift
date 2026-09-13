/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

// 日志页：按等级过滤，支持滚动浏览，一键分享。
struct LogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(red: 0.02, green: 0.02, blue: 0.08)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    logList
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    StarDexTopBar(
                        title: "日志",
                        statusText: "\(appState.log.entries.count) 条",
                        statusDot: true,
                        statusDotColor: .blue,
                        trailingIcon: "square.and.arrow.up",
                        trailingAction: {
                            let text = appState.log.entries.map(\.text).joined(separator: "\n")
                            let shareUrl = SDRLogWriter.shared().saveTemporary(with: text)
                            if let shareUrl = shareUrl {
                                // 在实际场景中，这里会弹出分享 Sheet
                                print("分享 URL: \(shareUrl)")
                            }
                        }
                    )
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    // 日志列表
    private var logList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(appState.log.entries.filter { $0.level.rawValue <= appState.logLevel.rawValue }) { entry in
                    LogRow(entry: entry)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .id(entry.id)
                }
            }
            .listStyle(.plain)
            .onChange(of: appState.log.entries.count) { _ in
                if let last = appState.log.entries.last {
                    withAnimation(.spring(response: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// 日志行
struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                LevelBadge(level: entry.level)
                
                Text(entry.timestamp.formatted(.dateTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text(entry.message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.primary)
                .lineSpacing(4)
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// 等级徽章
struct LevelBadge: View {
    let level: LogLevel

    var body: some View {
        Text(level.title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bgColor)
            .clipShape(Capsule())
    }

    var bgColor: Color {
        switch level {
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}
