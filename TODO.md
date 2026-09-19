# TODO List
### P0 — 修复工程与构建基线

- [x] 修复 `project.yml` 中 Widget target 的 `info:` 缩进错误。
- [x] 统一 bundle ID、日志 subsystem、Info.plist，不再残留 `com.praveetgupta`。
- [x] 删除已经无用的 Spotify URL Scheme。
- [x] GitHub Actions 改用 `xcode-27` runner。
- [x] CI 增加单元测试步骤，测试通过后再生成 IPA。
- [x] 保留无签名 `.ipa` 输出，继续兼容 AltStore 工作流。
- [x] 启用原生 iPad：`TARGETED_DEVICE_FAMILY = "1,2"`。
- [x] 更新 README，使其与实际的 XcodeGen/Actions 流程一致。

验收：✅ Actions 在 Xcode 27 下测试、构建并输出可侧载 IPA；iPhone 17 / iPad 10 真机测试通过。

### P1 — 彻底删除 Spotify

- [x] 删除 `SpotifyAuth.swift`、`SpotifySource.swift`。
- [x] 删除 Spotify Keychain、PKCE、Secrets.plist 和 URL Scheme。
- [x] 删除 `SpotifyAuthTests.swift`、`SpotifySourceTests.swift`、`CoordinatorTests.swift`。
- [x] 删除 Actions 中的 `SPOTIFY_CLIENT_ID`。
- [x] 删除首页 Spotify 登录区域。
- [x] 删除设置中的 Spotify 轮询间隔。
- [x] 删除播放来源选择、Spotify source badge 等状态。
- [x] 删除 `NowPlayingCoordinator`，让 `AppModel` 只订阅 `AppleMusicSource`。
- [x] 删除 `MusicSource`、`SourcePin` 和 Live Activity 中的 `sourceName`。
- [x] 更新 README 和代码注释。

验收：✅ Actions 构建通过，iPhone 17 真机测试通过；源代码、测试、配置和用户文档中不再存在 Spotify、Client ID、OAuth、Spotify Web API 相关实现或文案（本 TODO 的历史记录除外）。

### P2 — 完整系统语言本地化

采用系统语言，不提供 App 内语言切换。

- [x] 新建 String Catalog。
- [x] 支持：
    - 简体中文 `zh-Hans`
    - 繁体中文 `zh-Hant`
    - 英文作为 fallback
- [x] 本地化首页、设置、歌词页、错误信息、空状态、权限提示。
- [x] 本地化 Live Activity、灵动岛和 CarPlay 占位文案。
- [x] 本地化“开始驾驶模式／停止驾驶模式”快捷指令名称、描述和短语。
- [x] 本地化媒体库和定位权限说明。
- [x] 检查动态字符串，避免把完整英文句子拼接后再显示。
- [ ] 中文环境检查字体、换行、标点和 Dynamic Type。

验收：待 Actions 构建及 iPhone 17 简体中文／繁体中文／英文切换测试；同时检查字体、换行、标点和 Dynamic Type。

### P3 — 重构为中文歌词优先的数据模型

当前代码会直接把中文歌词转成拼音，这是必须先改掉的。

- [ ] 禁止在歌词载入阶段强制调用 `Transliterator.latinized`。
- [ ] 原始歌词永远保留，不做不可逆替换。
- [ ] 将单一 `text` 扩展为类似：
    - 原文
    - 翻译
    - 音译
    - 行起止时间
    - 可选逐字时间轴
- [ ] 默认显示策略：
    - 中文歌：显示原始中文。
    - 外语歌：显示原文；有中文翻译时在第二行显示翻译。
    - 音译默认关闭。
- [ ] 增加歌词显示设置：
    - 仅原文
    - 原文＋翻译
    - 原文＋音译
    - 繁简转换：保持原文／简体／繁体
- [ ] 支持全局歌词时间偏移校准。
- [ ] 缓存键加入歌词来源和数据格式版本，方便以后升级缓存结构。

验收：中文不再变成拼音；双语歌词结构化保存，Live Activity 可以选择显示原文或翻译。

### P4 — 多歌词源架构

- [ ] 把现有 `LRCLIBClient` 抽象成 `LyricsProvider`。
- [ ] 建立统一搜索结果和歌词模型。
- [ ] 增加匹配评分：
    - 标题
    - 多艺人
    - 专辑
    - 时长误差
    - 版本词：Live、伴奏、翻唱、Remaster 等
- [ ] Provider 按优先级查询。
- [ ] 为每次命中记录来源、匹配分数和失败原因。
- [ ] 设置页增加“当前歌词来源”和“重新匹配歌词”，但不让普通用户面对复杂配置。
- [ ] 保留 30 天本地缓存和 1 天未命中缓存。

初始优先级建议：

