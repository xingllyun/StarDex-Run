/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import Foundation
import Combine

// 日志等级。
enum LogLevel: Int, CaseIterable, Identifiable {
    case info = 0
    case warn
    case error

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .info: return "Info"
        case .warn: return "Warn"
        case .error: return "Error"
        }
    }
}

// 单条日志。
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let package: String
    let message: String
}

// 全局日志存储：实时滚动输出，按等级区分颜色，支持筛选与导出。
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 2000

    func log(_ message: String, level: LogLevel = .info, package: String = "system") {
        let entry = LogEntry(timestamp: Date(), level: level, package: package, message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func info(_ message: String, package: String = "system") { log(message, level: .info, package: package) }
    func warn(_ message: String, package: String = "system") { log(message, level: .warn, package: package) }
    func error(_ message: String, package: String = "system") { log(message, level: .error, package: package) }

    // 导出完整日志为纯文本。
    func exportText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { entry in
            "\(formatter.string(from: entry.timestamp)) [\(entry.level.title.uppercased())] [\(entry.package)] \(entry.message)"
        }.joined(separator: "\n")
    }
}