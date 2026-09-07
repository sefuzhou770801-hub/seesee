<p align="center">
  <img src="Resources/AppIcon-1024.png" width="144" height="144" alt="seesee 应用图标">
</p>

<h1 align="center">seesee</h1>

<p align="center">
  中文 · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  粘贴链接就能看的 macOS 离线视频播放器，自带双语字幕。<br>
  下载完整视频到本地，在干净的原生播放器里观看，没有网页上那些干扰。
</p>

<p align="center">
  <a href="https://github.com/sefuzhou770801-hub/seesee/releases/latest"><strong>下载最新版本</strong></a>
  ·
  <a href="https://github.com/sefuzhou770801-hub/seesee/releases">全部版本</a>
</p>

<p align="center">
  <img src="docs/images/seesee-banner.png" width="720" alt="seesee 宣传图">
</p>

## 愿景：把播放器做成 agent

seesee 不止想做一个更干净的播放器。我们相信下一代播放器是 agentic 的：它理解你正在看的内容，随时可以就此对话。

- **看时问答（内测中）**：播放中任何时刻按 `a` 暂停提问，回答基于当前画面与前后字幕给出；每个问答钉在时间轴上，右栏随时回看。看不懂的图表、没听清的术语、想深挖的论点，不用切出去搜索，在原地问。
- **接下来**：跨视频检索你看过的一切、新视频下载完自动生成预审摘要、盯住你信任的频道自动收集、自动跳过赞助段。

看视频学东西，应该是一场对话，不是单向播放。

## 安装

1. 在[发布页](https://github.com/sefuzhou770801-hub/seesee/releases/latest)下载 zip 并解压。
2. 把 **seesee.app** 拖进「应用程序」。
3. 本版未经 Apple 公证，首次打开请右键点应用选「打开」。

仅支持 Apple Silicon（M 系芯片），需要 macOS 13 或更新版本。yt-dlp、ffmpeg、Deno 已内置，无需安装 Homebrew。

## 添加视频

- 复制任意包含链接的文字，切到 seesee 按 **⌘V**，所有链接一次入队。
- 或粘贴进队列顶部的输入框，或把链接、`.webloc`、`.url` 文件拖到窗口或程序坞图标上。

视频在后台下载，存到本地离线播放。主要面向 YouTube 与 X，yt-dlp 支持的其他无版权保护站点也可以尝试。

## 功能

- **下载即播**：无需等待下载完成，边下边看，断网自动重试
- **双语字幕**：自动抓取中文与英文字幕，原文与译文贴身双行显示，在双语、仅译文、关闭三档间循环，逐视频记忆；也识别与视频文件同名的外置 `.srt` / `.vtt` 字幕（中文 `.zh.srt` 优先作为译文）
- **右栏字幕导航**：句级聚合的全文字幕，点句跳转，章节划分，看过的段落自动折叠
- **续播记忆**：播放位置、倍速、音量、字幕档位、右栏状态全部逐视频保存
- **队列管理**：拖拽排序、右键重命名、看完归档、缩略图、批量提取链接
- **播放体验**：10 秒快进快退、全键盘快捷键、媒体键、全屏、AirPlay、小窗后台播放
- **克制**：下载完成或重新启动后不自动播放，低电量模式自动暂停下载

## 快捷键

| 按键 | 动作 |
| --- | --- |
| `⌘V` | 剪贴板里的链接全部入队 |
| `空格` | 播放或暂停 |
| `←` / `→` | 后退或前进 10 秒 |
| `↑` / `↓` | 倍速加减 0.1× |
| `F` | 全屏 |
| 视频上垂直滚动 | 调节音量 |

## 配置 AI 密钥

解释与目录需要一把模型密钥。点标题栏右侧的齿轮（或菜单栏「seesee › 设置…」，⌘,），选好服务、粘贴密钥即可，粘贴后会自动验证密钥是否可用。密钥只保存在本机，只在你点「解释」或「生成目录」时把那段字幕发给模型。

- Gemini：在 [Google AI Studio](https://aistudio.google.com/apikey) 免费申请，不用绑卡（推荐）。
- Anthropic：在 [Anthropic Console](https://console.anthropic.com/settings/keys) 申请，按用量付费。

也可以用环境变量 `GEMINI_API_KEY` 或 `ANTHROPIC_API_KEY`。

## 数据与隐私

- 下载的媒体：`~/Movies/Replay`
- 队列记录：`~/Library/Application Support/Replay/queue.json`
- 无统计上报、无账号、无云同步
- 不读取浏览器 Cookie
- 不解密 DRM 内容

请只下载你有权观看和保存的内容，站点条款与版权规则仍然适用。

## 从源码构建

```sh
git clone https://github.com/sefuzhou770801-hub/seesee.git
cd seesee
./scripts/build_app.sh
./scripts/test.sh
```

开发构建输出到 `dist/Replay.app` 并安装为 `/Applications/seesee.app`。设 `REPLAY_INSTALL_APP=0` 只构建不安装，设 `REPLAY_LAUNCH_APP=0` 安装后不启动。本地开发时运行工具走 Homebrew 路径：

```sh
brew install yt-dlp ffmpeg deno
```

## 为什么内置 Deno

YouTube 会用 JavaScript 验证机制拦截请求，yt-dlp 需要一个受限的 JavaScript 运行时来求解，Deno 是它的官方推荐。Deno 只在解析视频时由 yt-dlp 调用，与界面渲染无关。同时内置的还有一份便携版 ffmpeg，用于合并音视频流、转换缩略图与字幕。各运行工具的许可声明在应用内 `Contents/Resources` 目录。

## 致谢

本项目基于 [grinich/replay](https://github.com/grinich/replay) 开发，感谢原作者的出色工作。在其离线队列与原生播放器基础上，重做了界面设计，加入双语字幕、右栏字幕导航、下载即播等功能，并全面中文化。

## 许可

[MIT License](LICENSE)。内置的运行组件保留各自的上游许可。
