/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UniformTypeIdentifiers

// 签名工具页：文件导入 → 信息预览 → 本地签名 → 输出管理与一键导入。
struct SignToolView: View {
    @EnvironmentObject var appState: AppState

    @State private var showImporter = false
    @State private var apkData: Data?
    @State private var apkInfo: SDRApkInfo?
    @State private var hardeningName: String?
    @State private var sigSummary: String?
    @State private var noticeMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    importSection
                    if let info = apkInfo {
                        previewSection(info)
                    }
                    if apkData != nil {
                        signSection
                    }
                    disclaimerSection
                }
                .padding()
            }
            .navigationTitle("签名工具")
            .navigationBarTitleDisplayMode(.large)
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data]) { result in
                handleImport(result)
            }
            .alert(item: Binding<IdentifiableString?>(
                get: { noticeMessage.map(IdentifiableString.init) },
                set: { noticeMessage = $0?.value }
            )) { item in
                Alert(title: Text("提示"), message: Text(item.value), dismissButton: .default(Text("确定")))
            }
        }
    }

    // 文件导入区。
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件导入").font(.headline)
            Button {
                showImporter = true
            } label: {
                Label(apkData == nil ? "选择原始未签名 APK" : "重新选择 APK", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            Text("支持从系统文件选择原始未签名 APK，全程本地处理。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // 信息预览区。
    private func previewSection(_ info: SDRApkInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("信息预览").font(.headline)
            Group {
                infoRow("包名", info.packageName)
                infoRow("版本名", info.versionName)
                infoRow("版本号", "\(info.versionCode)")
                infoRow("加固检测", hardeningName.map { "已加固：\($0)" } ?? "未检测到加固")
                infoRow("权限数量", "\(info.permissions.count)")
                infoRow("签名状态", sigSummary ?? "未校验")
            }
            .font(.subheadline)
        }
    }

    // 签名操作区。
    private var signSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("签名操作").font(.headline)
            Button {
                performSign()
            } label: {
                Label("本地执行签名（无需联网）", systemImage: "signature")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // 免责提示。
    private var disclaimerSection: some View {
        Text("免责声明：不支持脱壳、不支持破解加固包，仅处理合法原始安装包。")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // 安全作用域资源访问：外部文件 URL 需先申请读取权限。
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                noticeMessage = "读取文件失败（无访问权限），请重新选择"
                return
            }
            apkData = data
            hardeningName = SDRHardeningDetector().detect(inRawData: data)

            if let sigResult = try? SDRSignatureVerifier().verifyApkData(data, error: nil) {
                sigSummary = sigResult.summaryMessage
            }
            if let parser = try? SDRApkParser(apkData: data),
               let info = try? parser.parseInfo() {
                apkInfo = info
            } else {
                apkInfo = nil
                noticeMessage = "无法解析 APK 元数据"
            }
        case .failure(let error):
            noticeMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func performSign() {
        guard let data = apkData else { return }
        guard hardeningName == nil else {
            noticeMessage = "该 APK 已加固，不支持签名处理。"
            return
        }
        guard let signedData = try? SDRApkSigner().resignApkData(data, commonName: "StarDex-Run") else {
            noticeMessage = "签名失败"
            return
        }
        // 保存至应用沙盒并提示。
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outURL = dir.appendingPathComponent("StarDex-Run-signed.apk")
        do {
            try signedData.write(to: outURL, options: .atomic)
            appState.log.info("签名完成并保存至沙盒：\(outURL.lastPathComponent)")
            noticeMessage = "签名完成。可通过「导入」运行已签名 APK。"
        } catch {
            noticeMessage = "保存签名结果失败：\(error.localizedDescription)"
        }
    }
}