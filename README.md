# 心屿 OS V3.1 — 安卓一机一码激活版

**状态：Flutter 原生源码（非已经编译的 APK）。尚未运行 Flutter 编译、真机安装、服务商真实 API 测试。**

## 对内测用户
1. 从发行者处下载官方签名 APK，安装后打开 App。
2. 首次进入显示 `XY-XXXX-XXXX-XXXX-XXXX-XXXX` 设备编号，可一键复制。
3. 将设备编号发给发行者，领取专属激活码。粘贴到 App，点击「验证并激活」。
4. 激活通过后再去「API 连接」配置个人模型 API Key，给好友绑定 API，开始聊天。
5. 无需账户、无需开发者自建服务器；每台设备只需要激活一次。禁止分发私人 API Key。

## 对发布者（只分享 APK，不分享管理员工具）
1. **将 `心屿OS_私有发码管理员工具.zip` 下载并私下备份**；不要放入公共代码仓库、网盘公开分享或 APK 中。
2. 安卓首次安装请尽量使用固定的 **正式 Release 签名密钥**；重新更换签名密钥，Android ID 可能变化，旧激活码可能失效。
3. 体验者给你设备编号后，解压管理员 ZIP，在 Chrome / Edge 中打开 `管理员_离线发码.html`，粘贴设备号，一键生成激活码，并私发给对应体验者。
4. 可以永久或按 30/90/365 天发行；**离线过期取决于用户本机时钟，非防篡改的可靠计费手段**。
5. 应用对外只有签名验证公钥；签发私钥完全不进入公开源码 ZIP 或 APK。

## 安全范围与限制
- 一机一码可以阻止普通用户把 APK 和自己的激活码一起转发后，其他设备直接使用。
- **无法物理阻止 APK 文件转发**，也不能百分之百防止逆向修改或破解验证逻辑。安装包可被重打包，需要代码混淆、完整性检测等额外手段提高门槛。
- **没有服务器就无法准确统计激活设备数量、实时吊销激活码、避免模拟/克隆环境绕过或保证时间有效性**。如将来需要收款/管理数千用户，可使用托管授权服务，不一定需要自建服务器。
- Android 8+ `ANDROID_ID` 与设备、用户和应用签名密钥有关；恢复出厂设置、更换签名或 Android 系统更新等情况可能需要重新激活。
- 请在隐私说明中告知用户使用设备生成的匿名化编号作为授权绑定依据。展示的是 SHA-256 派生编号，不直接展示原始 Android ID。

## 工程构建
具体通用步骤参考上一版 README 和 `tools/prepare_platforms.py`。在具备 Flutter 和 Android SDK 的环境下：

```bash
flutter create --platforms=android,ios --project-name=xinyu_os --org=com.xinyuos .
python3 tools/prepare_platforms.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

**警告：命令默认生成的 Release APK 不一定具备你可长期维护的正式发布签名。** 大规模分发前必须配置、备份自己的 Android release keystore，并用稳定签名制作安装包。切勿把签名 keystore / password 上传到公共 GitHub。

此项目暂保留 iOS Flutter 页面/网络代码，但一机一码在 iOS 目前使用安装实例编号，尚未按 iPhone 分发标准完成验证。优先 Android；iOS 待后续另行开发验收。

其他功能包括本地 API Key 安全存储、人格导入、私聊、群聊、朋友圈手动授权生成、壁纸和音乐导入等；以实际真机测试为准。
