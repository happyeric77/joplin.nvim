local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local api = require("joplin.api.client")
local buffer_utils = require("joplin.utils.buffer")

local M = {
  name = "joplin",
  display_name = "Joplin"
}

local function get_icon(node_type)
  if node_type == "folder" then
    return {
      text = "📁",
      highlight = "NeoTreeDirectoryIcon"
    }
  elseif node_type == "note" then
    return {
      text = "📄",
      highlight = "NeoTreeFileIcon"
    }
  else
    return {
      text = "❓",
      highlight = "NeoTreeFileIcon"
    }
  end
end

local function create_node(item, node_type, parent_id)
  return {
    id = item.id,
    name = item.title,
    type = node_type,
    path = item.id,
    parent_id = parent_id,
    stat = {
      type = node_type,
      size = 0,
      mtime = item.updated_time and tonumber(item.updated_time) or 0,
      mode = 33188,
    },
    extra = {
      joplin_id = item.id,
      joplin_type = node_type,
      created_time = item.created_time,
      updated_time = item.updated_time,
    },
    is_loaded = node_type == "note",
    loaded = node_type == "note",
  }
end

local function get_folders()
  local success, folders = api.get_folders()
  if not success then
    vim.notify("Failed to fetch folders: " .. (folders or "Unknown error"), vim.log.levels.ERROR)
    return {}
  end
  return folders or {}
end

local function get_notes_in_folder(folder_id)
  local success, notes = api.get_notes(folder_id)
  if not success then
    vim.notify("Failed to fetch notes: " .. (notes or "Unknown error"), vim.log.levels.ERROR)
    return {}
  end
  return notes or {}
end

local function get_all_notes()
  local success, notes = api.get_notes()
  if not success then
    vim.notify("Failed to fetch notes: " .. (notes or "Unknown error"), vim.log.levels.ERROR)
    return {}
  end
  return notes or {}
end

function M.get_items(state, node, callback)
  local items = {}
  
  if not node then
    -- 根節點：顯示所有資料夾
    local folders = get_folders()
    for _, folder in ipairs(folders) do
      local folder_node = create_node(folder, "folder", nil)
      folder_node.icon = get_icon("folder")
      table.insert(items, folder_node)
    end
    
    -- 也顯示沒有分類的筆記
    local all_notes = get_all_notes()
    local folder_ids = {}
    for _, folder in ipairs(folders) do
      folder_ids[folder.id] = true
    end
    
    for _, note in ipairs(all_notes) do
      if not note.parent_id or not folder_ids[note.parent_id] then
        local note_node = create_node(note, "note", nil)
        note_node.icon = get_icon("note")
        table.insert(items, note_node)
      end
    end
  else
    -- 子節點：顯示資料夾中的筆記
    if node.type == "folder" then
      local notes = get_notes_in_folder(node.id)
      for _, note in ipairs(notes) do
        local note_node = create_node(note, "note", node.id)
        note_node.icon = get_icon("note")
        table.insert(items, note_node)
      end
    end
  end
  
  callback(items)
end

-- 主要的 navigate 函數（Neo-tree 必需）
function M.navigate(state, path, callback)
  if not path or path == "/" then
    -- 載入根節點
    M.get_items(state, nil, function(items)
      -- 不使用 neo-tree.tree，直接設置 state.tree
      state.tree = {
        root = {
          id = "root",
          name = "Joplin",
          type = "directory",
          path = "/",
          loaded = true,
          children = items
        }
      }
      
      -- 設置每個子節點的 parent
      for _, item in ipairs(items) do
        item.parent = state.tree.root
      end
      
      renderer.redraw(state)
      
      if callback then
        callback()
      end
    end)
  else
    -- 展開特定節點 - 簡化處理
    if callback then
      callback()
    end
  end
end

-- 處理節點選擇（打開筆記）
local function open_note(state, node, open_cmd)
  if node.type == "note" then
    local joplin_id = node.extra.joplin_id
    if joplin_id then
      buffer_utils.open_note(joplin_id, open_cmd)
    else
      vim.notify("Invalid note ID", vim.log.levels.ERROR)
    end
  elseif node.type == "folder" then
    -- 切換資料夾展開/折疊狀態
    if node:is_expanded() then
      node:collapse()
    else
      node:expand()
    end
    renderer.redraw(state)
  end
end

-- 定義按鍵映射
function M.setup(config, global_config)
  return {
    commands = {
      open = function(state)
        local node = state.tree:get_node()
        open_note(state, node, "edit")
      end,
      
      open_split = function(state)
        local node = state.tree:get_node()
        open_note(state, node, "split")
      end,
      
      open_vsplit = function(state)
        local node = state.tree:get_node()
        open_note(state, node, "vsplit")
      end,
      
      open_tabnew = function(state)
        local node = state.tree:get_node()
        open_note(state, node, "tabnew")
      end,
      
      refresh = function(state)
        manager.refresh(M.name)
      end,
      
      toggle_node = function(state)
        local node = state.tree:get_node()
        if node.type == "folder" then
          cc.toggle_node(state)
        else
          open_note(state, node, "edit")
        end
      end,
      
      add_folder = function(state)
        local node = state.tree:get_node()
        local parent_id = nil
        if node and node.type == "folder" then
          parent_id = node.id
        end
        
        vim.ui.input({ prompt = "New folder name: " }, function(input)
          if input and input ~= "" then
            local success, result = api.create_folder(input, parent_id)
            if success then
              vim.notify("Folder created successfully", vim.log.levels.INFO)
              manager.refresh(M.name)
            else
              vim.notify("Failed to create folder: " .. result, vim.log.levels.ERROR)
            end
          end
        end)
      end,
      
      add_note = function(state)
        local node = state.tree:get_node()
        local parent_id = nil
        if node and node.type == "folder" then
          parent_id = node.id
        end
        
        vim.ui.input({ prompt = "New note title: " }, function(input)
          if input and input ~= "" then
            local success, result = api.create_note(input, "", parent_id)
            if success then
              vim.notify("Note created successfully", vim.log.levels.INFO)
              manager.refresh(M.name)
              -- 自動打開新建的筆記
              if result and result.id then
                buffer_utils.open_note(result.id, "edit")
              end
            else
              vim.notify("Failed to create note: " .. result, vim.log.levels.ERROR)
            end
          end
        end)
      end,
      
      delete = function(state)
        local node = state.tree:get_node()
        if not node then
          return
        end
        
        local item_type = node.type == "folder" and "folder" or "note"
        local confirm_msg = string.format("Delete %s '%s'? (y/N)", item_type, node.name)
        
        vim.ui.input({ prompt = confirm_msg }, function(input)
          if input and (input:lower() == "y" or input:lower() == "yes") then
            local success, result
            if node.type == "folder" then
              success, result = api.delete_folder(node.id)
            else
              success, result = api.delete_note(node.id)
            end
            
            if success then
              vim.notify(string.format("%s deleted successfully", item_type:gsub("^%l", string.upper)), vim.log.levels.INFO)
              manager.refresh(M.name)
            else
              vim.notify(string.format("Failed to delete %s: %s", item_type, result), vim.log.levels.ERROR)
            end
          end
        end)
      end,
    },
    
    window = {
      mappings = {
        ["<cr>"] = "open",
        ["<2-LeftMouse>"] = "open",
        ["s"] = "open_split",
        ["v"] = "open_vsplit",
        ["t"] = "open_tabnew",
        ["R"] = "refresh",
        ["<space>"] = "toggle_node",
        ["a"] = "add_note",
        ["A"] = "add_folder",
        ["d"] = "delete",
      }
    }
  }
end

return M