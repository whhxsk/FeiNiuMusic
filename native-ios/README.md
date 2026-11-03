# 牛听 · 原生 iOS 飞牛音乐客户端

独立 SwiftUI 实现，iOS 16+。不引入旧 Flutter App 的代码或插件，不调用 FnMusicEnhance。

功能：直连 NAS 登录、按入库时间倒序的最近添加、全部歌曲搜索、客户端目录索引、目录内递归搜索、播放队列、进度控制、后台播放与锁屏控制、可选飞牛 MP3 转码。

目录通过 `/music/api/v1/track/list` 与 `/track/metadata?guid=...` 的 `audioSpec.path` 建立。
只有服务器实际返回路径的已入库歌曲才能显示；空目录、未入库文件不会显示。
首次索引应保持前台运行，可暂停；再次同步会复用已有路径。歌曲移动后可重新读取全部路径。
缺失路径、权限错误和网络错误在界面显示，不伪造目录，也不要求安装增强插件。

输入 NAS 的可直连 HTTP/HTTPS 地址和飞牛用户名、密码。当前不实现 FN Connect/FNID 自动探测、
中继、安全码、第三方证书放行、歌词、离线下载、目录新建/删除/移动。
密码只用于当前登录请求，持久化登录令牌使用 iOS Keychain。
为支持局域网 HTTP NAS，声明 ATS HTTP 例外；远程使用有效 HTTPS 地址。

构建：安装 Xcode 与 XcodeGen，在此目录运行 `xcodegen generate`。
GitHub Actions 执行模拟器 XCTest 与 iOS Release 编译，生成未签名 IPA。
使用 Sideloadly 签名安装，开发者模式按系统要求开启。

验证边界：自动化测试覆盖目录隔离、路径缺失、中文目录、CUE 路径、时间与地址解析。
尚无用户真实 NAS 的接口响应与真机联调证据，不能保证每个飞牛音乐版本都返回路径或支持转码。
播放与 NAS 接口协议参考项目： https://github.com/kuilei0926/FeiNiuMusic （仅用于确认接口字段）。
