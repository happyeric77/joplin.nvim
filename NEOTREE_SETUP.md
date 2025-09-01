# 如何在 Neo-tree 中顯示 Joplin Notes

## 問題解決

您遇到的錯誤 `Invalid argument: joplin` 表示 Neo-tree 沒有正確識別我們的 joplin source。

## 解決方案

### 方法 1: 手動註冊 source（推薦）

在您的 Neovim 配置中，在調用 `require('joplin').setup()` **之後**，手動註冊 Neo-tree source：

```lua
-- 1. 首先設置 joplin.nvim
require('joplin').setup({
  api = {
    token_env = 'JOPLIN_TOKEN',
    port = 41184,
    host = 'localhost'
  }
})

-- 2. 手動註冊 Neo-tree source
local ok, sources = pcall(require, "neo-tree.sources")
if ok then
  local joplin_source = require("joplin.ui.neotree")
  sources[joplin_source.name] = joplin_source
  print("✅ Joplin source registered")
end
```

### 方法 2: 在 Neo-tree 配置中包含 joplin

在您的 Neo-tree 設置中明確包含 joplin source：

```lua
require('neo-tree').setup({
  sources = {
    "filesystem",
    "buffers", 
    "git_status",
    "joplin"  -- 加入 joplin source
  },
  -- 其他 Neo-tree 配置...
})
```

### 方法 3: 使用 lazy loading

如果您使用 lazy.nvim 或類似的外掛管理器：

```lua
{
  "your-username/joplin.nvim",
  dependencies = {
    "nvim-neo-tree/neo-tree.nvim"
  },
  config = function()
    require('joplin').setup({
      api = {
        token_env = 'JOPLIN_TOKEN',
        port = 41184,
        host = 'localhost'
      }
    })
    
    -- 確保 Neo-tree 載入後才註冊 source
    vim.defer_fn(function()
      local ok, sources = pcall(require, "neo-tree.sources")
      if ok then
        local joplin_source = require("joplin.ui.neotree")
        sources[joplin_source.name] = joplin_source
      end
    end, 100)
  end
}
```

## 測試步驟

1. 確保 Joplin 桌面應用程式正在運行
2. 確保 Web Clipper 服務已啟用（設定 > General > Enable Web Clipper Service）
3. 設定環境變數：`export JOPLIN_TOKEN=你的token`
4. 重新啟動 Neovim
5. 執行：`:Neotree joplin`

## 檢查連接

您可以先測試 API 連接：

```vim
:lua require('joplin').ping()
:lua require('joplin').list_folders()
```

## 如果仍然不工作

執行以下調試命令：

```vim
" 檢查 source 是否註冊
:lua local sources = require("neo-tree.sources"); for k,v in pairs(sources) do print(k) end

" 手動註冊並測試
:lua local sources = require("neo-tree.sources"); sources.joplin = require("joplin.ui.neotree")
:Neotree joplin
```

請試試方法 1，這應該能解決您的問題！