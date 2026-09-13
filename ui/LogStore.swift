/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import Foundation
import Combine
import Darwin

// 日志等级：五级分级（DEBUG / INFO / WARN / ERROR / FATAL）。
// 顺序从低到高，用于阈值过滤。
enum LogLevel: Int, CaseIterable, Identifiable {
    case debug = 0
    case info
    case warn
    case error
    case fatal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .debug: return "Debug"
        case .info:  return "Info"
        case .warn:  return "Warn"
        case .error: return "Error"
        case .fatal: return "Fatal"
        }
    }
}

// 单条日志：毫秒级时间戳 + 线程 ID + 模块标签 + 包名 + 消息。
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let module: String    // 模块标签（ui / apk-tool / dex-core / framework / native-loader / sandbox / ios-adapter）
    let thread: Int       // 产生日志的线程 ID（mach thread）
    let package: String   // 关联应用包名（无关联时用 "system"）
    let message: String
}

// 全局日志存储：实时滚动输出 + 磁盘持久化（双输出），分片滚动，支持筛选与导出。
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 2000            // 内存滚动上限（分片，防大日志量阻塞主线程）
    private let fileURL: URL?                // 磁盘持久化日志文件
    private let fileQueue = DispatchQueue(label: "sd.log.file", qos: .utility)

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("StarDex-Run-runtime.log")
        // 首次启动清空旧日志文件，避免无限追加膨胀。
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 主入口

    func log(_ message: String,
             level: LogLevel = .info,
             module: String = "system",
             package: String = "system") {
        let entry = LogEntry(timestamp: Date(),
                             level: level,
                             module: module,
                             thread: Int(pthread_mach_thread_np(pthread_self())),
                             package: package,
                             message: message)
        // 屏幕输出：切主线程驱动 UI 滚动。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        // 磁盘输出：后台串行队列追加写盘，双输出不阻塞 UI。
        fileQueue.async { [weak self] in
            guard let self = self, let url = self.fileURL else { return }
            let line = self.format(entry) + "\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - 分级便捷方法

    func debug(_ message: String, module: String = "system", package: String = "system") { log(message, level: .debug, module: module, package: package) }
    func info(_ message: String, module: String = "system", package: String = "system") { log(message, level: .info, module: module, package: package) }
    func warn(_ message: String, module: String = "system", package: String = "system") { log(message, level: .warn, module: module, package: package) }
    func error(_ message: String, module: String = "system", package: String = "system") { log(message, level: .error, module: module, package: package) }
    func fatal(_ message: String, module: String = "system", package: String = "system") { log(message, level: .fatal, module: module, package: package) }

    // MARK: - 格式化与导出

    // 格式化单条日志为统一文本行。
    func format(_ entry: LogEntry) -> String {
        let ts = Self.timestampFormatter.string(from: entry.timestamp)
        return "\(ts) [\(entry.level.title.uppercased())] [TID:\(entry.thread)] [\(entry.module)] [\(entry.package)] \(entry.message)"
    }

    // 导出当前内存日志为纯文本（磁盘持久化文件与内存内容可能略有差异，此处导出内存快照）。
    func exportText() -> String {
        return entries.map { format($0) }.joined(separator: "\n")
    }

    // 磁盘持久化日志文件路径（供「导出完整日志」使用）。
    var logFilePath: String? { fileURL?.path }

    // 清空内存滚动日志。
    func clearEntries() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    // 时间戳格式化器（毫秒级）。
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}