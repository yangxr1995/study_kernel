# nvim的安装
1. 安装新版本的cmake

2. 下载nvim源码

3. 修改dns 为8.8.8.8，否则编译nvim时，下载资源会出错

4. 编译nvim

# nvim的配置

```shell
# nvim的配置目录
~/.config/nvim

# nvim读取的第一个配置
~/.config/nvim/init.lua

# 通常init.lua这样写
require "user.options"
require "user.keymaps"
require "user.plugins"

# 表示
.
├── init.lua
├── lua
   └── user
       ├── keymaps.lua
       ├── options.lua
       └── plugins.lua
```

# 插件管理

编辑 `~/.config/nvim/lua/user/plugins.lua`

```shell
return packer.startup(function(use)
    ... // 在这里添加需要的插件
end)
```

进行插件的更新和编译(编译会生成一个lua文件以快速加载插件)
```shell
:PackerSync
```

# 自动补全
使用插件
```shell
  use "hrsh7th/nvim-cmp" -- The completion plugin
```

编辑
```shell
/root/.config/nvim/lua/user/cmp.lua
```

```lua
-- 定义符号
      vim_item.menu = ({
        nvim_lsp = "[LSP]",
        nvim_lua = "[NVIM_LUA]",
        luasnip = "[Snippet]",
        buffer = "[Buffer]",
        path = "[Path]",
      })[entry.source.name]

-- 定义补全源
  sources = {
    { name = "nvim_lsp" },
    { name = "nvim_lua" },
    { name = "luasnip" },
    { name = "buffer" },
    { name = "path" },
  },

```

# lsp
使用插件
```lua
  use "williamboman/mason.nvim" -- simple to use language server installer
```

安装插件
```
:MasonInstall
```
找到要安装的插件，按 I

查看LSP信息，按回车

禁用LSP，按 X


