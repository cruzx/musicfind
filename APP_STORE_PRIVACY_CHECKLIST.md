# FlipMusic App Store Connect 隐私核对表

核对日期：2026 年 8 月 4 日

## App 内容与链接

- App 内已提供“隐私政策”入口。
- App 内已提供“联系我们”入口。
- 隐私政策 URL：`https://github.com/cruzx/musicfind/blob/main/PRIVACY.md`
- 支持 URL：`https://github.com/cruzx/musicfind/blob/main/SUPPORT.md`
- 只有在本次改动合并到 `main` 后，再将上述 URL 填入 App Store Connect。

## App Store Connect 建议选项

### 数据收集

- 选择：“否，我们不会从此 App 收集数据”。

原因：提审版已移除 LRCLIB 和 lyrics.ovh 外部歌词服务。Apple Music 资料库和歌词只在设备内读取，App 没有开发者后台、广告 SDK 或分析 SDK。专辑封面和音乐信息请求仅使用 Apple 服务；Apple 官方说明不需申报由 Apple 收集的数据。

### 不应勾选

- 联系信息
- 位置
- 健康与健身
- 财务信息
- 用户内容
- 浏览历史
- 标识符
- 购买记录
- 广告数据
- 诊断数据
- 跟踪

## 设备内处理，不作为开发者收集

- Apple Music 资料库、歌单、专辑、播放次数和最近播放信息由 App 在设备内读取和排序。
- 用户的偏好设置保存在设备的 UserDefaults 中。
- App 不包含开发者账号系统、广告 SDK 或自建数据后台。

## 后续变更

如果以后重新引入外部歌词、分析、广告或开发者后台，必须在发布前同步更新：

- `musicfind/PrivacyInfo.xcprivacy`
- `PRIVACY.md`
- App 内隐私政策
- App Store Connect 的 App 隐私选项
