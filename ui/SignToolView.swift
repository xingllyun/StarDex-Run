/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UniformTypeIdentifiers

// 全新设计的签名工具页
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
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StarDexTopBar(title: "签名工具")
            }
            .navigationTitle("")
            .navigationBarHidden(true)
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

    // 文件导入区
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件导入")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            
            Button(action: {
                showImporter = true
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.15))
                        Image(systemName: apkData == nil ? "doc.badge.plus" : "arrow.clockwise")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    .frame(width: 50, height: 50)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(apkData == nil ? "选择原始未签名 APK" : "重新选择 APK")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("支持从系统文件选择")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
            }
            .buttonStyle(PlainButtonStyle())
            
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green.opacity(0.8))
                Text("全程本地处理，无需联网")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // 信息预览区
    private func previewSection(_ info: SDRApkInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("信息预览")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            
            VStack(spacing: 12) {
                infoRow("包名", info.packageName)
                infoRow("版本名", info.versionName)
                infoRow("版本号", "\(info.versionCode)")
                infoRow("加固检测", hardeningName.map { "已加固：\($0)" } ?? "未检测到加固")
                infoRow("权限数量", "\(info.permissions.count)")
                infoRow("签名状态", sigSummary ?? "未校验")
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
        }
    }

    // 签名操作区
    private var signSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("签名操作")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            
            Button(action: {
                performSign()
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.15))
                        Image(systemName: "signature")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .frame(width: 50, height: 50)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本地执行签名")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("无需联网，安全快捷")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(16)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // 免责提示
    private var disclaimerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange.opacity(0.8))
            Text("免责声明：不支持脱壳、不支持破解加固包，仅处理合法原始安装包。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
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
