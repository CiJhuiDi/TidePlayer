# 潮人电台（Tide Player）

在暗潮里直接放网易云歌单 / 专辑。复制链接 → 游戏里按 **F9** → 点「粘贴歌单链接」→ 点歌。

音频是 mod 自带的 `tide_audio.dll`（minimp3 解码 + waveOut 输出），**不需要** Audio Plugin、Darktide Local Server、ffmpeg 或任何外部播放器。

当前版本 **0.3.0**。

## 用法

1. 在网易云里复制歌单或专辑链接（`https://music.163.com/playlist?id=...`、`https://music.163.com/album?id=...`，短链 `163cn.tv/...` 也行）。
2. 游戏里按 **F9** 打开电台。
3. 点右上角「粘贴歌单链接」——读的是剪贴板，不用手动输入。
4. 点列表里的歌开始放。翻页用列表下方的 `<` / `>`。

右栏有两个页签：**频道**（当前歌单的曲目）和**歌单**（保存过的歌单/专辑，点一下切换，右边 `x` 删除）。每加载一个新链接都会自动存进 `cache/playlists.lua`。切换歌单后在歌单页等加载完成，会自动跳回频道页，正在播的那首歌名不会丢。

第一次点某首歌会先把 mp3 下到 `mods/TidePlayer/cache/`（几秒，状态栏显示「正在缓存」），之后同一首秒开。

左栏从上到下：歌名、歌手、五行歌词（当前行高亮，按播放位置走，LRC 自带的 `[offset:]` 也会算）、`0:36 / 2:13` + 进度条、24 段 LED 方块频谱。

**歌词对不上**：ESC → Mod Options 里有「歌词偏移（毫秒）」，正数让歌词晚一点、负数早一点。

放歌 / 暂停时，右上角任务目标下面会多出一条迷你 HUD：收音机图标 + 歌名（长名滚动）+ 方块频谱 + 半透明暗红进度遮罩。任务目标变多盖住它，就在设置里把「迷你 HUD 距顶部」调大。

调音量（快捷键或面板按钮）时，屏幕下方会亮一条 `VOL 70`，1.5 秒后消失。

顶栏「缓存」按钮打开缓存页：显示缓存大小/文件数，可以一键清空（保留歌单列表和上次链接）。

## 设置项（ESC → Mod Options → 潮人电台）

| 设置 | 默认 | 说明 |
|---|---|---|
| 打开电台 | `F9` | 打开 / 关闭面板 |
| 播放 / 暂停 | 未绑定 | 不开面板直接控制 |
| 下一首 | 未绑定 | 同上 |
| 上一首 | 未绑定 | 同上 |
| 音量加 / 音量减 | 未绑定 | 每按一次 ±5% |
| 播放时压低游戏音乐 | 开 | 放歌时把游戏自带音乐淡掉，暂停/停止后恢复 |
| 播放时显示迷你 HUD | 开 | 右上角任务目标下面显示歌名 / 频谱 / 进度 |
| 迷你 HUD 距顶部 | 0 | 额外下移，任务目标变多盖住它就往下调 |
| 长歌名滚动间隔 | 0.12 | 每滚一格用多少秒，越小越快 |
| 歌词偏移（毫秒） | 0 | 歌词比音乐快/慢时微调 |
| 音量 | 70 | 播放器自己的音量，和游戏音乐音量分开 |

控制台命令：`/tideplayer` 打开面板，`/tp <链接或歌单/专辑id>` 直接加载。

## 能放什么、不能放什么

- 能放：歌单/专辑里**不需要付费/会员**的曲子。网易云允许匿名拿到的 mp3，这里都能放。
- 放不了：需要登录、需要会员、或者已经下架的歌。点到这种歌会自动跳过，接着放下面的。
- 进度条只显示，**不能拖**（DLL 还没导出 seek）。
- 部分歌单的歌名/歌手在列表里可能是「未知歌手」——那是 `song/detail` 没返回的条目，不影响播放。

## 已知限制：面板按钮会和背后的游戏 UI 一起响应

暗潮的 UI 热点**不互斥**：`UIManager` 不给每层 UI 做遮挡判断，每个界面各自按鼠标位置响应。原生菜单不穿透是因为打开时下层界面根本不渲染；这个电台面板是**叠加式**的，所以点面板里的按钮时，背后同位置的游戏按钮也可能被触发。

