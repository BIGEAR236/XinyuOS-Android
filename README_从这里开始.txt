心屿 OS V3.1 | 安卓 APK 最简构建包
======================================================
重要：这个 ZIP 是源代码和云端构建配置，不是 APK。本次环境没有 Flutter/Android SDK，也无法联网获取编译工具，无法本地编译 APK。

如果你只想先看 APK 是否能装：
1) 建立 GitHub 私人仓库，上传此 ZIP 解压后的所有文件（包括 .github 目录）。
2) 进入仓库 Actions，选择「生成 Android 测试 APK（无需签名密钥）」→ Run workflow。
3) 绿色成功后点击工作流下方 Artifacts 的 XinyuOS-仅测试版.apk 下载。
测试版构建的签名每次可能改变，不可长期用作对外正式发布，否则升级、设备编号与激活可能受影响。

给别人长期分发：
1) 把这个 ZIP 解压内容上传 GitHub 私人仓库。
2) 私下保管另一份单独提供的「Android_Release_Signing_PRIVATE.zip」，千万不要把它的私钥文件上传 GitHub 代码仓库。
3) GitHub 仓库 Settings → Secrets and variables → Actions → New repository secret
   Name 填写：XY_RELEASE_SIGNING_BUNDLE
   Secret 复制私有 ZIP 中 GitHub_机密_XY_RELEASE_SIGNING_BUNDLE.txt 的全部一行。
4) Actions → 「生成心屿OS正式签名 APK」→ Run workflow。
5) 构建成功后，从 Artifacts 下载 XinyuOS-v3.1-release.apk。
6) 先在真实安卓手机测试激活、API 连接、聊天、重启后的数据保留；通过后再把 APK 上传蒲公英或网盘供内测者下载。

应用仍然没有自己的服务器。真实模型需要联网，API Key 由用户自行填写；管理员离线发码工具请继续单独保管。
友情提醒：代码通过本地静态检查，未运行 Flutter 编译或真实 Android 真机测试，所以不能保证云端第一次编译即成功。
