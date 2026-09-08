/*
 * StarDex-Run
 * Copyright (c) 星云云络科技
 * MIT License
 * 独立自研实现
 */

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            MainView()
                .tabItem { Label("应用", systemImage: "square.grid.2x2") }
            SignToolView()
                .tabItem { Label("签名", systemImage: "signature") }
            LogView()
                .tabItem { Label("日志", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
    }
}