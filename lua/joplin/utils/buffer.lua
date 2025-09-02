local api = require("joplin.api.client")
local M = {}

-- 儲存 buffer 到 note 的映射關係
local buffer_note_map = {}
local note_buffer_map = {}

-- 獲取或創建筆記 buffer
function M.open_note(note_id, open_cmd)
  -- 如果傳入的是 table，提取 id
  if type(note_id) == "table" then
    note_id = note_id.id
  end
  
  if not note_id then
    vim.notify("Note ID is required", vim.log.levels.ERROR)
    return
  end
  
  open_cmd = open_cmd or "edit"
  
  -- 檢查是否已經有該筆記的 buffer
  local existing_bufnr = note_buffer_map[note_id]
  if existing_bufnr and vim.api.nvim_buf_is_valid(existing_bufnr) then
    -- buffer 已存在，直接打開
    if open_cmd == "edit" then
      vim.api.nvim_set_current_buf(existing_bufnr)
    elseif open_cmd == "split" then
      vim.cmd("split")
      vim.api.nvim_set_current_buf(existing_bufnr)
    elseif open_cmd == "vsplit" then
      vim.cmd("vsplit")
      vim.api.nvim_set_current_buf(existing_bufnr)
    elseif open_cmd == "tabnew" then
      vim.cmd("tabnew")
      vim.api.nvim_set_current_buf(existing_bufnr)
    end
    return existing_bufnr
  end
  
  -- 從 Joplin 獲取筆記內容
  local success, note = api.get_note(note_id)
  if not success then
    vim.notify("Failed to fetch note: " .. note, vim.log.levels.ERROR)
    return
  end
  
  -- 創建新 buffer
  local bufnr = vim.api.nvim_create_buf(true, false)  -- listed=true, scratch=false
  if not bufnr or bufnr == 0 then
    vim.notify("Failed to create buffer", vim.log.levels.ERROR)
    return
  end
  
  -- 設置 buffer 內容
  local lines = {}
  if note.body then
    lines = vim.split(note.body, "\n", { plain = true })
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  
  -- 設置 buffer 屬性，為 Copilot 創建更標準的環境
  -- 使用當前工作目錄而不是 /tmp，讓 Copilot 認為這是項目中的檔案
  local safe_title = (note.title or "Untitled")
    :gsub("[^%w%s%-_%.%+]", "_")  -- 保留更多安全字符
    :gsub("%s+", "_")             -- 空格轉下劃線
    :sub(1, 50)                   -- 限制長度避免過長的檔名
  
  -- 使用隱藏的 .joplin 目錄在當前工作目錄中
  local cwd = vim.fn.getcwd()
  local joplin_dir = cwd .. "/.joplin"
  
  -- 創建目錄（如果不存在）
  vim.fn.mkdir(joplin_dir, "p")
  
  -- 使用簡化的檔案路徑，避免過度複雜化
  local filename = string.format("%s/%s_%s.md", joplin_dir, note_id:sub(1, 8), safe_title)
  
  -- 立即創建真實檔案，確保檔案存在且內容正確
  vim.fn.writefile(lines, filename)
  
  vim.api.nvim_buf_set_name(bufnr, filename)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "")
  vim.api.nvim_buf_set_option(bufnr, "modified", false)  -- 檔案已同步，無需修改標記
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(bufnr, "writebackup", false)
  
  -- 保存映射關係
  buffer_note_map[bufnr] = {
    note_id = note_id,
    title = note.title,
    parent_id = note.parent_id,
    created_time = note.created_time,
    updated_time = note.updated_time,
  }
  note_buffer_map[note_id] = bufnr
  
  -- 設置自動命令來處理保存
  -- 使用更強制的方法確保 BufWriteCmd 被觸發
  
  vim.api.nvim_buf_set_var(bufnr, "joplin_temp_file", filename)
  
  -- 設置 buffer 為需要自定義寫入
  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  
  -- 使用 BufWriteCmd 完全接管保存
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      print("💾 開始 Joplin 筆記保存流程...")
      
      -- 1. 手動觸發格式化（如果 conform.nvim 可用）
      local conform_ok, conform = pcall(require, "conform")
      if conform_ok then
        print("🎨 正在格式化...")
        local format_ok, format_err = pcall(conform.format, { 
          bufnr = bufnr, 
          async = false,  -- 同步格式化確保完成
        })
        if format_ok then
          print("✨ 格式化完成")
        else
          print("⚠️  格式化失敗: " .. tostring(format_err))
        end
      else
        print("ℹ️  未找到 conform.nvim，跳過格式化")
      end
      
      -- 2. 獲取（可能已格式化的）內容
      local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local current_filename = vim.api.nvim_buf_get_name(bufnr)
      
      -- 3. 同步到 Joplin
      local joplin_success = M.save_note(bufnr)
      
      -- 4. 更新本地檔案
      local file_success = pcall(vim.fn.writefile, current_lines, current_filename)
      
      -- 5. 設置為未修改狀態（這是 BufWriteCmd 的關鍵）
      vim.api.nvim_buf_set_option(bufnr, "modified", false)
      
      -- 6. 報告結果
      if joplin_success and file_success then
        print("✅ 保存完成（Joplin + 本地檔案）")
      elseif file_success then
        print("⚠️  本地檔案已保存，但 Joplin 同步失敗")
      else
        print("❌ 保存失敗")
      end
    end,
  })
  
  -- 設置多個自動命令來確保清理映射和臨時檔案
  local cleanup_callback = function()
    local note_info = buffer_note_map[bufnr]
    if note_info then
      -- 清理映射關係
      note_buffer_map[note_info.note_id] = nil
      buffer_note_map[bufnr] = nil
      
      -- 清理臨時檔案
      local buf_filename = filename  -- 使用簡化後的檔案名
      if buf_filename and buf_filename:find("/.joplin/") then
        local delete_ok = pcall(vim.fn.delete, buf_filename)
        if delete_ok then
          print("🗑️  已清理 Joplin 暫存檔案: " .. vim.fn.fnamemodify(buf_filename, ":t"))
        else
          print("⚠️  清理暫存檔案失敗: " .. vim.fn.fnamemodify(buf_filename, ":t"))
        end
      end
    end
  end
  
  -- 設置多個觸發點確保清理
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
    buffer = bufnr,
    callback = cleanup_callback,
  })
  
  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = bufnr,
    callback = function()
      -- 延遲清理作為備選方案
      vim.schedule(cleanup_callback)
    end,
  })
  
  -- 延遲觸發 Copilot 重新檢查此 buffer
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      -- 暫時設置為正常 buffer 來讓 Copilot 初始化
      vim.api.nvim_buf_set_option(bufnr, "buftype", "")
      
      -- 觸發 Copilot 重新檢查
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })
      vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
      
      -- 延遲一點後重新設置為 acwrite
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
        end
      end)
    end
  end)
  
  -- 設置自動同步命令（當進入此 buffer 時）
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = bufnr,
    callback = function()
      -- 延遲執行避免在 buffer 創建過程中觸發
      vim.schedule(function()
        local joplin = require('joplin')
        if joplin.auto_sync_to_current_note then
          joplin.auto_sync_to_current_note()
        end
      end)
    end,
  })
  
  -- 根據 open_cmd 打開 buffer
  if open_cmd == "edit" then
    vim.api.nvim_set_current_buf(bufnr)
  elseif open_cmd == "split" then
    vim.cmd("split")
    vim.api.nvim_set_current_buf(bufnr)
  elseif open_cmd == "vsplit" then
    vim.cmd("vsplit")
    vim.api.nvim_set_current_buf(bufnr)
  elseif open_cmd == "tabnew" then
    vim.cmd("tabnew")
    vim.api.nvim_set_current_buf(bufnr)
  end
  
  return bufnr
