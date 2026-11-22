# App

第三方 AppDump（`blade` 工程，ObjC / Theos）为基底，**不改动、不删减它的任何原有代码**，
在其之上把本项目 AppDump（SwiftUI 版）里它没有的能力以**新增模块**的形式加了进去，
构建出一个可安装的 IPA。

- `src/` — 第三方源码，逐字节原样（`diff -r` 为空）
- `build_ipa.sh`、`tools/`、根目录的 `*.py` — 第三方原包自带，原样保留
- `extras/` — **本次新增**的全部代码（不覆盖、不修改 `src/`）
- `ci/` — 构建脚本（macOS 版；原包自带的是 Linux/theos 版 `build_ipa.sh`，两者并存）

## 新增了什么

| 功能 | 实现 | 说明 |
| --- | --- | --- |
| **FairPlay 用户态砸壳** | `extras/FairPlayCore.c` + `ADXFairPlayJob.m` + `ADXAppListViewController.m` + `ADXJobViewController.m` | 走 `mremap_encrypted()`，由 fairplayd 解密后回读。**不需要内核漏洞**；用已安装 App 自带的 `SC_Info` 授权直接出包 |
| **解除安装限制** | `ADXFairPlayJob.m` 的 `relaxInstallRestrictionsInApp:` | 出包时把 `MinimumOSVersion` 降到 10.0，去掉 `UIRequiredDeviceCapabilities` / `UISupportedDevices`（作用于暂存副本，不动已安装包） |
| **屏蔽 App Store 更新** | `ADXBlockUpdates.m` + `ADXRemoteCompat.m` + `ADXBlockViewController.m` | 移植 AppDump 的 installd placeholder 做法：`.app` 父目录下建 `com.apple.mobileinstallation.placeholder`（0000） |
| **产物管理** | `ADXIPAViewController.m` | 列出 `Documents/Decrypted/*.ipa`，分享 / 删除 |
| **入口** | `ADXHook.m` + `ADXHomeViewController.m` | 运行时交换 `UITabBarController -setViewControllers:`，往第三方主界面的标签栏末尾追加「扩展」页。第三方源码零改动，它自己重建标签栏时也会保住这个 tab |

`FairPlayCore.c` 来自本项目（原 iPadn 实现）的 `fairplay/FairPlayCore.c`，逐字节复制。
`ADXBlockUpdates.m` / `ADXRemoteCompat.m` 由本项目的 `kcblock.m` / `kcdowngrade_compat.m` 移植，
只把「全局函数接口」接到第三方源码里已有的 `TaskRop/RemoteCall`、`SKKernelLock` 上。

## 构建

### GitHub Actions（仓库自带）

`.github/workflows/build.yml` 在 `macos-15` 上跑 `ci/build_ipa_macos.sh`，产物 `dist/App.ipa`（未签名）。

### 本地（macOS + Xcode）

```bash
./ci/build_ipa_macos.sh
```

用 `xcrun --sdk iphoneos clang` 编译，源文件清单与 `src/Makefile` 的 `blade_FILES` 一致
（`SKDiag.m` 依旧排除，与原构建脚本相同），最后 `codesign -s -` 内嵌 `src/appdump.entitlements`。

### 原包的 Linux/theos 构建

`./build_ipa.sh` 仍可用（需要 `/opt/theos` 的 linux/iphone 工具链 + iPhoneOS16.5 SDK）。
它不会编译 `extras/`，要带上新增模块请用 macOS 脚本。

## 说明与已知限制

- 新增页只出现在第三方 App 的标签栏末尾（标题「扩展」），第三方原有页面（砸壳 / 应用 / 文件，
  以及设置里的内存编辑、进程列表、偏移管理等）都保持原状。
- FairPlay 砸壳需要能读到目标 App 的 bundle —— 若读不到，先在第三方「砸壳」页初始化系统（沙盒逃逸）。
- 屏蔽更新需要内核读写就绪（第三方利用链跑成功），且要先去 App Store 点一次「获取」把 installd 唤醒。
- 安装限制只改出包时的暂存副本；修改已安装 App 的 Info.plist 会让签名失效。
- 产物目录 `Documents/Decrypted/`，`Info.plist` 里 `UIFileSharingEnabled = true`，「文件」App 可直接取。