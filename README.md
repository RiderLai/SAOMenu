# SAO Menu

一个 SAO 风格的 macOS 快捷菜单：按热键在鼠标位置呼出一列圆形图标，逐级展开列表，打开文件夹或文件。

## 构建与运行

```bash
./build.sh run     # 编译出 build/SAOMenu.app 并启动
```

需要 Xcode 命令行工具（`swiftc`），无其他依赖。应用常驻菜单栏，没有 Dock 图标。

## 操作

| 操作 | 效果 |
| --- | --- |
| `⌥S`（可改） | 在鼠标位置呼出 / 收起菜单 |
| 鼠标：同时按住左右键向下划 | 呼出菜单（可在设置里关闭） |
| 触控板：四指轻点 | 呼出 / 收起菜单（可改为三指、五指或关闭） |
| 点击圆形图标 | 选中并展开列表，再点一次收起 |
| 点击列表项 | 展开下一级，或执行动作 |
| `↑` `↓` | 在当前层移动 |
| `→` / `Enter` | 进入下一级；`Enter` 在叶子项上执行动作 |
| `←` / `Backspace` | 返回上一级 |
| `Esc` / 点击空白处 | 关闭 |

再次启动应用（例如 `open build/SAOMenu.app`）也会呼出菜单。

## 设置窗口

点菜单栏图标 →「设置…」，或在菜单里选 SYSTEM → Settings，打开图形化的设置窗口：

- 左侧是菜单树：添加、添加子项、上移、下移、删除。最外层每一项是一个圆形图标。
- 右侧编辑选中的项：名称、图标、类型（子菜单 / 打开文件或文件夹 / 打开应用 / 打开网页 / 终端命令 / 退出等）以及对应的路径、网址、命令，路径和应用可以用系统的选择框挑选。
- 「通用设置」里改热键（点击后直接按组合键）、音效、音量、启动动画和欢迎语。
- 修改自动保存，下次呼出菜单生效；每次打开设置窗口时，当时的配置会备份到 `~/.config/sao-menu/config.backup.json`。

## 配置文件

也可以直接编辑配置文件。

配置文件在 `~/.config/sao-menu/config.json`，首次启动时自动生成。改完保存即可，下次呼出菜单时生效。

```json
{
  "hotkey": "alt+s",
  "sound": true,
  "menu": [
    {
      "icon": "folder",
      "label": "PROJECTS",
      "items": [
        { "label": "sao-menu", "action": { "type": "open", "path": "~/my/sao-menu" } },
        { "label": "用 VS Code 打开", "action": { "type": "open", "path": "~/my/sao-menu", "app": "Visual Studio Code" } },
        { "label": "更多", "items": [
          { "label": "笔记.md", "action": { "type": "open", "path": "~/Documents/notes.md" } }
        ] }
      ]
    }
  ]
}
```

- `menu` 的每一项是一个圆形图标；`items` 可以任意嵌套，每多一层就多一个面板。
- `action.type`：
  - `open`：打开 `path` 指向的文件夹或文件，可选 `app` 指定用哪个应用打开。
  - `app`：启动应用，如 `{ "type": "app", "app": "Music" }`。
  - `url`：打开网页，如 `{ "type": "url", "url": "https://github.com" }`，可选 `app` 指定浏览器。
  - `terminal`：新开终端窗口，在 `cwd`（默认 `~`）下执行 `command`，执行完留在 shell 里；两者都可省略。可选 `app` 换成其他终端，如 `"iTerm"`。例：`{ "type": "terminal", "cwd": "~/my/sao-menu", "command": "./build.sh run" }`。
  - `settings`：打开设置窗口。
  - `quit`：退出 SAO Menu，会先弹出确认框，确认后播放登出动画。
- 二次确认：任何动作都可以加 `"confirm": true` 或 `"confirm": "提示文字"`，执行前弹出确认框（`Enter` / `Y` 确认，`Esc` / `N` 取消）。
- `app` 类型的条目不写 `icon` 时，自动显示该应用自己的图标。
- `app` 的写法：应用名（`"Visual Studio Code"`）、完整路径（`"~/Applications/Foo.app"`）或 bundle id（`"com.apple.Safari"`）。
- `hotkey`：`cmd` / `alt` / `ctrl` / `shift` 加一个键，如 `ctrl+alt+space`、`cmd+shift+m`。
- `mouseGesture`：`true` 开启鼠标手势。授予「辅助功能」权限后，手势中的按键不会传给下面的应用；未授权时也能触发，但可能同时弹出右键菜单。
- `trackpad`：触控板手势，`off` / `tap3` / `tap4` / `tap5`（三、四、五指轻点）。
- `intro`：启动动画开关，默认 `true`；设为 `false` 则启动后直接弹出菜单。动画播放中按任意键或点击可跳过。
- `welcome`：启动动画结尾的欢迎语，默认 `Welcome to Sword Art Online!`。
- `sound` / `volume`：音效开关和音量（0–1，默认 0.7）。
- 自定义音效：把音频文件放进 `~/.config/sao-menu/sounds/`，文件名为 `open` `close` `select` `move` `back` `launch` `error`（菜单）或 `dive` `tick` `welcome` `warp`（启动动画）之一，扩展名 `wav` / `mp3` / `m4a` / `aiff`，下次呼出菜单时生效；没有对应文件时用内置的合成音。
- `icon`：内置名称 `user users message map gear folder file star home download desktop grid list code terminal globe image music book heart logout sword`，或者直接写一个 emoji / 文字。列表项不写 `icon` 时按路径自动选择。
