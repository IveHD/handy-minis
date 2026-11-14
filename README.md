# ClipStack

菜单栏里的 Mac 剪切板队列。复制过的文本、图片和文件会按时间留下来，按 **⌘⇧C** 唤起列表，选一条贴回刚才的应用。

## 运行

需要 macOS 14。

```bash
./build.sh run
```

菜单栏会出现剪贴板图标。应用没有 Dock 图标。

## 怎么用

1. 像平时一样复制（⌘C）。最近 40 条会记在队列里，重复内容会回到最上面。
2. 按 **⌘⇧C** 打开「最近复制」。要更换快捷键，点菜单栏图标里的「设置…」。
3. 用 ↑↓ 或 ⌘1–⌘9 选择，回车粘贴到唤起前的应用。
4. **⌘↩** 只放回剪切板，不粘贴。**⌫**（搜索框为空时）删除当前条。**esc** 关闭。

也可以点菜单栏图标里的「打开队列」。

第一次需要在「辅助功能」里允许 ClipStack，回车才能替你按下 ⌘V。已经允许过的话，再次打开不会再弹出系统请求。没允许时，选中的内容仍然会放回剪切板，需要自己粘贴。

## 数据

历史在 `~/Library/Application Support/ClipStack/`。图片单独存在 `images/`。以前存在 `CopyQueue` 目录里的记录会在第一次打开时搬过来。

登录时启动可以在菜单栏图标里打开。这项需要通过 `open ClipStack.app` 启动的正式应用包，不要只运行裸可执行文件。

## 更新与使用统计

首次构建先执行 `scripts/setup-sparkle.sh` 下载固定版本 Sparkle 2.9.6 并校验 SHA-256，然后执行 `./build.sh`。更新地址未配置时不启动更新检查。统计 App Key 未配置时不发送事件。

配置通过构建时环境变量写入应用 Info.plist。

- `UPDATE_FEED_URL` 为 HTTPS appcast.xml 地址。
- `SPARKLE_PUBLIC_KEY` 为 `.build/sparkle/bin/generate_keys` 生成的公钥。私钥保留在发布机器 Keychain，后续更新必须使用同一密钥。
- `APTABASE_APP_KEY` 为 Aptabase 的 EU 或 US 区域 App Key。
- `APP_VERSION` 为显示版本，例如 `1.1.0`。
- `APP_BUILD` 为严格递增构建号，例如 `2`。

菜单栏可关闭「发送匿名使用统计」。当前通过 Aptabase HTTP 接口发送启动、打开队列、请求粘贴三个事件，参数仅包含系统、语言、应用版本与临时会话标识，每类事件每进程最多每小时一次。因此功能事件统计表示限频后的使用情况，不能直接当作精确操作次数或去重日活。网络失败丢弃事件，不保存离线队列。开发构建标记为测试数据。复制内容、图片、文件路径和目标应用名称均不进入事件。

### 正式打包

准备 Developer ID Application 签名证书和 `notarytool` Keychain profile，然后设置上述变量及 `SIGN_ID`、`NOTARY_PROFILE`、`DOWNLOAD_URL_PREFIX`，执行 `scripts/package-release.sh`。下载前缀示例为 `https://github.com/OWNER/REPO/releases/download/v1.1.0/`。脚本完成构建、签名、公证、装订和 Sparkle 清单签名。当前构建只包含本机 CPU 架构。

每次产物存放于独立的 `dist/版本-构建号/` 目录。将生成的 ZIP 上传至对应 GitHub Release，将 该目录内的 `appcast.xml` 发布至 GitHub Pages 的固定地址。默认提供完整版本更新。发布前用旧版应用验证检查、下载、安装和重启全流程。

查询各版本附件累计下载量需要已安装 GitHub CLI，然后执行 `scripts/download-stats.sh OWNER/REPO`。输出列依次为版本、文件名、下载次数，包含重复下载和更新下载。