试过延迟关闭、改 `released_callback`、加遮罩，都治不了——根因在热点本身。要彻底解决只能让下层界面停画（动 view 栈，风险大）。**规避办法**：在不会被游戏按钮盖住的位置打开面板。

## 安装

1. DML + DMF（和其他 mod 一样）。
2. 把整个 `TidePlayer` 文件夹放进 `<游戏目录>/mods/`（要带 `tide_audio.dll`，x64）。
3. `mods/mod_load_order.txt` 里加一行 `TidePlayer`。
4. **改完代码要完整重启游戏**（DMF 热重载不清理 hook 注册表，未开开发者模式时也不生效）。

依赖：Windows 自带的 `curl.exe`（Win10 1803+），能访问 `music.163.com`。

## 原理（给改代码的人）

```
电台面板 (TidePlayer_view)
  │  F9
  ▼
TidePlayer.lua      状态机：歌单、当前曲目、循环模式、歌词、压低游戏音乐、缓存统计
  ├─ TidePlayer_playlist.lua    链接解析 + v6 歌单 + song/detail + 专辑接口 + 歌词 LRC
  ├─ TidePlayer_playlists.lua   已保存歌单（cache/playlists.lua）
  ├─ TidePlayer_net.lua         CreateProcessW 隐藏窗口跑 curl
  ├─ TidePlayer_audio.lua       ffi 调 tide_audio.dll（minimp3 + waveOut + FFT 频谱）
  ├─ TidePlayer_json.lua        自己写的 JSON 解码
  ├─ TidePlayer_util.lua        UTF-8/UTF-16、路径、剪贴板、宽度截断、缓存统计
  ├─ TidePlayer_hud.lua         迷你 HUD（HudElementBase）
  └─ TidePlayer_volume_hud.lua  音量提示 HUD
src/
  ├─ tide_audio.c               DLL 源码（解码、waveOut、512 点 FFT 24 段频谱、电平）
  ├─ minimp3.h / minimp3_ex.h   mp3 解码器（public domain）
  └─ build.bat                  重新编译 DLL
```

几个关键决定（都是踩过坑才定的）：

1. **音频不能用 MCI**。暗潮主线程是 MTA，MCI 的 mpegvideo 驱动（DirectShow）在游戏进程里 `open` 会返回 266/267，同样的命令在 PowerShell 里正常。所以自己写 DLL。
2. **下载不能走 io.popen**。那会从游戏进程拉一个带控制台的 cmd.exe，全屏下闪黑框。用 `CreateProcessW` + `CREATE_NO_WINDOW` 起 curl。
3. **curl 必须加 `-g`**。`song/detail?ids=[1,2,3]` 里的 `[]` 会被 curl 当 URL glob，不加 `-g` 直接 exit 3。
4. **歌单接口用 v6**。`/api/v6/playlist/detail` 给全量 `trackIds`，再用 `/api/song/detail?ids=[...]` 补详情（一次最多 500 个 id）。
5. **专辑用 `/api/v1/album/<id>`**。歌在顶层 `songs` 里，字段是 `ar`/`al`/`dt` 新格式；`/api/album/<id>` 返回 -462。
6. **`io_dofile` 不是 `require`**。它每次执行都新建模块实例，有状态的模块必须自己收成单例（`mod._modules`）。
7. **播放位置要用每声道样本数**。`waveOutGetPosition(TIME_SAMPLES)` 返回的是每声道样本数，分母乘了声道数就会慢一半（歌词和进度条整体错位）。
8. **频谱刷新率取决于 buffer 大小**。一块 4096 帧要 93ms 才填一次，频谱看起来一格一格跳；改成 1024 帧 × 16 块后是约 43 次/秒。
9. **View 的 style 按 `style_id` 索引**。只写 `value_id` 的 pass 会被存成 `style_id_N`，`widget.style.xxx` 取不到。
10. **面板居中交给 scenegraph 的 `alignment = "center"`**。它在 init 时就把节点 `world_position` 算好了，widget 坐标再额外加偏移会变成两倍（面板跑到右下角）。

## 已知坑

- 首次点歌要等下载（几秒）；之后走缓存。
- 同时开 MusicBox 之类的音乐会互相抢 `options_music_slider`，二选一。
- 游戏强杀时 DMF 的内存设置可能丢；歌单链接单独存在 `cache/last_url.txt` 里，不受影响。
- 缓存不会自动清理，用面板里的「缓存」页手动清。
- 面板按钮热点会和背后游戏 UI 重叠（见上文「已知限制」）。
