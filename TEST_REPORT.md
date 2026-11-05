# 心屿 OS V3.3 检查状态

本次由 V3.2 工程升级，**交付的是待编译 Flutter 源码**，不是已经编译或真机验收的 APK。

## 已完成的静态检查

- 12 个 lib/*.dart 源文件在括号/相对 import 层面通过静态检查。
- 原有 `activation_service.dart`、`ui_activation.dart`、`tools/configure_release_signing.py` 未改动；签名验证和本地文件路径保留。
- API Key 依然仅通过 flutter_secure_storage 保存，未写进 AppData JSON。
- 新增 `ApiProfile.apiProtocol`，旧用户从 JSON 导入时默认 chat；提供自定义中转站 `/models` 列表、Chat Completions / Responses 两种请求格式的代码与单元测试。
- 新增 `Character.allowSocialInteractions`、`friendIds`，默认无授权和好友关系；只对双向关系的 AI 展示/互动模拟朋友圈。
- 新增 MomentEntry.likedBy、MomentComment 及 parentId；兼容之前没有这些字段的存储数据。
- 新增点赞、评论、定向 AI 回复、手动邀请好友互动，以及前台一小时节流自动邀请的 UI 与 controller 代码。
- 新增消息编辑、最后一次私聊回复重生成、聊天气泡透明度/颜色/时间设置。
- 增加 test/moments_contract_test.dart，并在 GitHub Actions 编译流程中纳入测试。
- 公开工程中不包含 APK 签名私钥或管理员激活码签发私钥。

## 尚未完成、需要你运行 GitHub Actions 及真机测试的事项

1. Flutter analyze / flutter test / flutter build apk --release **在此环境无法运行（没有 Flutter SDK）**。新代码可能仍有编译或插件兼容错误；应以 Actions 日志为准。
2. 中转站 `/models`、`/chat/completions`、`/responses` 的真实协议和网络兼容性仍需用户自己的中转站与密钥验证。
3. 真机验证角色头像、桌面图标、音乐切换页面持续播放、消息编辑/重生成，以及前台自动朋友圈互动。
4. 真机覆盖升级验证旧激活码、旧聊天数据与旧 API Key 持久可用。
5. 「返回主界面后图标变成纯文字」缺少 App 画面和重现步骤，本次未确认根因。

### 建议最先测试的朋友圈情景

- 创建 A、B、C 三个角色，都配置有效 API；A 允许发朋友圈，A/B/C 都手动允许互动。
- 分别把 B 和 C 设为 A 的好友；用 A 发布动态。
- 你点赞、评论；点击该评论右边的小机器人：检查 A 与 B 能否回复且每人只回复一次。
- 点击「好友互动」：检查 B/C 由模型选择点赞或评论。
- 再对 B 的评论点回复，并邀请 AI 回复：检查其他角色可对 B 的评论再回复。
- 关闭所有互动权限，检查不会再发起社交模型请求。
- 彻底退出 App 再打开，验证点赞、评论、好友关系都仍然存在。
