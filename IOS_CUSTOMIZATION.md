# iOS 文件夹与最近添加版本

## 来源与状态

基于 https://github.com/kuilei0926/FeiNiuMusic 的第三方 Flutter 客户端，不是飞牛官方 iOS 源码。
保留上游代码及来源说明。本地修改尚未通过 Flutter 分析、iOS 编译或 NAS 真机验证。
本机 Windows 未安装 Flutter/Dart，也没有 Xcode；目录中的源码不能直接安装到 iPhone。

## 本次修改

- 歌曲页面增加「最近添加」入口，固定使用服务端 `createdAt,desc` 分页。
- 首页「最新歌曲」更名为「最近添加」，查看全部进入固定排序的页面。
- 最近添加的分页及播放队列使用同一排序，不读取或覆盖普通曲库的排序偏好。
- 顶栏增加文件夹入口，空曲库也可以访问；未开启增强服务时显示说明并可跳转设置。
- 复用已有 NAS 目录浏览、目录搜索、子目录和平铺播放能力。
- iOS 最低版本统一为 15.0，增加局域网用途说明和本地网络 ATS 设置。
- 添加手动触发的 macOS iOS 验证工作流，沿用上游锁定的 Flutter commit。

## 文件夹依赖

在 NAS 安装并配置 https://github.com/kuilei0926/FnMusicEnhance ，然后在客户端
「设置 → 元数据管理」开启服务端增强。现有客户端通过 NAS 地址下的
`/music-enhance/music/api/v1/folder/list` 请求目录，并使用飞牛音乐登录 token。
需要确认 NAS 上的反向代理提供此路径，不能仅假定开放 38200 端口就能工作。

这里的文件夹是 NAS 曲库中的实际目录。没有新增创建、移动或删除 NAS 文件的能力，
也没有实现 iPhone 本地文件导入。「最近添加」指服务端入库时间，不是歌曲发行日期。

## Mac 构建与验证

安装 Xcode、CocoaPods 及上游指定 Flutter 版本后，在项目根目录执行：

```sh
flutter pub get
dart format lib/pages/songs/songs_page.dart lib/pages/home/home_page.dart
flutter analyze
flutter test
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

在 Xcode 选择自己的开发团队、设置唯一 Bundle Identifier，再连接 iPhone 编译运行。
未签名的 Runner.app 不是可直接安装的 IPA。仓库已附手动 CI，但尚未上传或运行。
上游包含 Android 专用插件和平台通道；完整 iOS 兼容性以实际编译和运行结果为准。

验收项目：

1. 使用实际 NAS 登录；允许局域网访问；检查 HTTPS、局域网 IP 和远程连接。
2. 普通歌曲列表按歌名升序，再打开最近添加；确认新入库歌曲在最前，返回后普通列表排序不变。
3. 曲库超过 100 首时加载下一页，确认顺序连续；点击播放并检查后续播放队列。
4. 新增一首音乐并完成 NAS 扫描，下拉刷新最近添加，确认新曲出现。
5. 未开启增强服务时打开文件夹，确认提示及设置跳转；开启后检查多层目录、返回、搜索、平铺与播放。
6. 检查空目录、无访问权限、服务未安装及网络断开时的反馈。
7. 验证锁屏控制、后台播放和真实音频格式。

上游 README 提到继承 NagoMusic 协议，但 GitHub 未识别到仓库许可证；
公开分发前应核实上游授权及应用名称、图标使用条件。
