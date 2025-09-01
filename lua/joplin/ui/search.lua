local client = require("joplin.api.client")
local buffer_utils = require("joplin.utils.buffer")
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')

local M = {}

-- 格式化搜尋結果顯示
local function format_entry(note)
  local title = note.title or "Untitled"
  local updated = note.updated_time or 0
  local date_str = os.date("%Y-%m-%d %H:%M", updated / 1000)
  
  return string.format("%-40s │ %s", title, date_str)
end

-- 創建筆記預覽器
local function create_note_previewer()
  return previewers.new_buffer_previewer({
    title = "Note Preview",
    define_preview = function(self, entry, status)
      local note_id = entry.value.id
      local success, note_data = client.get_note(note_id)
      
      if success and note_data then
        local lines = {}
        
        -- 添加標題
        table.insert(lines, "# " .. (note_data.title or "Untitled"))
        table.insert(lines, "")
        
        -- 添加元數據
        local created = note_data.created_time or 0
        local updated = note_data.updated_time or 0
        table.insert(lines, "**Created:** " .. os.date("%Y-%m-%d %H:%M:%S", created / 1000))
        table.insert(lines, "**Updated:** " .. os.date("%Y-%m-%d %H:%M:%S", updated / 1000))
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
        
        -- 添加內容
        if note_data.body then
          for line in note_data.body:gmatch("[^\r\n]+") do
            table.insert(lines, line)
          end
        end
        
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'markdown')
      else
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Failed to load note preview"})
      end
    end,
  })
end

-- 執行搜尋並顯示結果
function M.search_notes(opts)
  opts = opts or {}
  local initial_query = opts.default_text or ""
  
  pickers.new(opts, {
    prompt_title = "Search Joplin Notes",
    finder = finders.new_dynamic {
      fn = function(prompt)
        if not prompt or prompt == "" then
          return {}
        end
        
        local success, result = client.search_notes(prompt, {
          limit = 50,
          fields = 'id,title,body,parent_id,updated_time,created_time'
        })
        
        if not success or not result or not result.items then
          return {}
        end
        
        local entries = {}
        for _, note in ipairs(result.items) do
          table.insert(entries, {
            value = note,
            display = format_entry(note),
            ordinal = note.title .. " " .. (note.body or ""),
          })
        end
        
        return entries
      end,
      entry_maker = function(entry)
        return entry
      end,
    },
    sorter = conf.generic_sorter(opts),
    previewer = create_note_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          buffer_utils.open_note_current(selection.value)
        end
      end)
      
      -- 添加 Ctrl+V 垂直分割開啟
      map('i', '<C-v>', function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          buffer_utils.open_note_split(selection.value)
        end
      end)
      
      return true
    end,
  }):find()
end

-- 檢查 Telescope 是否可用
function M.is_telescope_available()
  local has_telescope, _ = pcall(require, 'telescope')
  return has_telescope
end

return M