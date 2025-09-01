-- Joplin Tree UI - 自定義樹狀瀏覽器
-- 這個模組包含了主要的樹狀視圖功能，不依賴 Neo-tree

local api = require("joplin.api.client")

local M = {}

-- 樹狀態管理
local buffer_tree_states = {}

-- 設定樹狀檢視的快捷鍵
function M.setup_tree_keymaps(bufnr)
	local tree_state = buffer_tree_states[bufnr]
	if not tree_state then
		print("❌ 無法找到樹狀檢視狀態")
		return
	end
	
	-- o/Enter: 展開/摺疊資料夾或開啟筆記
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'o', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').handle_tree_open(tree_state)
		end
	})
	
	vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').handle_tree_enter(tree_state)
		end
	})
	
	-- R: 重新整理
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'R', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').refresh_tree(tree_state)
		end
	})
	
	-- q: 關閉
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<cr>', {
		noremap = true,
		silent = true
	})
	
	-- a: 在當前資料夾建立新筆記
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'a', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').create_item_from_tree()
		end
	})
	
	-- A: 在當前資料夾建立新資料夾
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'A', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').create_folder_from_tree()
		end
	})
	
	-- d: 刪除筆記或資料夾
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').delete_item_from_tree()
		end
	})
	
	-- r: 重新命名筆記或資料夾
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'r', '', {
		noremap = true,
		silent = true,
		callback = function()
			require('joplin').rename_item_from_tree()
		end
	})
end

-- 重建樹狀顯示
function M.rebuild_tree_display(tree_state)
	if not tree_state or not tree_state.bufnr then
		print("❌ Invalid tree state")
		return
	end
	
	-- 重建顯示內容
	tree_state.lines = {}
	tree_state.line_data = {}
	
	-- 標題
	table.insert(tree_state.lines, "📋 Joplin Notes")
	table.insert(tree_state.line_data, {type = "header"})
	table.insert(tree_state.lines, "")
	table.insert(tree_state.line_data, {type = "empty"})
	
	-- 建立並顯示階層樹狀結構
	local folder_tree = require('joplin').build_folder_tree(tree_state.folders or {})
	require('joplin').display_folder_tree(tree_state, folder_tree, 0)
	
	-- 更新 buffer 內容
	vim.api.nvim_buf_set_option(tree_state.bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(tree_state.bufnr, 0, -1, false, tree_state.lines)
	vim.api.nvim_buf_set_option(tree_state.bufnr, "modifiable", false)
end

-- 創建樹狀瀏覽器
function M.create_tree()
	local success, error_msg = pcall(function()
		local config = require("joplin.config")
		local tree_height = config.options.tree.height
		local tree_position = config.options.tree.position
		
		-- 記錄當前視窗 ID，作為之後開啟筆記的目標視窗
		local original_win = vim.api.nvim_get_current_win()
		
		local bufnr
		
		-- 總是創建新的 buffer
		bufnr = vim.api.nvim_create_buf(false, true)
		local timestamp = os.time()
		vim.api.nvim_buf_set_name(bufnr, "Joplin Tree " .. timestamp)
		
		vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
		vim.api.nvim_buf_set_option(bufnr, "filetype", "joplin-tree")
		vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
		
		print("🔄 正在載入資料夾結構...")
		
		-- 獲取 Joplin 資料夾數據
		local folders_success, folders = api.get_folders()
		if not folders_success then
			error("Failed to fetch folders: " .. folders)
		end
		
		print("✅ 已載入 " .. #folders .. " 個資料夾，正在建立樹狀結構...")
		
		-- 建立樹狀結構的狀態管理
		local tree_state = {
			bufnr = bufnr,
			folders = folders,
			folder_notes = {},
			expanded = {},
			loading = {},
			lines = {},
			line_data = {},
			original_win = original_win,  -- 記錄原始視窗
		}
		
		-- 初始狀態：所有 folder 都是收縮的
		for _, folder in ipairs(folders) do
			tree_state.expanded[folder.id] = false
			tree_state.loading[folder.id] = false
		end
		
		-- 重建顯示內容
		M.rebuild_tree_display(tree_state)
		
		-- 儲存 tree_state 供其他函數使用
		buffer_tree_states[bufnr] = tree_state
		
		-- 清理 autocmd：當 buffer 關閉時清除狀態
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = bufnr,
			callback = function()
				buffer_tree_states[bufnr] = nil
			end
		})
		
		-- 設定快捷鍵
		M.setup_tree_keymaps(bufnr)
		
		-- 使用配置的位置和高度開啟樹狀檢視
		vim.cmd(tree_position .. " " .. tree_height .. "split")
		vim.api.nvim_set_current_buf(bufnr)
		
		print("✅ Joplin 樹狀檢視已開啟")
		print("💡 按 'Enter' 在上方視窗開啟筆記，'o' 垂直分割開啟，'q' 關閉樹狀檢視")
	end)
	
	if not success then
		print("❌ 樹狀檢視開啟失敗: " .. error_msg)
		vim.notify("Failed to open Joplin tree: " .. error_msg, vim.log.levels.ERROR)
	end
