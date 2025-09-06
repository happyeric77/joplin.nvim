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
	vim.api.nvim_buf_set_keymap(bufnr, "n", "o", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").handle_tree_open(tree_state)
		end,
	})

	vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").handle_tree_enter(tree_state)
		end,
	})

	-- R: 重新整理
	vim.api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").refresh_tree(tree_state)
		end,
	})

	-- q: 關閉
	vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>q<cr>", {
		noremap = true,
		silent = true,
	})

	-- a: 在當前資料夾建立新筆記
	vim.api.nvim_buf_set_keymap(bufnr, "n", "a", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").create_item_from_tree()
		end,
	})

	-- A: 在當前資料夾建立新資料夾
	vim.api.nvim_buf_set_keymap(bufnr, "n", "A", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").create_folder_from_tree()
		end,
	})

	-- d: 刪除筆記或資料夾
	vim.api.nvim_buf_set_keymap(bufnr, "n", "d", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").delete_item_from_tree()
		end,
	})

	-- r: 重新命名筆記或資料夾
	vim.api.nvim_buf_set_keymap(bufnr, "n", "r", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").rename_item_from_tree()
		end,
	})

	-- m: 移動筆記或資料夾
	vim.api.nvim_buf_set_keymap(bufnr, "n", "m", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").move_item_from_tree()
		end,
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
	table.insert(tree_state.line_data, { type = "header" })
	table.insert(tree_state.lines, "")
	table.insert(tree_state.line_data, { type = "empty" })

	-- 建立並顯示階層樹狀結構
	local folder_tree = require("joplin").build_folder_tree(tree_state.folders or {})
	require("joplin").display_folder_tree(tree_state, folder_tree, 0)

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
			original_win = original_win, -- 記錄原始視窗
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
			end,
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

-- 尋找活躍的樹狀 buffer
function M.find_active_tree_buffer()
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			return bufnr
		end
	end
	return nil
end

-- 尋找顯示樹狀檢視的活躍視窗
function M.find_active_tree_window()
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			-- 檢查是否有視窗正在顯示這個 buffer
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local win_bufnr = vim.api.nvim_win_get_buf(winid)
				if win_bufnr == bufnr then
					return winid, bufnr
				end
			end
		end
	end
	return nil, nil
end

-- 在樹狀視窗中尋找並高亮指定筆記（不切換 focus）
function M.highlight_note_in_tree(note_id)
	local tree_bufnr = M.find_active_tree_buffer()
	if not tree_bufnr then
		return false
	end

	local tree_state = buffer_tree_states[tree_bufnr]
	if not tree_state then
		return false
	end

	-- 在樹狀顯示中尋找指定的筆記
	for line_num, line_data in ipairs(tree_state.line_data) do
		if line_data.type == "note" and line_data.id == note_id then
			-- 尋找樹狀視窗
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_bufnr then
					-- 記錄當前活躍視窗
					local current_win = vim.api.nvim_get_current_win()

					-- 使用 nvim_win_call 在樹狀視窗中設置游標，但不切換 focus
					vim.api.nvim_win_call(winid, function()
						vim.api.nvim_win_set_cursor(0, { line_num, 0 })
					end)

					-- 確保 focus 保持在原來的視窗
					if vim.api.nvim_get_current_win() ~= current_win then
						vim.api.nvim_set_current_win(current_win)
					end

					return true
				end
			end
			return false
		end
	end

	return false
end

-- 展開到指定 folder 並高亮指定筆記（靜默模式）
function M.expand_and_highlight_note(parent_folder_id, note_id, silent)
	silent = silent or false

	if not silent then
		print("🔄 展開到資料夾: " .. parent_folder_id)
	end

	-- 先展開到目標資料夾，傳遞 silent 參數
	M.expand_to_folder(parent_folder_id, silent)

	-- 等待樹狀重建完成後嘗試高亮筆記
	vim.schedule(function()
		-- 給一個短暫延遲確保樹狀重建完成
		vim.defer_fn(function()
			local highlighted = M.highlight_note_in_tree(note_id)
			if not silent and not highlighted then
				-- 只在非靜默模式下提供診斷信息
				local tree_bufnr = M.find_active_tree_buffer()
				if tree_bufnr then
					local tree_state = buffer_tree_states[tree_bufnr]
					if tree_state and tree_state.folder_notes[parent_folder_id] then
						local notes = tree_state.folder_notes[parent_folder_id]
						print("📝 資料夾中共有 " .. #notes .. " 個筆記")
						for i, note in ipairs(notes) do
							if note.id == note_id then
								print("✅ 目標筆記確實在資料夾中: " .. note.title)
								break
							end
						end
					end
				end
			end
		end, 200) -- 200ms 延遲
	end)
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
function M.expand_to_folder(target_folder_id, silent)
	silent = silent or false

	if not silent then
		print("🔍 開始展開資料夾: " .. target_folder_id)
	end

	-- 尋找活躍的樹狀檢視 buffer
	local tree_bufnr = nil
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			tree_bufnr = bufnr
			break
		end
	end

	if not tree_bufnr then
		if not silent then
			print("❌ 沒有找到活躍的樹狀檢視")
		end
		return false
	end

	local tree_state = buffer_tree_states[tree_bufnr]
	if not tree_state then
		if not silent then
			print("❌ 無法找到樹狀檢視狀態")
		end
		return false
	end

	-- 確保 folders 資料是最新的（對於使用現有樹狀檢視的情況）
	if not tree_state.folders or #tree_state.folders == 0 then
		if not silent then
			print("🔄 重新載入資料夾資料...")
		end
		local api = require("joplin.api.client")
		local success, folders = api.get_folders()
		if success then
			tree_state.folders = folders
			-- 初始化新資料夾的狀態
			for _, folder in ipairs(folders) do
				if tree_state.expanded[folder.id] == nil then
					tree_state.expanded[folder.id] = false
				end
				if tree_state.loading[folder.id] == nil then
					tree_state.loading[folder.id] = false
				end
			end
		else
			if not silent then
				print("❌ 無法載入資料夾資料: " .. folders)
			end
			return false
		end
	end

	-- 建立 folder 映射
	local folder_map = M.build_folder_map(tree_state.folders)

	-- 檢查目標 folder 是否存在
	if not folder_map[target_folder_id] then
		if not silent then
			print("❌ 找不到指定的資料夾: " .. target_folder_id)
			print("🐛 可用的資料夾 ID: ")
			for id, folder in pairs(folder_map) do
				print("  - " .. id .. ": " .. (folder.title or "Untitled"))
			end
		end
		return false
	end

	-- 獲取到目標 folder 的路徑
	local path = M.get_folder_path(target_folder_id, folder_map)

	if not silent then
		print("🗂️  展開路徑 (" .. #path .. " 層): " .. table.concat(path, " -> "))
		for i, folder_id in ipairs(path) do
			local folder_name = folder_map[folder_id] and folder_map[folder_id].title or "Unknown"
			print("  " .. i .. ". " .. folder_id .. " (" .. folder_name .. ")")
		end
	end

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
					if not silent then
						local folder_name = folder_map[folder_id].title or "Unknown"
						if #notes > 0 then
							print("✅ 已載入 " .. #notes .. " 個筆記 (" .. folder_name .. ")")
						else
							print("📝 資料夾已展開，但沒有筆記 (" .. folder_name .. ")")
						end
					end
				else
					tree_state.folder_notes[folder_id] = {}
					if not silent then
						print("❌ 載入筆記失敗: " .. notes)
					end
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
			-- 尋找樹狀檢視視窗
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_bufnr then
					if silent then
						-- 靜默模式：使用 nvim_win_call 不切換 focus
						local current_win = vim.api.nvim_get_current_win()
						vim.api.nvim_win_call(winid, function()
							vim.api.nvim_win_set_cursor(0, { line_num, 0 })
						end)
						-- 確保 focus 保持在原來的視窗
						if vim.api.nvim_get_current_win() ~= current_win then
							vim.api.nvim_set_current_win(current_win)
						end
					else
						-- 非靜默模式：正常切換到樹狀視窗
						vim.api.nvim_set_current_win(winid)
						vim.api.nvim_win_set_cursor(winid, { line_num, 0 })
						local folder_name = folder_map[target_folder_id].title or "Unknown"
						local note_count = tree_state.folder_notes[target_folder_id]
								and #tree_state.folder_notes[target_folder_id]
							or 0
						print("✅ 已定位到資料夾: " .. folder_name .. " (" .. note_count .. " 個筆記)")
					end
					return true
				end
			end
			break
		end
	end

	if not silent then
		print("⚠️  資料夾已展開但未能定位游標")
	end
	return true
end

return M
