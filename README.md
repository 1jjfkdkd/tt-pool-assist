# TT 桌球辅助（独立 App，跨进程）

不注入 TT、不改任何游戏数据：用 **ReplayKit 广播扩展**读屏 → **App Group** 传帧 → 主 App 做识别与几何 → **画中画**浮在 TT 之上显示辅助线。

## 目录

```
App/                      主 App（SwiftUI）
  AppMain.swift           界面 + 读帧循环 + 广播选择器
  PiPController.swift     画中画渲染（AVSampleBufferDisplayLayer）
  Info.plist / App.entitlements
BroadcastExtension/       ReplayKit 广播上传扩展（独立进程）
  SampleHandler.swift     整屏 → 480×270 JPEG → App Group
Shared/                   两端共用
  AssistConst.swift       App Group ID、尺寸、常量
  FramePipe.swift         共享容器的读写（原子替换）
project.yml               XcodeGen 工程描述（自动生成 .xcodeproj）
.github/workflows/        macOS runner 自动出包
```

## 一、构建

本机无 Xcode，用 CI 出包：

1. 把整个 `tt-pool-assist/` 推到 GitHub 仓库
2. Actions → `build-ipa` → Run workflow
3. 下载 `TTPoolAssist-ipa` 工件，得到 `TTPoolAssist.ipa`（未签名）

本机有 Mac 也可以：

```bash
brew install xcodegen
xcodegen generate
open TTPoolAssist.xcodeproj      # 选自己的开发者证书后 Archive
```

## 二、安装与授权

1. 用 TrollStore / Sideloadly 自签安装 `TTPoolAssist.ipa`
2. 首次打开 App，点「开始录屏」→ 系统会拉起广播面板
3. 控制中心 → 屏幕录制 长按 → 选「桌球广播」开始
4. 回到 App 点「起画中画」，再切到 TT —— PiP 窗口会浮在上层

## 三、当前版本（Step 1）能力

- ✅ 广播扩展 → App Group → 主 App 显示 480×270 实时缩略图
- ✅ 画中画窗口浮起，画面随录屏刷新
- ⬜ 球桌四点检测 / 透视校正（Step 2）
- ⬜ 球位识别（Step 2）
- ⬜ 球杆方向 + 多库反弹预测（Step 3，几何代码已有 C 版可直接移植）

## 四、已知限制

| 限制 | 说明 |
|---|---|
| 每次要手动开广播 | iOS 系统限制，控制中心里点一次 |
| 延迟 100–250ms | 降采样 + 传帧 + 渲染的固有开销 |
| App Group 需要签名带上 entitlement | TrollStore 自签可带；免费个人证书不支持 App Group，此时改用 Sideloadly 或付费证书 |
| 画中画需前台启动一次 | 之后可后台常驻 |

## 五、下一步

Step 2 需要真实对局截图来调 CV 参数：装上后开一局桌球，广播 + 画中画跑通后，把 App 里显示的缩略图截屏发我几张（不同球桌皮肤各一张），我按实际像素把检测阈值定死。
