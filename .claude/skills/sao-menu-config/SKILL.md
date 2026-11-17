---
name: sao-menu-config
description: 修改 SAO Menu（SAO 菜单）的配置文件 ~/.config/sao-menu/config.json。用户要求在 SAO 菜单里添加、删除、改名、移动条目，或调整它的热键、手势、音效、启动动画时使用。
---

# 调整 SAO Menu 配置

SAO Menu 是一个 macOS 快捷菜单：一列圆形图标，逐级展开面板，条目可以打开文件、应用、网页或在终端执行命令。全部内容由 `~/.config/sao-menu/config.json` 决定，程序在每次呼出菜单时重新读取它。

## 步骤

1. **读取** `~/.config/sao-menu/config.json`。文件不存在说明程序还没启动过：请用户先启动一次 SAO Menu 生成默认配置，然后停在这里。
2. **落实目标**：把用户的要求对应到具体条目和字段。用户说的文件夹、文件、应用、网址，逐个确认真实存在（路径用 `ls` 展开 `~` 后检查；应用在 `/Applications`、`/System/Applications`、`~/Applications` 里找 `.app`）。用户没说放在哪里时，放进含义最接近的现有图标下；没有合适的才新建图标。完成标准：每个要写入的路径、应用名、网址都核对过，位置已确定。
3. **备份**：`cp ~/.config/sao-menu/config.json ~/.config/sao-menu/config.agent-backup.json`。
4. **修改**：用 Edit 工具做最小改动，保持其余内容、键的顺序和缩进原样。
5. **校验**：运行 `python3 <本 skill 目录>/validate.py`。完成标准：输出 `OK`，且每条 `warning` 都已修正或向用户说明原因。校验失败时程序会沿用旧配置并在菜单上报错，所以这一步必须通过。
6. **告知用户**：列出改了哪些条目，说明下次呼出菜单生效、无需重启。若改了 `hotkey`、`mouseGesture` 或 `trackpad`，它们同样要到下一次呼出才生效，而呼出只能用旧方式，所以改完后运行 `open -b local.sao-menu` 替用户呼出一次菜单使其立即生效，并告诉用户屏幕上弹出的菜单是这个原因。

## 配置结构

```json
{
  "hotkey": "alt+s",
  "sound": true,
  "volume": 0.7,
  "intro": true,
  "welcome": "Welcome to Sword Art Online!",
  "mouseGesture": "right",
  "trackpad": "tap4",
  "menu": [
    {
      "icon": "folder",
      "label": "PROJECTS",
      "items": [
        { "label": "sao-menu", "action": { "type": "open", "path": "~/my/sao-menu" } },
        { "label": "More", "items": [ ... ] }
      ]
    }
  ]
}
```

### 条目

`menu` 里的每一项是一个圆形图标；`items` 可以任意嵌套，每一层是一个面板。

- 每个条目要么有 `items`（子菜单），要么有 `action`（执行动作），二者取其一。
- `label`：显示名称。面板宽度有限，保持在 22 个字符以内。最外层的 `label` 是面板标题，现有配置用大写英文，新增时沿用。
- `icon`：最外层必须写。内层可省略，程序会按动作类型自动选择；`app` 类型省略时显示应用自己的图标，所以应用条目不写 `icon`。
- 最外层图标控制在 6 个以内，再多会超出小屏幕的高度。

### 动作

| `type` | 字段 | 行为 |
| --- | --- | --- |
| `open` | `path`，可选 `app` | 打开文件或文件夹；`app` 指定用哪个应用打开 |
| `app` | `app` | 启动应用 |
| `url` | `url`，可选 `app` | 打开网页；`app` 指定浏览器 |
| `terminal` | 可选 `cwd`、`command`、`app` | 新开终端窗口，在 `cwd`（默认 `~`）执行 `command`，之后留在 shell；`app` 换终端，如 `iTerm` |
| `system` | `name` | 执行一个 macOS 系统功能，见下 |
| `settings` | 无 | 打开设置窗口 |
| `quit` | 无 | 确认后退出程序 |

- `system` 的 `name`：`lock`（锁屏）`screensaver`（屏保）`displaySleep`（关显示器）`sleep`（睡眠）`screenshot`（截图工具）`darkMode`（切换深浅色）`mute`（切换静音）`missionControl`（调度中心）`emptyTrash`（清倒废纸篓，务必加 `confirm`）`restart` `shutdown` `logout`（重启、关机、退出登录，系统会自己弹确认框）。注意 `logout` 是退出 macOS 用户，退出 SAO Menu 本身用 `quit`。
- `app` 的值可以是应用名（`Visual Studio Code`）、完整路径或 bundle id。
- 路径支持 `~`。
- `command` 在交互式 zsh 里执行，用户的别名和 PATH 可用；多条命令用换行或 `&&` 连接。
- 任何动作都可以加 `"confirm": "提示文字"`，执行前弹出确认框。会删除、覆盖、推送或花钱的终端命令一律加上。

### 图标

内置名称：`user` `users` `message` `map` `gear` `folder` `file` `star` `home` `download` `desktop` `grid` `list` `code` `terminal` `globe` `image` `music` `book` `heart` `lock` `moon` `power` `camera` `trash` `volume` `refresh` `logout` `sword`。也可以写一个 emoji 或一两个字。

### 通用项

- `hotkey`：`cmd` / `alt` / `ctrl` / `shift` 加一个键，用 `+` 连接，如 `ctrl+alt+space`。F1–F12 可以单独使用。
- `sound`（布尔）、`volume`（0–1）、`intro`（启动动画，布尔）、`welcome`（启动动画结尾的欢迎语）。
- `mouseGesture`：`right`（按住右键向下划）/ `both`（同时按住左右键向下划）/ `off`。
- `trackpad`：`tap3` / `tap4` / `tap5`（三、四、五指轻点）/ `off`。
