# 心屿 OS V3.8 · 亲密互动功能模块（Flutter 源码）

**重要：这是一份独立的 Flutter 演示工程 + 可移植的功能模块，绝不是已合并到旧 V3.7 App 的正式 APK。** 当前会话里没有可读取的 V3.7 源码，所以不能假称完成了旧通讯录、激活码、数据库、签名系统的集成。本包不含旧用户的 API Key、激活私钥或签名文件。不能直接用本包 APK 覆盖你已经发布的 V3.7。

## 本次真正写成的模块

| 功能 | 源码位置 | 范围与说明 |
|---|---|---|
| AI 角色 → 亲密互动 | `lib/pages/hub_page.dart` | 独立角色 ID、人格、模型回调，宠物/音乐/视频/小游戏入口 |
| Markdown / JSON 剧情自动解析 | `lib/core/story_parser.dart` | 从回复中分离场景、动作、对白、心声与状态；结构化 JSON 优先、Markdown 兜底 |
| 剧情卡片渲染与真实 API 生成 | `lib/pages/story_page.dart` | 可编辑原文，结构化渲染；配置兼容 API 后可请求新剧情 |
| 15 种宠物图鉴 | `lib/core/pet_engine.dart` | 猫、犬、兔、仓鼠、企鹅、刺猬、狐狸、熊猫、水獭、松鼠、小鹿、六角龙、龙、独角兽、水母 |
| 宠物蛋养成与孵化 | `lib/pages/pet_page.dart` | 至少 1h + 80亲密值，稀有度权重 65/28/7；可选择蛋壳主题并彩绘；本地持久化 |
| 宠物动作与表情 | `lib/widgets/pet_art.dart` | Flutter 矢量绘制、浮动/晃动；高兴/撒娇/疲惫切换。当前是矢量演示画风，不是高精度 15 套动画资产 |
| 孵化后养成 | `lib/core/pet_engine.dart` | 投喂、玩球、洗澡、睡眠、抚摸、挠痒、轻拍、训练、探险；饥饿/心情/精力/经验/等级 |
| 五子棋 | `lib/core/game_engines.dart` | 15x15、棋盘点击、胜负、基础阻挡和抢五 AI；不依赖云端下棋 |
| 飞行棋轻量版 | 同上 | 双人各2架、6点起飞、24格、落点相撞、胜负 |
| 大富翁轻量版 | 同上 | 16格、星币、土地购买、过路费、随机事件、破产；无真实支付 |
| 一起听歌 | `lib/pages/media_page.dart` | 导入手机本地音频、播放/暂停、循环、LRC 歌词同步、在其他互动页面持续播放（全局注入音乐服务） |
| 一起看视频 | 同上 | 导入本地视频、播放/暂停/进度、SRT 字幕，伴随 AI 交流；视频画面默认不发给模型 |
| 淡化互动聊天栏 | `lib/widgets/chat_overlay.dart` | 每页底部常驻；可展开聊天记录；根据动作自动评论（8s限流）、直接输入消息 |
| OpenAI 兼容接口 | `lib/core/companion.dart` | 演示环境 HTTPS 请求；可适配现有 GPT/Claude/Gemini 等模型路由（各家原生协议未在本包重新实现） |
| 角色独立宠物存档 | `lib/core/storage.dart` | 本机 `SharedPreferencesAsync`，键为 `intimacy.pet.<roleId>` |
| 基础单元测试 | `test/companion_engines_test.dart` | 格式解析、15 宠物、孵化、五子棋、飞行棋、星币、字幕时间轴 |

## 运行独立演示工程

需安装 Flutter SDK、Android SDK：

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter run
```

如果 GitHub 上编译独立样例，已有 `.github/workflows/verify.yml`；它生成的仅为调试 APK，不能覆盖你的心屿 OS 正式版。

## 接入旧 App（必须先合并代码）

见 `docs/INTEGRATION_CN.md`，包括角色资料入口、模型适配回调、音乐全局生命周期和应用签名注意事项。

## API 安全

演示 API Key 仅停留在运行内存中，不写入 `SharedPreferences`，应用重启需要重填。正式 App 应复用旧版 Keystore/Keychain 安全存储，不要把 Key 硬编码到 APK、截图、日志或 GitHub。

## 尚未完成或需要真机验收

- 没有原 V3.7 源码，因此旧数据迁移、激活、长期记忆、朋友圈、聊天界面的接入均未完成。
- 现有矢量宠物是动画占位美术，不是 15 套完整帧动画、动作特效与音效系统。
- 飞行棋/大富翁是**可玩的简化规则版**，并非严格复刻所有地块、道具和复杂规则。
- 当前小游戏战局只保存在页面状态，退出小游戏会重新开始（宠物状态会本地保存）。
- 没有自动视频画面/声音理解；字幕或歌词共享必须由用户手动打开。歌词原文只传短片段。
- 没有锁屏音频后台服务，也没有让应用被杀掉后自动调用 AI 的保证。
- 此环境没有 Flutter SDK，无法本地执行 `flutter analyze/test/build`；请以 GitHub Actions 结果为准，不要当成编译已通过。

## 内容边界

这是一款虚拟陪伴与模拟游戏：宠物、内心活动、虚拟星币都是**软件生成或本地模拟状态**；不代表模型具有真实感知、意识、或任何真实金融账户。抽蛋无现金充值、无有价物品兑换，亦不涉及真实商品购买。
