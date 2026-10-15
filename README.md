# F50 Monitor iOS 2.5 自签名构建

本目录是构建材料，尚不是 IPA。只有 macOS 编译成功并通过校验后才会生成 IPA。

## 源码依据

- 上游：<https://github.com/koldllc/f50-monitor>
- 固定源码提交：`741984b434f5ee93578bdcc34c32490e975f5595`，2026-08-27。
- 这是主分支删除 iOS 工程之前最后保留完整 iOS 工程的公开提交，使用该提交随附的 MIT 许可证。
- 应用版本：2.5，内部构建号：9；最低 iOS：16.0；设备架构：arm64。
- 保留上游 iPhone 应用、Widget 扩展及 F50Core 框架，不混用删除后的主分支核心代码。
- 本构建材料没有加入应用功能修改。

## GitHub Actions 构建

将本目录内的 README、UPSTREAM-LICENSE、两个脚本和 `.github/workflows/build-ios-unsigned.yml` 放入你控制的构建仓库。
在 Actions 中手动运行 **Build F50 Monitor iOS 2.5 unsigned**。
流程从公开上游固定提交获取源码，运行已有 Swift 单元测试，生成 Xcode 工程，执行 iPhoneOS Release 编译，再验证 IPA。
流程仅有 `contents: read` 权限；产物保存为 Actions artifact，保留 30 天；没有 Release 发布步骤。
构建无需 Apple ID、证书、描述文件或设备密码。

下载 `F50-Monitor-iOS-2.5-unsigned` 产物并解压，即可得到 IPA、SHA-256 校验文件、来源记录和包结构验证报告。
日志在单独的 `F50-Monitor-iOS-2.5-build-logs` 产物中。

## 在 Mac 上构建

安装 Xcode 与 XcodeGen，将配套 `f50-monitor-ios-2.5-source.zip` 解压，然后运行：

```bash
bash build-unsigned.sh /绝对路径/解压后的源码 /绝对路径/输出目录
```

## 自行签名与安装

IPA 是未签名真机包，需使用自己的有效 Apple 签名身份和描述文件，或支持个人 Apple ID 的自签工具。
应用包含 Widget 扩展与共享框架，签名工具需要正确处理嵌入组件。
主应用 Bundle ID：`com.kold.f50.monitor.ios`。
扩展 Bundle ID：`com.kold.f50.monitor.ios.widget`。
Widget 共享数据使用 App Group：`group.com.f50.monitor`；自己的签名配置必须正确支持或映射该组，才能保证小组件的数据共享。
免费个人账号对扩展与 App Group 的支持取决于实际签名工具和账户能力，不能仅凭 IPA 编译通过保证小组件可用。

安装后连接 F50/V50 的 Wi-Fi，在初始设置中填写设备实际地址和后台密码，并允许“本地网络”。
后台刷新由 iOS 调度，不能保证持续实时刷新。此构建流程不执行设备设置更改、短信发送、反馈提交或真实设备测试。

## 验证范围

流程成功可以证明：上游已有单元测试通过、Xcode 为 iPhoneOS 编译成功、包内主应用/Widget/框架齐全、Mach-O 为 arm64 iOS、未加密且没有签名材料。
无法据此证明：个人签名已完成、iPhone 已安装成功，或你的具体 F50 固件所有功能都兼容。