end

-- 獲取指定 buffer 的 tree_state
function M.get_tree_state_for_buffer(bufnr)
	return buffer_tree_states[bufnr]
end

-- 建立 folder ID 到 folder 物件的映射
function M.build_folder_map(folders)
	local folder_map = {}
	for _, folder in ipairs(folders) do
		folder_map[folder.id] = folder
	end
	return folder_map
end

-- 獲取到達目標 folder 的路徑（從根到目標的 folder ID 列表）
function M.get_folder_path(target_folder_id, folder_map)
	local path = {}
	local current_id = target_folder_id
	
	-- 從目標 folder 向上追溯到根 folder
	while current_id do
		table.insert(path, 1, current_id) -- 在前面插入，保持從根到目標的順序
		local folder = folder_map[current_id]
		if not folder then
			break
		end
		current_id = folder.parent_id
		-- 如果 parent_id 為空或空字串，表示已到達根層級
		if not current_id or current_id == "" then
			break
		end
	end
	
	return path
end

-- 展開到指定的 folder 並載入其筆記
function M.expand_to_folder(target_folder_id)
	-- 尋找活躍的樹狀檢視 buffer
	local tree_bufnr = nil
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			tree_bufnr = bufnr
			break
		end
	end
	
	if not tree_bufnr then
		print("❌ 沒有找到活躍的樹狀檢視")
		return
	end
	
	local tree_state = buffer_tree_states[tree_bufnr]
	if not tree_state then
		print("❌ 無法找到樹狀檢視狀態")
		return
	end
	
	-- 建立 folder 映射
	local folder_map = M.build_folder_map(tree_state.folders)
	
	-- 檢查目標 folder 是否存在
	if not folder_map[target_folder_id] then
		print("❌ 找不到指定的資料夾: " .. target_folder_id)
		return
	end
	
	-- 獲取到目標 folder 的路徑
	local path = M.get_folder_path(target_folder_id, folder_map)
	
	print("🗂️  展開路徑: " .. table.concat(path, " -> "))
	
	-- 逐層展開路徑上的每個 folder
	for _, folder_id in ipairs(path) do
		if not tree_state.expanded[folder_id] then
			tree_state.expanded[folder_id] = true
			
			-- 載入該 folder 的筆記（如果尚未載入）
			if not tree_state.folder_notes[folder_id] then
				tree_state.loading[folder_id] = true
				
				-- 同步載入筆記（在展開過程中保持同步）
				local success, notes = api.get_notes(folder_id)
				if success then
					tree_state.folder_notes[folder_id] = notes
					local folder_name = folder_map[folder_id].title or "Unknown"
					if #notes > 0 then
						print("✅ 已載入 " .. #notes .. " 個筆記 (" .. folder_name .. ")")
					else
						print("📝 資料夾已展開，但沒有筆記 (" .. folder_name .. ")")
					end
				else
					tree_state.folder_notes[folder_id] = {}
					print("❌ 載入筆記失敗: " .. notes)
				end
				tree_state.loading[folder_id] = false
			end
		end
	end
	
	-- 重建樹狀顯示
	local joplin = require("joplin")
	joplin.rebuild_tree_display(tree_state)
	
	-- 尋找目標 folder 在顯示中的行號並定位游標
	for line_num, line_data in ipairs(tree_state.line_data) do
		if line_data.type == "folder" and line_data.id == target_folder_id then
			-- 切換到樹狀檢視視窗
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_bufnr then
					vim.api.nvim_set_current_win(winid)
					vim.api.nvim_win_set_cursor(winid, {line_num, 0})
					local folder_name = folder_map[target_folder_id].title or "Unknown"
					local note_count = tree_state.folder_notes[target_folder_id] and #tree_state.folder_notes[target_folder_id] or 0
					print("✅ 已定位到資料夾: " .. folder_name .. " (" .. note_count .. " 個筆記)")
					break
				end
			end
			break
		end
	end
end

return M