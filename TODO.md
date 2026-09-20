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
- [x] 中文环境检查字体、换行、标点和 Dynamic Type。

验收：✅ Actions 构建通过，iPhone 17 简体中文／繁体中文／英文切换及界面显示测试通过。

### P3 — 重构为中文歌词优先的数据模型

原问题：旧代码会直接把中文歌词转成拼音，导致原文丢失。

- [x] 禁止在歌词载入阶段强制调用 `Transliterator.latinized`。
- [x] 原始歌词永远保留，不做不可逆替换。
- [x] 将单一 `text` 扩展为类似：
    - 原文
    - 翻译
    - 音译
    - 行起止时间
    - 可选逐字时间轴
- [x] 默认显示策略：
    - 中文歌：显示原始中文。
    - 外语歌：显示原文；有中文翻译时在第二行显示翻译。
    - 音译默认关闭。
- [x] 增加歌词显示设置：
    - 仅原文
    - 原文＋翻译
    - 原文＋音译
    - 繁简转换：保持原文／简体／繁体
- [x] 支持全局歌词时间偏移校准。
- [x] 缓存键加入歌词来源和数据格式版本，方便以后升级缓存结构。

验收：✅ Actions 构建及 iPhone 17 真机验证通过：中文保持原文、双语第二行、音译开关、繁简转换、时间偏移，以及 Live Activity 显示模式。

### P4 — 多歌词源架构

- [x] 把现有 `LRCLIBClient` 抽象成 `LyricsProvider`。
- [x] 建立统一搜索结果和歌词模型。
- [x] 增加按字段优先级进行的字典序匹配：
    - 标题
    - 多艺人
    - 专辑
    - 时长误差
    - 版本词：Live、伴奏、翻唱、Remaster 等
    - 当前显示设置要求的翻译或音译
    - 是否逐字
- [x] Provider 按固定优先级懒惰查询；先用轻量元数据排序，每个来源最多拉取 3 份完整歌词，命中完美结果后停止。
- [x] 为每次候选记录来源、逐项匹配结果和失败原因。
- [x] 设置页增加“当前歌词来源”和“重新匹配歌词”，但不让普通用户面对复杂配置。
- [x] 保留 30 天本地缓存和 1 天未命中缓存；翻译／音译要求分别缓存。

当前固定优先级：

1. 酷狗音乐（KRC 逐字）
2. 网易云音乐（优先 YRC 逐字，匿名接口无 YRC 时降级 LRC）
3. LRCLIB

不接入其他来源，也不接入 Apple Music 私有歌词接口。

### P5 — Lyricify Lyrics Helper 调研与移植

这个仓库值得使用，但适合“参考和选择性移植”，不适合作为 iOS 直接依赖。

原因：

