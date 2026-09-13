/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI
import UIKit

@main
struct StarDexRunApp: App {
    @StateObject private var appState = AppState()

    init() {
        // 全局外观：纯黑底（#000000）+ 白字 + 系统蓝强调色，还原旧版原生风格。
        configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }

    private func configureGlobalAppearance() {
        let black = UIColor.black
        let white = UIColor.white

        // 导航栏
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = black
        navAppearance.titleTextAttributes = [.foregroundColor: white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = .systemBlue

        // Tab 栏
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = black
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = .systemBlue
        UITabBar.appearance().unselectedItemTintColor = UIColor(white: 0.6, alpha: 1.0)

        // 列表 / 表单
        UITableView.appearance().backgroundColor = black
        UITableViewCell.appearance().backgroundColor = black
    }
}