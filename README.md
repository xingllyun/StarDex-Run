# StarDex-Run
iOS侧载环境独立自研的Android APK运行时，纯字节码解释执行，无需越狱、无JIT编译。支持32/64位DEX自动识别，内置APK加固检测、签名校验与本地重签名工具。按需映射安卓API至iOS原生能力，覆盖组件生命周期、基础控件、存储、网络等常用场景。优先适配全能签/轻松签等侧载场景，要求大地址空间与大内存权限证书。支持iOS 16~19、26~27，MIT协议开源

## 云端打包（无需 Mac）

项目使用 XcodeGen 定义工程，构建全程跑在 GitHub Actions 的 macOS 云主机上，本地无需 Mac。

- 每次推送 `main` 分支或在 Actions 页手动触发，自动构建无签名包。
- 产物：`StarDexRun-unsigned.ipa` 与 `StarDexRun.app`，下载后用全能签/轻松签等侧载工具重新签名即可安装。
- 本地（有 Mac）也可复现：`xcodegen generate` 后 `xcodebuild`。