- 它是 `.NET Standard 2.1`/C# 项目，并依赖 Newtonsoft.Json、SharpZipLib 等库，不能作为普通 Swift Package 接入 iOS。[项目配置](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Lyricify.Lyrics.Helper.csproj)
- 它支持 LRC、QRC、KRC、YRC、TTML、逐字歌词、翻译和繁简转换，这些能力非常符合中文用户需求。[项目说明](https://github.com/WXRIW/Lyricify-Lyrics-Helper)
- 代码采用 Apache-2.0，可以移植，但需要保留许可证和来源说明。[许可证](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/LICENSE)

具体 TODO：

- [x] 研究并移植统一歌词模型，不整体搬运 C# 工程。
- [x] 接入网易云 YRC/LRC 与酷狗 KRC，并合并翻译／音译。
- [x] 为移植代码保留 Apache-2.0 来源和许可证声明（见 `THIRD_PARTY_NOTICES.md`）。
- [x] 为逐行、翻译、音译和逐字歌词制作固定测试样本。
- [x] 完成 KRC 解密；不接入 QRC、TTML 和背景人声。
- [x] 第三方 Provider 可通过注入列表单独禁用；接口失效时自动回退下一来源直至 LRCLIB。

风险说明：

- 网易云实现调用 `weapi/eapi` 私有接口并包含加密过程，不属于稳定官方 API。[网易云实现](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/Netease/Api.cs)
- QQ 音乐同样调用网页/客户端接口，并处理 QRC 解密。[QQ 音乐实现](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs)
- Lyricify 的 Apple Music 歌词实现使用 `amp-api.music.apple.com` 私有接口、从 Apple Music 网页提取 Access Token，并在完整能力下依赖 Media User Token，维护风险更高，不建议首批采用。[Apple Music Provider](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/master/Lyricify.Lyrics.Helper/Providers/Web/AppleMusic/Api.cs)

当前实现以“酷狗 → 网易云 → LRCLIB”懒惰搜索；网易云和酷狗均为非官方接口，失效时会自动回退。

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
- [x] 保持 Activity 更新只发生在当前字／换行、换歌和播放状态改变时，未变化的 500 ms tick 不推送。
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

### P9 — 逐字动画、播放控制与专辑封面

- [x] 歌名不匹配时立即改用仅歌名的第二阶段搜索，继续保留时长、翻译／音译和逐字排序。
- [x] 修正候选时长排序：±3 秒容差内视为同档，再比较翻译／音译和逐字，避免毫秒级误差让 LRCLIB 压过网易云逐字歌词。
- [x] 中文原文歌词在“原文＋翻译”模式下不再强制要求翻译，避免为中文歌继续搜索后续来源；音译模式保持原评估规则。
- [x] 增加持久化“启用歌词”总开关；关闭时取消搜索、清空同步状态、结束 Live Activity，并停止歌词后台保活。
- [x] App 全屏歌词增加逐字高亮动画。
- [x] 灵动岛展开态和锁屏实时活动增加逐字高亮；由于真机不会可靠刷新 Activity 内的 `TimelineView`，改为仅在当前字变化时推送精简状态。
- [x] 灵动岛紧凑态按当前字推进歌词，并给尾部文本明确宽度，避免 `GeometryReader` 被系统压缩到单字都放不下。
- [x] App 增加可拖动时间轴、暂停／播放、上一首和下一首。
- [x] 灵动岛展开态增加暂停／播放、上一首、下一首和前后 15 秒跳转；按真机反馈移除锁屏控制和两处进度条，并放大展开态控件。
- [x] 灵动岛展开、紧凑和 minimal 图标替换为专辑封面缩略图；锁屏实时活动不显示封面。
- [x] 设置页显示懒惰搜索实际解析过的候选歌词，支持手动选择，并按歌曲和翻译／音译设置记住选择。
- [x] 精简 Live Activity 状态载荷并提高封面 JPEG 预算，展开态歌词与封面共同占满可用宽度。
- [ ] 真机复测共享逐字状态更新下的灵动岛逐行显示；若换行仍会被冻结，再评估降低全局 Activity 更新频率。
- [x] 锁屏继续渲染逐字高亮；灵动岛展开态和紧凑态将同一状态重新拼成完整当前行，只在换行时产生可见变化，并移除紧凑态逐字滚动字段。
- [x] 增加持久化“实时活动逐字更新”开关：开启时以 0.25 秒采样积极推送锁屏／CarPlay 逐字状态，关闭时所有实时活动仅提交逐行状态。
- [x] 灵动岛紧凑态无论逐字开关状态都用单次换行更新的插入转场，从行首滚到行尾；动画按该行剩余时间自动压缩，并为行尾保留完整字符余量。展开态取消歌词行数限制并允许自动换行。
- [ ] Actions 构建与 iPhone 17 真机验收。

推荐实际执行顺序是：`P0 → P1 → P2 → P3 → P6 → P7 → P4/P5 → P8 → P9`。先得到一个干净、全中文、Apple Music-only、iPhone/iPad 均可用的版本，再引入外部歌词接口与交互增强。

测试约定：日常版本以 Actions 和 iPhone 17 真机为准；iPhone/iPad 系统版本一致，除非阶段内容专门涉及 iPad 布局或交互，否则不再单独进行 iPad 10 真机测试。
