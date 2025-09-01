local api = require("joplin.api.client")
local M = {}

-- 儲存 buffer 到 note 的映射關係
local buffer_note_map = {}
local note_buffer_map = {}

-- 獲取或創建筆記 buffer
function M.open_note(note_id, open_cmd)
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
  local bufnr = vim.api.nvim_create_buf(false, false)
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
  
  -- 設置 buffer 屬性
  local filename = string.format("[Joplin] %s", note.title or "Untitled")
  vim.api.nvim_buf_set_name(bufnr, filename)
  vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(bufnr, "modified", false)
  
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
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      M.save_note(bufnr)
    end,
  })
  
  -- 設置自動命令來清理映射
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = bufnr,
    callback = function()
      local note_info = buffer_note_map[bufnr]
      if note_info then
        note_buffer_map[note_info.note_id] = nil
        buffer_note_map[bufnr] = nil
      end
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
    vim.notify("This buffer is not associated with a Joplin note", vim.log.levels.ERROR)
    return false
  end
  
  -- 獲取 buffer 內容
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  
  -- 準備更新數據
  local update_data = {
    body = content,
  }
  
  -- 調用 API 更新筆記
  local success, result = api.update_note(note_info.note_id, update_data)
  
  if success then
    vim.api.nvim_buf_set_option(bufnr, "modified", false)
    vim.notify("Note saved successfully", vim.log.levels.INFO)
    return true
  else
    vim.notify("Failed to save note: " .. tostring(result), vim.log.levels.ERROR)
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

return M