# 心屿 OS V3 — 交付测试记录

日期：2026-11-04

## 已实际完成（本环境）

- 检查 `pubspec.yaml` 文件有效性、核心依赖声明、Dart 文件的相对引用与模块结构：通过。
- 检查所有 Dart 源码和测试文件的括号成对结构（忽略字符串与注释）：通过。
- 代码静态安全断言：API Key 与普通 JSON 分离、HTTPS URL 校验、禁止 3xx 自动跟随、角色朋友圈默认未授权、群聊轮次上限：通过。
- 用生成的示例 Android / iOS 宿主文件测试 `prepare_platforms.py`：Android INTERNET、禁用明文传输/备份、iOS 最低版本和名字补丁均成功写入。
- 已提供 Flutter 测试用例，覆盖六类配置、五类模型回复解析、请求结构、拒绝 HTTP、默认权限、本地 JSON 往返。

## 尚未执行（必须在开发机或 CI 上完成）

- `flutter pub get`：制作环境没有 Flutter SDK 和下载网络。
- `flutter analyze`：未运行 Dart 编译器；不能确认所有代码完全通过分析。
- `flutter test`：测试用例已写入但未实际执行。
- 真实 Android APK 构建、安卓手机安装和本机 API 调用测试：未执行。
- iOS 模拟器编译、iPhone 真机代码签名、iOS API 联调：未执行。
- 商用级安全审计、iOS App Store / Google Play 审核：未执行。

## 后续优先验收路线

1. 在构建机完成 `flutter pub get`、`flutter analyze`、`flutter test`。
2. Android 用 `flutter build apk --debug` 安装一台真实手机；iOS 在 Mac 上通过 Xcode 安装到真机。
3. 用自己的一个正常计费的 API Key 完成“测试连接 → 保存 → 绑定小满 → 私聊返回正文”。
4. 测试错误密钥、无额度、网络断开、不同模型 ID 的错误提示。
5. 群聊至少两位 AI，验证按序回复且不会无限循环。
6. 朋友圈在默认关闭的情况下不能生成；用户打开后可手动生成。
7. 杀掉 App 再重新打开，验证联系人、聊天记录、壁纸、音乐和主题设置持久化。
8. 用文件应用导入 TXT / MD / JSON / DOCX，检查中文文本无乱码。

结论：这是**可用于跨平台开发和编译验证的源代码交付**，不是已通过双平台真机验收的正式 App。不要拿静态检查替代 APK/IPA 真实安装测试。
