# V3.6 测试与尚需验证的项目

## 当前环境已完成

- `python tools/static_check.py`: 通过（16 个 Dart 模块、相对引用、密钥分离、HTTPS、安全权限、构建配置基础一致性检查）。
- `python tools/check_activation_vector.py`: 通过（签名、设备号匹配、签名篡改拒绝测试）。
- 已检查新数据字段 `imagePath`, `previousVersions`, `inputTokens`, `outputTokens`, `myAvatarPath`, `fontPath`, `notes`, `albumPaths` 都包含序列化与旧数据默认值。
- 已创建 `test/v36_contract_test.dart`，包括旧存档升级、消息历史、图像请求结构、真实 Token 返回字段。GitHub 工作流已经纳入测试。

## 尚未完成

- 未运行 `flutter analyze` / `flutter test`，当前环境没有 Flutter SDK。新 Dart 代码可能存在需要依据 GitHub 日志修复的编译问题。
- 未使用真实手机执行 API、图片发送、文件权限、音频循环、字体加载、键盘自动收起等测试。
- 未实际完成一个成功的 V3.6 APK Release 构建，也未验证旧版覆盖安装后的所有数据迁移。
- 只有服务商返回的用量才显示真实 Token；部分流式或中转站不返回用量。
- 音乐循环只保证当前应用存活和音频通路可用时的重复播放，不保证锁屏/被系统杀死后继续播放。
- Markdown 当前仅增强代码围栏显示，复杂 Markdown 渲染不完整。
- 多模型图片 API 请求遵循官方格式，但具体中转站及模型能力还需实测。

## 建议真机验收路径

旧 APK 覆盖安装 → 启动不需二次激活 → API 连接 → 新消息和图片 → 回复时收起键盘 → 编辑与重生成查看历史 → 播放音乐并切聊天 → 单曲循环、删除、关闭 → 本地字体导入重启 → 联系人背景和透明度 → 用户发朋友圈 → 本地相册/备忘录/日记。