1. LRCLIB
2. 网易云或 QQ 音乐中的一个
3. 第二个中文来源
4. 暂不接入 Apple Music 私有歌词接口

### P5 — Lyricify Lyrics Helper 调研与移植

这个仓库值得使用，但适合“参考和选择性移植”，不适合作为 iOS 直接依赖。

原因：

- 它是 `.NET Standard 2.1`/C# 项目，并依赖 Newtonsoft.Json、SharpZipLib 等库，不能作为普通 Swift Package 接入 iOS。[项目配置](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Lyricify.Lyrics.Helper.csproj)
- 它支持 LRC、QRC、KRC、YRC、TTML、逐字歌词、翻译和繁简转换，这些能力非常符合中文用户需求。[项目说明](https://github.com/WXRIW/Lyricify-Lyrics-Helper)
- 代码采用 Apache-2.0，可以移植，但需要保留许可证和来源说明。[许可证](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/LICENSE)

具体 TODO：

- [ ] 先研究并移植统一歌词模型，不整体搬运 C# 工程。
- [ ] 第一阶段只移植网易云 YRC/LRC 或 QQ 音乐歌词解析中的一个。
- [ ] 为移植代码保留 Apache-2.0 版权声明。
- [ ] 为逐行、翻译和逐字歌词制作固定测试样本。
- [ ] 第二阶段再考虑 QRC/KRC 解密、TTML 和背景人声。
- [ ] 所有第三方 Provider 都必须支持单独禁用，接口失效时自动回退 LRCLIB。

风险说明：

- 网易云实现调用 `weapi/eapi` 私有接口并包含加密过程，不属于稳定官方 API。[网易云实现](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/Netease/Api.cs)
- QQ 音乐同样调用网页/客户端接口，并处理 QRC 解密。[QQ 音乐实现](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs)
- Lyricify 的 Apple Music 歌词实现使用 `amp-api.music.apple.com` 私有接口、从 Apple Music 网页提取 Access Token，并在完整能力下依赖 Media User Token，维护风险更高，不建议首批采用。[Apple Music Provider](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/AppleMusic/Api.cs)

因此，推荐先做“LRCLIB + 网易云 fallback”，验证中文歌曲覆盖率后再决定是否加入 QQ 音乐。

### P6 — iPhone/iPad 全屏歌词体验

- [ ] 将现有导航歌词页改造成真正的沉浸式全屏。
- [ ] 支持点击首页歌词卡片展开、手势关闭。
- [ ] iPhone 竖屏突出当前歌词和上下文。
- [ ] iPad 10 原生自适应布局，支持横屏。
- [ ] 加入歌词字号、行距、翻译显示和偏移调节。
- [ ] 自动滚动时避免用户手动浏览被强制拉回。
- [ ] 用户停止拖动一段时间后恢复跟随。
- [ ] 正确处理超长中文句子、双语行和无时间轴歌词。

### P7 — Live Activity、灵动岛与 CarPlay 中文优化

- [ ] 当前行优先显示中文原文。
- [ ] 根据空间决定是否显示翻译。
- [ ] 灵动岛 compact 模式只显示一行，避免中文被压缩过度。
- [ ] expanded、锁屏和 CarPlay 显示当前行＋下一行。
- [ ] 检查暂停、等待播放、无歌词、加载失败等中文状态。
- [ ] 保持 Activity 更新只发生在换行、换歌和播放状态改变时。
- [ ] 长时间驾驶真机测试更新预算、暂停恢复和切歌。
- [ ] 不增加传统 CarPlay entitlement，不使用 CPTemplate。

### P8 — 测试与验收

- [ ] 删除所有 Spotify 测试并补齐 Apple Music-only pipeline 测试。
- [ ] 增加简体、繁体、日文、韩文、英文和双语歌词样本。
- [ ] 增加多艺人、同名歌曲、Live/Remaster/伴奏版本匹配测试。
- [ ] 增加翻译合并、繁简转换、逐字降级逐行测试。
- [ ] iPhone 17 真机测试。
- [ ] iPad 10 真机测试（仅在专门开发或修改 iPad 布局时执行；常规阶段验收省略）。
- [ ] CarPlay 连接、断开、暂停、切歌、锁屏和后台长时间测试。
- [ ] 验证 AltStore 重签后主 App 与 Live Activity Extension 都能正常启动。

推荐实际执行顺序是：`P0 → P1 → P2 → P3 → P6 → P7 → P4/P5 → P8`。先得到一个干净、全中文、Apple Music-only、iPhone/iPad 均可用的版本，再引入网易云/QQ 等不稳定外部接口。

测试约定：日常版本以 Actions 和 iPhone 17 真机为准；iPhone/iPad 系统版本一致，除非阶段内容专门涉及 iPad 布局或交互，否则不再单独进行 iPad 10 真机测试。
