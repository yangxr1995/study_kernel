# windows 包管理 - scoop
## scoop 安装
打开 powershell
为了让PowerShell可以执行脚本，首先需要设置PowerShell执行策略，通过输入以下命令

`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

更改默认的安装目录，添加环境变量的定义，通过执行以下命令完成：

```
$env:SCOOP='E:\scoop'
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
```

安装scoop

`iwr -useb get.scoop.sh | iex`

scoop的目录
- apps——所有通过scoop安装的软件都在里面。
- buckets——管理软件的仓库，用于记录哪些软件可以安装、更新等信息，默认添加main仓库
- cache——软件下载后安装包暂存目录。
- persit——用于储存一些用户数据，不会随软件更新而替换。
- shims——用于软链接应用，使应用之间不会互相干扰，实际使用过程中无用户操作不必细究。

## scoop使用
Scoop的操作命令十分简单，基本结构是scoop + 动词 + 对象，动词就是一个操作动作，如安装、卸载，对象一般就是软件名了（支持通配符*操作），

当然这需要你先打开命令行工具。比如我想安装typora，通过输入scoop install typora即可自动完成软件的官网进入+下载+安装等操作。

以下是一些常用的命令说明：
- search——搜索仓库中是否有相应软件。
- install——安装软件。
- uninstall——卸载软件。
- update——更新软件。可通过scoop update *更新所有已安装软件，或通过scoop update更新所有软件仓库资料及Scoop自身而不更新软件。
- hold——锁定软件阻止其更新。
- info——查询软件简要信息。
- home——打开浏览器进入软件官网。

## 修改源 设置代理
使用Gitee镜像源。在命令行中输入

```
# 更换scoop的repo地址
scoop config SCOOP_REPO "https://gitee.com/scoop-installer/scoop"
# 拉取新库地址
scoop update
```

或者直接修改找到Scoop配置文件，路径

C:\Users\username\.config\scoop\config.json

然后直接修改里面的配置

## 扩展仓库
默认安装Scoop后仅有main仓库，其中主要是面向程序员的工具，对于一般用户而言并不是那么实用。好在Scoop本身考虑到了这一点，添加了面向一般用户的软件仓库extras

Scoop添加软件仓库的命令是

`scoop bucket add bucketname (+ url可选)`

如添加extras的命令是

`scoop bucket add extras`

执行此命令后会在scoop文件夹中的buckets子文件夹中添加extras文件夹。

除了官方的软件仓库，Scoop也支持用户自建仓库并共享，于是又有很多大佬提供了许多好用的软件仓库。

这里强推dorado仓库，里面有许多适合中国用户的软件，添加dorado仓库的命令如下：

scoop bucket add dorado https://github.com/chawyehsu/dorado

此外，若多个仓库间的软件名称冲突，可以通过在软件名前添加仓库名的方式避免冲突，

scoop install dorado/appname

Scoop安装的软件：sudo和scoop-completion，前者可以像debian系Linux临时提权，后者可以自动补全Scoop命令

## 安装常用软件

wezterm neovim neovide git gzip cmake

# 设置windows终端 wezterm + gitbash

## scoop安装 wezterm 和 gitbash

scoop install wezterm git

## 将gitbash中的linux工具加入PATH

获得工具路径

scoop prefix git

C:\Users\CJTX\scoop\apps\git\current

工具路径为

C:\Users\CJTX\scoop\apps\git\current\usr\bin

将其加入PATH

## 修改wezterm配置文件，将bash.exe设置为启动程序


```lua
-- 加载 wezterm API 和获取 config 对象
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-------------------- 颜色配置 --------------------
config.color_scheme = 'GitHub Dark'
config.window_decorations = "RESIZE"
config.enable_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.show_tab_index_in_tab_bar = false
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = false

-- 设置窗口透明度
config.window_background_opacity = 0.9
config.macos_window_background_blur = 10
-- config.background = {
--   {
--     source = {
--       File = 'D:/壁纸/wallhaven-858lz1_2560x1600.png',
--     },
--   }
-- }

config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.8,
}

-- 设置字体和窗口大小
config.font_size = 12
config.initial_cols = 140
config.initial_rows = 30

-- 设置默认的启动shell
config.set_environment_variables = {
    COMSPEC = 'C:\\Users\\CJTX\\scoop\\apps\\git\\current\\usr\\bin\\bash.exe',
    -- COMSPEC = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
}

-------------------- 键盘绑定 --------------------
local act = wezterm.action

-- config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }
config.keys = {
	{
		key = "1",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "1"}),
		}),
	},
	{
		key = "2",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "2"}),
		}),
	},
	{
		key = "3",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "3"}),
		}),
	},
	{
		key = "4",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "4"}),
		}),
	},
	{
		key = "5",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "5"}),
		}),
	},
	{
		key = "6",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "6"}),
		}),
	},
	{
		key = "7",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "7"}),
		}),
	},
	{
		key = "8",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "8"}),
		}),
	},
	{
		key = "9",
		mods = "ALT",
		action = wezterm.action.Multiple ({
			wezterm.action.SendKey({mods = "CTRL", key = "b"}),
			wezterm.action.SendKey({key = "9"}),
		}),
	},


  { key = 'q',          mods = 'ALT',         action = act.QuitApplication },
}

return config
```



