> 2026-09-28 更新：已接入 iOS 27.1 分隔区域与双向布局，最新状态见 [FOLDABLE_STATUS.md](FOLDABLE_STATUS.md)。下方是此前验证记录。

# 悬停播放器

入口：我的音乐 → 悬停模式。当前通过手动入口展示，不依据普通横竖屏或设备运动猜测折叠状态。

上半区域复用 `FluidPlayerOverlay(isLandscape: true)`，保留现有封面、歌词、文本取色及手势。下半区域将当前播放队列展示为五列 `SongSquare` 封面网格，并复用 `BottomNavigationBar` 胶囊。点击当前封面暂停/继续，点击其他封面按原队列顺序切歌。退出模式不停止播放。

`FlexPlayerLayout` 可接受横向 division frame，将其完整留空；没有区域数据时用于手动预览，上半区域最高占可用空间的一半，窄屏限制高度以保留横屏构图。下半滚动区底部留出 85 pt，使最后一排可以滚到胶囊上方。

## 设备 API 边界

当前本地 SDK 为 iOS 27.0，没有 `GeometryProxy.reservedRegions`。Apple 的 [iPhone Duo 布局讲解](https://developer.apple.com/videos/play/tech-talks/111463/) 展示了 iOS 27.1 的 reserved regions / ArrangementView。升级到支持该接口的 SDK 后，需从真实窗口的 active `.division` 区域传入 frame，并仅在横向分割姿态自动进入此模式。还需进行 Duo 姿态、外屏/内屏连续切换和系统安全区域验证。当前版本没有接入自动折叠检测。

## 验证入口

Debug 构建使用 `--flex-preview` 启动本地交互测试界面；追加 `--flex-empty` 验证空队列。Release 不包含该启动入口。

- `FlexPlayerLayoutTests`：窄屏、横屏、近方形、真实分割区及无效分割区。
- `FlexPlayerUITests`：选歌、暂停、滚动到最后一项、退出和空队列。
- 音乐服务真实续播依然复用 `MusicConnectionManager`，需要连接有曲库的真机验收。

## 本次验收（2026-09-16）

使用本机 Xcode 26.6 / iOS 26.5 模拟器完成最终构建和 12 项测试（4 项布局/截图、5 项播放状态、3 项 UI 交互），全部通过。Xcode 27.0 的 Metal Toolchain 当前缺失，因此采用已安装的完整工具链验证。构建副本与工作区源码逐文件核对一致。

此前已在本地目视检查近方形布局、普通 iPhone 布局和正式入口。截图使用本地测试曲目和示意封面，不作为实际折叠屏适配验收；截图未包含在此分支。

模拟器冷启动初始化曲库时，首次设置点击可能被加载过程打断；正式入口测试等待后再次点击可正常进入与返回。真机当前未连接，未安装此次版本，也未验收真实音乐服务连续播放及 Duo 自动姿态切换。