end

-- 保存筆記到 Joplin
function M.save_note(bufnr)
  local note_info = buffer_note_map[bufnr]
  if not note_info then
    print("❌ Buffer 沒有關聯的 Joplin 筆記")
    return false
  end
  
  print("🔍 開始保存筆記 ID: " .. note_info.note_id)
  
  -- 獲取 buffer 內容
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  
  print("📝 筆記內容長度: " .. #content .. " 字元")
  
  -- 準備更新數據
  local update_data = {
    body = content,
  }
  
  print("🚀 發送 API 更新請求...")
  
  -- 調用 API 更新筆記
  local success, result = api.update_note(note_info.note_id, update_data)
  
  if success then
    print("✅ 筆記儲存成功")
    return true
  else
    print("❌ 筆記儲存失敗: " .. tostring(result))
    return false
  end
end

-- 檢查 buffer 是否是 Joplin 筆記
function M.is_joplin_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return buffer_note_map[bufnr] ~= nil
end

-- 獲取 buffer 對應的筆記信息
function M.get_note_info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return buffer_note_map[bufnr]
end

-- 重新加載筆記內容
function M.reload_note(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local note_info = buffer_note_map[bufnr]
  if not note_info then
    vim.notify("This buffer is not associated with a Joplin note", vim.log.levels.ERROR)
    return false
  end
  
  local success, note = api.get_note(note_info.note_id)
  if not success then
    vim.notify("Failed to reload note: " .. note, vim.log.levels.ERROR)
    return false
  end
  
  -- 更新 buffer 內容
  local lines = {}
  if note.body then
    lines = vim.split(note.body, "\n", { plain = true })
  end
  
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, "modified", false)
  
  -- 更新筆記信息
  buffer_note_map[bufnr] = {
    note_id = note_info.note_id,
    title = note.title,
    parent_id = note.parent_id,
    created_time = note.created_time,
    updated_time = note.updated_time,
  }
  
  vim.notify("Note reloaded successfully", vim.log.levels.INFO)
  return true
end

-- 便利函數：在分割視窗中打開筆記（從搜尋結果使用）
function M.open_note_split(note)
  return M.open_note(note, "vsplit")
end

-- 便利函數：直接替換當前視窗（從搜尋結果使用）
function M.open_note_current(note)
  return M.open_note(note, "edit")
end

-- 清理所有 Joplin 暫存檔案
function M.cleanup_all_temp_files()
  local cwd = vim.fn.getcwd()
  local joplin_dir = cwd .. "/.joplin"
  
  if vim.fn.isdirectory(joplin_dir) == 1 then
    local files = vim.fn.readdir(joplin_dir)
    for _, file in ipairs(files) do
      if file:match("%.md$") then
        local filepath = joplin_dir .. "/" .. file
        pcall(vim.fn.delete, filepath)
      end
    end
    -- 如果目錄空了就刪除目錄
    if #vim.fn.readdir(joplin_dir) == 0 then
      pcall(vim.fn.delete, joplin_dir, "d")
    end
  end
end

-- 在 Neovim 退出時清理所有暫存檔案
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    M.cleanup_all_temp_files()
  end,
})

return M