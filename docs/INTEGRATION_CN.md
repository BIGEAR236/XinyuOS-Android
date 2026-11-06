# 接入心屿 OS V3.7 的正确方式（避免以前的覆盖文件错误）

## 一、不要整包覆盖旧工程

本包是**独立可编译的 Flutter 功能模块**。因为没有读取到你私有仓库的现有源文件，此处不知道 V3.7 的 `AppController`、数据存储、`ui_chat.dart` 和路由的精确签名。因此**不能**直接复制整个 `lib` 覆盖旧版。尤其不要复制 `lib/main.dart`、`pubspec.yaml`、`.github` 盖掉旧工程。

要做真正 V3.8 升级，请先把本包的 `lib/core` 中的功能文件、`lib/widgets`、`lib/pages` 并入旧工程的一个新的功能命名空间（建议 `lib/intimacy/`），再将此包使用的依赖逐项合并旧 `pubspec.yaml`。导入路径应与移动后的目录对应调整。旧的激活码验证、公钥、包名、应用签名和模型存储代码全部保持不变。

## 二、在“联系人详情 / 角色资料”新增唯一入口

建议联系人资料页仅保留以下 6 个条目：

1. 个人信息
2. 模型绑定
3. 好友关系
4. 朋友圈
5. 聊天背景
6. **亲密互动** → 宠物、听歌、视频、游戏

第 6 项的页面跳转示意：

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => CompanionHub(
      roleId: character.id,     // 旧 App 已有的稳定角色 ID
      roleName: character.name,
      persona: character.persona,
      responder: adapter,       // 下文的原模型适配回调
      musicRoom: appMusicRoom,   // 全 App 生命周期持有的音频服务
    ),
  ),
);
```

`character`、`appMusicRoom`、`adapter` 是**旧工程对象的示例名称**，不是对你现有 V3.7 API 的猜测。真实导入与字段名需要根据实际 V3.7 源码调整。

## 三、把 V3.7 已有的模型适配器接进互动系统

定义 `RoleResponder` 的实现，转发到你原先已经支持 GPT、Claude、Gemini、GLM、DeepSeek、中转站的 HTTP 客户端：

```dart
class ExistingAdapter implements RoleResponder {
  final MyCurrentModelService api;
  ExistingAdapter(this.api);

  @override
  Future<String> respond({
    required String roleId,
    required String roleName,
    required String persona,
    required String event,
    required String userMessage,
  }) async {
    return api.chatAsCharacter(
      roleId: roleId,
      systemPrompt: '''
角色身份：$roleName
角色档案：$persona
你正在和用户实时参与同一个虚拟互动空间。
已发生的真实游戏动作：$event
只说 1–2 句自然的话，不要幻想你看到了未传入的视频画面。
''',
      userText: userMessage,
    );
  }
}
```

上面的 `MyCurrentModelService` 和 `chatAsCharacter` 是**伪代码接口**，需要换成你现有 `api_client.dart` 的真实调用。不能将旧 API Key 搬到新 `SharedPreferences`。不同角色使用各自保存的模型绑定与安全密钥。

## 四、剧情对话协议（替换旧的 Markdown / JSON 模式选择）

角色人格文件：维持人物设定；**不**直接当作整段回答。

用户消息：正常输入“请用表格”“请用 Markdown”“请照这段格式”等内容；不需要设置下拉开关。

剧情页面内：优先请求模型输出 `StoryParser.outputContract` 定义的 JSON 结构，例如：

```json
{
  "time": "16:45", "place": "湖边咖啡馆",
  "beats": [
    {"type":"action","speaker":"","text":"他笑了一下"},
    {"type":"speech","speaker":"楼一","text":"这红包给我的？"},
    {"type":"thought","speaker":"楼一","text":"她比从前开朗多了。"}
  ],
  "status": {"剧情地点":"湖边咖啡馆","好感度":"38%","爱意":"12%","醋意":"0%","内心":"她竟然记得今天。"}
}
```

客户端再使用 `StorySceneCard` 分层渲染。若模型返回旧 Markdown，`StoryParser.parseMarkdown` 尝试降级解析。注意**一般聊天不应被强制输出该 JSON**：只有明确使用这类剧情模板的角色启用结构化渲染，其他普通 Markdown、表格、代码块走通用渲染器。

格式指令优先级：应用安全和工具授权 > 当前用户明确格式要求 > 角色背景的人格表达 > 普通风格默认。若模型输出字段缺失，UI 显示“格式不完整”，可提供一次自动修复或重新生成，不应无限重试。

## 五、游戏逻辑 vs AI 评论

- 游戏规则在本地确定：五子棋落点合法性、骰子点数、买地、宠物数值。
- 模型输入经过压缩的动作事件（例如：“用户喂小猫，饱腹值从40到66，角色心情很开心”）。
- 模型只生成评论、对白、角色建议；不能直接改写游戏数值。
- 主动聊天遵循 8s 冷却，当前模型调用未结束不发第二条；另设置每日 Token 预算和“关闭自动评论”开关。
- 如果 App 完全退出，联网生成不能保证继续进行；本地宠物状态可在下次打开时根据时间差更新。

## 六、全局音乐服务与临时路径

旧版若已经存在音乐播放器，可**复用原来的全局音乐服务**，避免引入第二套音频播放器。当前示例 `MusicRoom` 在 Demo 根页面存活，路由切换时保留；接入旧 App 时要让它与原 App 或 Provider 生命周期一致，否则离开“亲密互动”模块可能停止播放。

用户挑选的音频、视频会被复制进 `ApplicationDocumentsDirectory/intimacy_media/`，避免临时文件失效；可再补一个“媒体清理”入口（当前仅音乐关闭，不会自动清理所有复制的文件）。

## 七、升级与正式签名

保留旧 V3.7 包名、版本升级策略、安卓应用签名（GitHub Secret 中原密钥）、激活验证公钥、角色数据库 Key、Keystore 配置。需要给旧用户覆盖安装时，只能在**原仓库工程中合并上述新模块，并使用原工作流签名构建**，不能用本独立样例的 APK 覆盖。

建议把旧 Flutter 工程 ZIP（去掉私钥和真实 API Key）上传到对话后再做准确合并：可以真正针对 `ui_contacts.dart`、`ui_chat.dart`、`app_controller.dart` 生成增量补丁，并让 GitHub Actions 验证。
