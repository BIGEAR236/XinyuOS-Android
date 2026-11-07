# Android 系统语音识别服务检查

用户设备提示 `PlatformException(recognizerNotAvailable, Speech recognition not available on this device, null)`。

这说明 App 查询不到可用的 Android 语音识别服务，可能是：

- AndroidManifest.xml 没有添加 Android 11 (API 30)+ 的服务可见性声明；
- 手机未安装、被停用、未选择系统识别提供方（Google 或手机厂商的 Speech Recognition）；
- 麦克风权限未允许；少数定制安卓系统根本没有识别提供方。

请在 **`android/app/src/main/AndroidManifest.xml`** 的 `<manifest>` 直接子节点（`<application>` 外）确认：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<queries>
    <intent>
        <action android:name="android.speech.RecognitionService" />
    </intent>
</queries>
```

若已有 `<queries>` 或相同权限，**合并节点，不要重复插入，也不要覆盖完整 Manifest**。不要删除原 `applicationId`、签名或其他 Android 配置。

手机端：设置 → 应用 → 小雨机 → 权限 → 麦克风 → 允许；检查手机“语音识别 / 语音输入”默认服务。若没有系统服务，尝试启用/安装兼容的 Google 或厂商语音识别服务（视设备可用性而定）。缺少服务时，文字仍可与原模型聊天。本补丁不能在没有引擎的设备上凭空实现离线语音识别；之后可另外集成离线模型（例如 sherpa-onnx），但安装包会增大。

官方依据：https://developer.android.com/reference/android/speech/SpeechRecognizer 和 https://pub.dev/packages/speech_to_text
