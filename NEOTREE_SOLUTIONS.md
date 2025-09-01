# Neo-tree 問題解決方案

## 問題診斷

你遇到 "❌ Neo-tree not found" 錯誤，這表示你的 Neovim 環境中沒有安裝 Neo-tree 外掛。

## 解決方案

### 方案 1: 安裝 Neo-tree（推薦）

在你的 Neovim 外掛配置中添加 Neo-tree：

```lua
return {
  -- Neo-tree 外掛
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      require("neo-tree").setup({
        sources = { "filesystem", "buffers", "git_status" }
      })
    end
  },
  
  -- 你的 joplin.nvim 外掛
  {
    dir = "~/Projects/side-projects/joplin.nvim",
    name = "joplin.nvim",
    dependencies = { "nvim-neo-tree/neo-tree.nvim" }, -- 確保 Neo-tree 先載入
    config = function()
      require("joplin").setup({
        api = {
          token_env = "JOPLIN_TOKEN",
          port = 41184,
          host = "localhost",
        }
      })
      -- register_neotree() 會自動在 setup() 中調用
    end,
  },
}
```

### 方案 2: 不使用 Neo-tree，使用內建瀏覽器

如果你不想安裝 Neo-tree，可以使用我們提供的內建瀏覽器：

```lua
return {
  {
    dir = "~/Projects/side-projects/joplin.nvim",
    name = "joplin.nvim",
    config = function()
      require("joplin").setup({
        api = {
          token_env = "JOPLIN_TOKEN",
          port = 41184,
          host = "localhost",
        }
      })
    end,
  },
}
```

然後使用以下命令：

```vim
:JoplinPing          " 測試連接
:JoplinFolders       " 列出資料夾
:JoplinBrowse        " 瀏覽筆記
```

### 方案 3: 手動打開筆記

你也可以直接使用 Lua 命令來打開筆記：

```vim
" 列出所有筆記
:lua require('joplin').list_notes()

" 打開特定筆記（需要筆記 ID）
:lua require('joplin.utils.buffer').open_note('your_note_id')
```

## 測試步驟

1. 重新啟動 Neovim
2. 執行 `:JoplinPing` 測試連接
3. 如果安裝了 Neo-tree，執行 `:Neotree joplin`
4. 如果沒有安裝 Neo-tree，執行 `:JoplinBrowse`

## 推薦

我建議使用**方案 1**，安裝 Neo-tree，因為它提供了最完整的功能，包括：
- 樹狀結構瀏覽
- 拖拽操作
- 快捷鍵支持
- 視覺化的文件管理

選擇哪個方案都可以，主要看你的需求！