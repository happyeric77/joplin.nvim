local config = require("joplin.config")
local api = require("joplin.api.client")
local M = {}

function M.setup(opts)
	opts = opts or {}
	
	-- 設定配置
	config.setup(opts)
	
	-- 註冊基本命令
	vim.api.nvim_create_user_command('JoplinPing', function()
		M.ping()
	end, { desc = 'Test Joplin connection' })
	
	vim.api.nvim_create_user_command('JoplinHelp', function()
		M.show_help()
	end, { desc = 'Show Joplin plugin help' })
	
	vim.api.nvim_create_user_command('JoplinBrowse', function()
		M.browse()
	end, { desc = 'Browse Joplin notebooks and notes' })
	
	vim.api.nvim_create_user_command('JoplinTree', function()
		M.create_tree()
	end, { desc = 'Open Joplin tree view' })
	
	-- 搜尋相關命令
	vim.api.nvim_create_user_command('JoplinFind', function(opts)
		M.search_notes(opts.args)
	end, { 
		desc = 'Search Joplin notes with Telescope',
		nargs = '?'
	})
	
	vim.api.nvim_create_user_command('JoplinSearch', function(opts)
		M.search_notes(opts.args)
	end, { 
		desc = 'Search Joplin notes with Telescope',
		nargs = '?'
	})
	
	vim.api.nvim_create_user_command('JoplinFindNotebook', function(opts)
		M.search_notebooks(opts.args)
	end, { 
		desc = 'Search Joplin notebooks with Telescope',
		nargs = '?'
	})
	
	-- 設置快捷鍵
	local search_keymap = config.options.keymaps.search
	if search_keymap and search_keymap ~= "" then
		vim.keymap.set('n', search_keymap, function()
			M.search_notes()
		end, { 
			desc = 'Search Joplin notes',
			silent = true 
		})
	end
	
	local search_notebook_keymap = config.options.keymaps.search_notebook
	if search_notebook_keymap and search_notebook_keymap ~= "" then
		vim.keymap.set('n', search_notebook_keymap, function()
			M.search_notebooks()
		end, { 
			desc = 'Search Joplin notebooks',
			silent = true 
		})
	end
end

-- 測試 API 連接
function M.ping()
	local success, result = api.ping()
	if success then
		print("✅ Joplin connection successful: " .. result)
	else
		print("❌ Joplin connection failed: " .. result)
	end
	return success, result
end

-- 測試完整連接並顯示基本資訊
function M.test_connection()
	local ping_ok, ping_result = api.ping()
	if not ping_ok then
		print("❌ Cannot connect to Joplin: " .. ping_result)
		return false
	end

	print("✅ Connected to Joplin: " .. ping_result)

	local folders_ok, folders = api.get_folders()
	if folders_ok then
		print(string.format("📁 Found %d folders", #folders))
	else
		print("⚠️  Could not fetch folders: " .. folders)
	end

	return ping_ok
end

-- 列出所有資料夾
function M.list_folders()
	local success, folders = api.get_folders()
	if not success then
		print("❌ Failed to get folders: " .. folders)
		return false
	end

	print("📁 Joplin Folders:")
	for i, folder in ipairs(folders) do
		print(string.format("  %d. %s (id: %s)", i, folder.title, folder.id))
	end

	return folders
end

-- 列出筆記（可選擇資料夾）
function M.list_notes(folder_id, limit)
	local success, notes = api.get_notes(folder_id, limit)

	if not success then
		print("❌ Failed to get notes: " .. tostring(notes))
		return false
	end

	local folder_info = folder_id and ("in folder " .. folder_id) or "(all folders)"
	print(string.format("📝 Joplin Notes %s:", folder_info))

	if #notes == 0 then
		print("  (No notes found)")
		return notes
	end

	for i, note in ipairs(notes) do
		local updated = note.updated_time and os.date("%Y-%m-%d %H:%M", note.updated_time / 1000) or "N/A"
		print(string.format("  %d. %s (updated: %s)", i, note.title or "Untitled", updated))
	end

	return notes
end

-- 取得單一筆記
function M.get_note(note_id)
	return api.get_note(note_id)
end

-- 開啟樹狀檢視
function M.create_tree()
	local tree_ui = require("joplin.ui.tree")
	tree_ui.create_tree()
end

-- 查找適合開啟筆記的視窗
function M.find_target_window(tree_state)
	local tree_winid = vim.api.nvim_get_current_win()
	local all_wins = vim.api.nvim_list_wins()
	
	-- 如果有記錄的原始視窗，優先使用
	if tree_state.original_win then
		for _, winid in ipairs(all_wins) do
			if winid == tree_state.original_win then
				return winid
			end
		end
	end
	
	-- 尋找第一個非樹狀檢視的正常視窗
	for _, winid in ipairs(all_wins) do
		if winid ~= tree_winid then
			local bufnr = vim.api.nvim_win_get_buf(winid)
			local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
			-- 排除特殊 buffer (nofile, quickfix, etc.)
			if buftype == '' or buftype == 'acwrite' then
				return winid
			end
		end
	end
	
	-- 如果沒找到合適的視窗，返回 nil
	return nil
end

-- 在指定視窗開啟筆記
function M.open_note_in_window(note_id, target_win, split_type)
	local config = require("joplin.config")
	local buffer_utils = require('joplin.utils.buffer')
	
	if target_win then
		-- 切換到目標視窗
		vim.api.nvim_set_current_win(target_win)
		
		if split_type == "vsplit" then
			-- 垂直分割開啟筆記
			local success, result = pcall(buffer_utils.open_note, note_id, "vsplit")
			if not success then
				print("❌ 開啟筆記失敗: " .. result)
			end
		else
			-- 直接在當前視窗開啟筆記（替換內容）
			local success, result = pcall(buffer_utils.open_note, note_id, "edit")
			if not success then
				print("❌ 開啟筆記失敗: " .. result)
			end
		end
		
		-- 根據配置決定是否將焦點返回到樹狀檢視
		if not config.options.tree.focus_after_open then
			-- 保持在筆記視窗
			return
		end
	else
		-- 沒有找到目標視窗，創建新的垂直分割
		print("💡 沒有找到合適的視窗，創建新的分割")
		local success, result = pcall(buffer_utils.open_note, note_id, "vsplit")
		if not success then
			print("❌ 開啟筆記失敗: " .. result)
		end
	end
end

-- 重建樹狀顯示內容
function M.rebuild_tree_display(tree_state)
	local tree_ui = require("joplin.ui.tree")
	tree_ui.rebuild_tree_display(tree_state)
end

-- 建立 folder 階層樹狀結構
function M.build_folder_tree(folders)
	local tree = {}
	local folder_map = {}
	
	-- 建立 folder id 到 folder 物件的映射
	for _, folder in ipairs(folders) do
		folder_map[folder.id] = folder
		folder.children = {}
	end
	
	-- 建立父子關係
	for _, folder in ipairs(folders) do
		if folder.parent_id and folder.parent_id ~= "" then
			-- 有父資料夾，加入到父資料夾的 children 中
			local parent = folder_map[folder.parent_id]
			if parent then
				table.insert(parent.children, folder)
			end
		else
			-- 沒有父資料夾，是根層級
			table.insert(tree, folder)
		end
	end
	
	-- 排序根層級 folder
	table.sort(tree, function(a, b)
		return (a.title or "") < (b.title or "")
	end)
	
	-- 遞迴排序子資料夾
	local function sort_children(folder)
		if folder.children then
			table.sort(folder.children, function(a, b)
				return (a.title or "") < (b.title or "")
			end)
			for _, child in ipairs(folder.children) do
				sort_children(child)
			end
		end
	end
	
	for _, folder in ipairs(tree) do
		sort_children(folder)
	end
	
	return tree
end

-- 遞迴顯示 folder 樹狀結構
function M.display_folder_tree(tree_state, folders, depth)
	for _, folder in ipairs(folders) do
		local indent = string.rep("  ", depth)
		local is_expanded = tree_state.expanded[folder.id]
		local icon = is_expanded and "📂" or "📁"
		local expand_icon = is_expanded and "▼" or "▶"
		
		-- Folder 行
		local folder_line = string.format("%s%s %s %s", indent, expand_icon, icon, folder.title)
		table.insert(tree_state.lines, folder_line)
		table.insert(tree_state.line_data, {
			type = "folder",
			id = folder.id,
			title = folder.title,
			expanded = is_expanded,
			depth = depth
		})
		
		-- 如果展開，顯示內容
		if is_expanded then
			-- 先顯示子資料夾
			if folder.children and #folder.children > 0 then
				M.display_folder_tree(tree_state, folder.children, depth + 1)
			end
			
			-- 再顯示該資料夾中的筆記
			if tree_state.loading[folder.id] then
				-- 顯示載入指示器
				local loading_indent = string.rep("  ", depth + 1)
				local loading_line = string.format("%s⏳ 正在載入筆記...", loading_indent)
				table.insert(tree_state.lines, loading_line)
				table.insert(tree_state.line_data, {
					type = "loading",
					id = folder.id,
					depth = depth + 1
				})
			else
				local notes = tree_state.folder_notes[folder.id]
				if notes then
					for _, note in ipairs(notes) do
						local note_indent = string.rep("  ", depth + 1)
						local note_line = string.format("%s📄 %s", note_indent, note.title)
						table.insert(tree_state.lines, note_line)
						table.insert(tree_state.line_data, {
							type = "note",
							id = note.id,
							title = note.title,
							parent_id = folder.id,
							depth = depth + 1
						})
					end
				end
			end
		end
	end
end



-- 異步載入資料夾筆記
function M.load_folder_notes_async(tree_state, folder_id, cursor_line)
	-- 設置載入狀態
	tree_state.loading[folder_id] = true
	
	-- 立即更新顯示，顯示載入指示器
	M.rebuild_tree_display(tree_state)
	vim.api.nvim_win_set_cursor(0, {cursor_line, 0})
	
	-- 顯示載入訊息
	local folder_name = ""
	for _, folder in ipairs(tree_state.folders) do
		if folder.id == folder_id then
			folder_name = folder.title
			break
		end
	end
	print("🔄 正在載入 " .. folder_name .. " 的筆記...")
	
	-- 使用 vim.defer_fn 來模擬異步行為
	vim.defer_fn(function()
		local success, notes = api.get_notes(folder_id)
		if success then
			tree_state.folder_notes[folder_id] = notes
			print("✅ 已載入 " .. #notes .. " 個筆記")
		else
			tree_state.folder_notes[folder_id] = {}
			print("❌ 載入筆記失敗: " .. notes)
		end
		
		-- 清除載入狀態
		tree_state.loading[folder_id] = false
		
		-- 重新渲染
		M.rebuild_tree_display(tree_state)
		vim.api.nvim_win_set_cursor(0, {cursor_line, 0})
	end, 10) -- 10ms 延遲，讓 UI 有時間更新
end

-- 處理 Enter 按鍵
function M.handle_tree_enter(tree_state)
	local config = require("joplin.config")
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then return end
	
	if line_data.type == "folder" then
		-- 切換 folder 展開/收縮狀態
		local is_expanding = not tree_state.expanded[line_data.id]
		tree_state.expanded[line_data.id] = is_expanding
		
		-- 如果是展開且尚未載入筆記，則按需載入
		if is_expanding and not tree_state.folder_notes[line_data.id] then
			M.load_folder_notes_async(tree_state, line_data.id, line_num)
		else
			M.rebuild_tree_display(tree_state)
			-- 保持游標位置
			vim.api.nvim_win_set_cursor(0, {line_num, 0})
		end
		
	elseif line_data.type == "note" then
		-- Enter: 根據配置決定開啟方式（預設為替換上方視窗）
		local open_mode = config.options.keymaps.enter
		local target_win = M.find_target_window(tree_state)
		local split_type = (open_mode == "vsplit") and "vsplit" or "replace"
		
		M.open_note_in_window(line_data.id, target_win, split_type)
		
		-- 如果配置要求保持焦點在樹狀檢視，切換回樹狀檢視
		if config.options.tree.focus_after_open then
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_state.bufnr then
					vim.api.nvim_set_current_win(winid)
					break
				end
			end
		end
	end
end

-- 處理 o 按鍵（開啟）
function M.handle_tree_open(tree_state)
	local config = require("joplin.config")
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then return end
	
	if line_data.type == "note" then
		-- o: 根據配置決定開啟方式（預設為垂直分割）
		local open_mode = config.options.keymaps.o
		local target_win = M.find_target_window(tree_state)
		local split_type = (open_mode == "replace") and "replace" or "vsplit"
		
		M.open_note_in_window(line_data.id, target_win, split_type)
		
		-- 如果配置要求保持焦點在樹狀檢視，切換回樹狀檢視
		if config.options.tree.focus_after_open then
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_state.bufnr then
					vim.api.nvim_set_current_win(winid)
					break
				end
			end
		end
		
	elseif line_data.type == "folder" then
		-- 對 folder 按 o 也是展開/收縮
		M.handle_tree_enter(tree_state)
	end
end

-- 從樹狀檢視開啟筆記
function M.open_note_from_tree(note_id)
	print("🔍 嘗試開啟 note ID: " .. (note_id or "nil"))
	if not note_id then
		print("❌ Note ID 為空")
		return
	end
	
	local buffer_utils = require('joplin.utils.buffer')
	local success, result = pcall(buffer_utils.open_note, note_id, "vsplit")
	if not success then
		print("❌ 開啟 note 失敗: " .. result)
	else
		print("✅ Note 在 vsplit 中開啟成功")
	end
end

-- 重新整理樹狀檢視
function M.refresh_tree(tree_state)
	-- 重新獲取資料夾
	local folders_success, folders = api.get_folders()
	if not folders_success then
		print("❌ Failed to refresh folders")
		return
	end
	
	tree_state.folders = folders
	
	-- 保留已展開資料夾的筆記，清除其他資料夾的筆記
	local old_folder_notes = tree_state.folder_notes
	local old_expanded = tree_state.expanded
	tree_state.folder_notes = {}
	tree_state.expanded = {}
	
	-- 重新初始化展開狀態，並保留已展開資料夾的筆記
	for _, folder in ipairs(folders) do
		local was_expanded = old_expanded[folder.id] or false
		tree_state.expanded[folder.id] = was_expanded
		
		-- 如果資料夾之前是展開的且有筆記資料，保留這些資料
		if was_expanded and old_folder_notes[folder.id] then
			tree_state.folder_notes[folder.id] = old_folder_notes[folder.id]
		end
		-- 否則不預先載入筆記（按需載入）
	end
	
	M.rebuild_tree_display(tree_state)
	print("✅ 樹狀檢視已重新整理")
end

-- 提供一個備用的瀏覽器功能，不依賴 Neo-tree
function M.browse()
	print("📁 Joplin Browser (without Neo-tree)")
	print("=====================================")
	
	local success, folders = api.get_folders()
	if not success then
		print("❌ Failed to fetch folders: " .. (folders or "Unknown error"))
		return
	end
	
	print("📁 Available Notebooks:")
	for i, folder in ipairs(folders) do
		print(string.format("  %d. %s (id: %s)", i, folder.title, folder.id))
	end
	
	print("\n📝 Recent Notes:")
	local notes_success, notes = api.get_notes(nil, 10)
	if notes_success then
		for i, note in ipairs(notes) do
			local updated = note.updated_time and os.date("%Y-%m-%d %H:%M", note.updated_time / 1000) or "N/A"
			print(string.format("  %d. %s (updated: %s)", i, note.title or "Untitled", updated))
		end
	end
	
	print("\nℹ️  To open a note, use: :lua require('joplin.utils.buffer').open_note('note_id')")
end

-- 顯示幫助資訊
function M.show_help()
	print("📖 Joplin.nvim 使用指南")
	print("=======================")
	print("")
	print("🎯 主要指令:")
	print("  :JoplinTree         - 開啟互動式樹狀瀏覽器")
	print("  :JoplinFind         - 開啟 Telescope 搜尋筆記")
	print("  :JoplinSearch       - 開啟 Telescope 搜尋筆記 (同 JoplinFind)")
	print("  :JoplinFindNotebook - 開啟 Telescope 搜尋 Notebook")
	print("  :JoplinBrowse       - 開啟簡單文字清單瀏覽器")
	print("  :JoplinPing         - 測試 Joplin 連線狀態")
	print("  :JoplinHelp         - 顯示此幫助訊息")
	print("")
	print("⌨️  快捷鍵:")
	print("  " .. config.options.keymaps.search .. "         - 搜尋筆記 (預設: <leader>js)")
	print("  " .. config.options.keymaps.search_notebook .. "   - 搜尋 Notebook (預設: <leader>jsnb)")
	print("")
	print("🔍 筆記搜尋功能:")
	print("  • 使用 Telescope 提供即時搜尋體驗")
	print("  • 搜尋筆記標題和內容")
	print("  • 提供筆記預覽")
	print("  • Enter    - 在當前視窗開啟筆記")
	print("  • Ctrl+V   - 在分割視窗開啟筆記")
	print("")
	print("📁 Notebook 搜尋功能:")
	print("  • 使用 Telescope 搜尋資料夾")
	print("  • 即時搜尋 Notebook 標題")
	print("  • Enter    - 開啟樹狀檢視並展開到該資料夾")
	print("  • 自動載入並顯示資料夾內的所有筆記")
	print("")
	print("🌳 樹狀瀏覽器操作:")
	print("  Enter    - 在上方視窗開啟筆記（替換內容）")
	print("  o        - 在上方視窗垂直分割開啟筆記")
	print("  a        - 建立新項目 (名稱以 '/' 結尾建立資料夾，否則建立筆記)")
	print("  A        - 建立新資料夾 (快捷方式)")
	print("  d        - 刪除筆記或資料夾 (需要確認)")
	print("  r        - 重新命名筆記或資料夾")
	print("  R        - 重新整理樹狀結構")
	print("  q        - 關閉樹狀瀏覽器")
	print("")
	print("⚙️  配置選項:")
	print("  tree.height             - 樹狀檢視高度 (預設: 12)")
	print("  tree.position           - 樹狀檢視位置 (預設: 'botright')")
	print("  keymaps.enter           - Enter 鍵行為 ('replace' 或 'vsplit')")
	print("  keymaps.o               - o 鍵行為 ('vsplit' 或 'replace')")
	print("  keymaps.search          - 筆記搜尋快捷鍵 (預設: '<leader>js')")
	print("  keymaps.search_notebook - Notebook 搜尋快捷鍵 (預設: '<leader>jsnb')")
	print("")
	print("⚠️  重要提醒:")
	print("  • 確保 Joplin Web Clipper 服務正在運行")
	print("  • 搜尋功能需要安裝 telescope.nvim")
	print("  • 樹狀檢視會在底部開啟，類似 quickfix 視窗")
	print("  • 筆記會智能地在上方視窗開啟")
	print("")
	print("💡 需要協助？請參考 GitHub repository 或提交 issue")
end

-- 建立新筆記
function M.create_note(folder_id, title)
	if not title or title == "" then
		print("❌ 筆記標題不能為空")
		return
	end
	
	if not folder_id then
		print("❌ 需要指定資料夾 ID")
		return
	end
	
	print("📝 建立新筆記: " .. title)
	
	local success, result = api.create_note(title, "", folder_id)
	if not success then
		print("❌ 建立筆記失敗: " .. result)
		vim.notify("Failed to create note: " .. result, vim.log.levels.ERROR)
		return
	end
	
	print("✅ 筆記建立成功: " .. result.id)
	vim.notify("Note created successfully: " .. title, vim.log.levels.INFO)
	
	-- 自動開啟新建立的筆記，使用與正常開啟筆記相同的邏輯
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)
	
	if tree_state then
		-- 使用與 Enter 鍵相同的邏輯開啟筆記
		local target_win = M.find_target_window(tree_state)
		local config = require("joplin.config")
		M.open_note_in_window(result.id, target_win, config.options.keymaps.enter)
		print("✅ 新筆記已在上方視窗開啟")
	else
		-- 如果沒有樹狀結構，回退到原來的方式
		local buffer_utils = require('joplin.utils.buffer')
		local open_success, open_result = pcall(buffer_utils.open_note, result.id, "vsplit")
		if not open_success then
			print("❌ 開啟新筆記失敗: " .. open_result)
		else
			print("✅ 新筆記已在 vsplit 中開啟")
		end
	end
	
	return result
end

-- 刪除筆記
function M.delete_note(note_id)
	if not note_id then
		print("❌ 需要指定筆記 ID")
		return
	end
	
	-- 確認刪除
	local confirm = vim.fn.input("確定要刪除此筆記嗎？(y/n): ")
	if confirm ~= "y" and confirm ~= "Y" then
		print("❌ 取消刪除操作")
		return false
	end
	
	print("🗑️  刪除筆記 ID: " .. note_id)
	
	local success, result = api.delete_note(note_id)
	if not success then
		print("❌ 刪除筆記失敗: " .. result)
		vim.notify("Failed to delete note: " .. result, vim.log.levels.ERROR)
		return false
	end
	
	print("✅ 筆記刪除成功")
	vim.notify("Note deleted successfully", vim.log.levels.INFO)
	
	return true
end

-- 刪除資料夾
function M.delete_folder(folder_id)
	if not folder_id then
		print("❌ 需要指定資料夾 ID")
		return false
	end
	
	-- 確認刪除
	local confirm = vim.fn.input("確定要刪除此資料夾嗎？(y/n): ")
	if confirm ~= "y" and confirm ~= "Y" then
		print("❌ 取消刪除操作")
		return false
	end
	
	print("🗑️  刪除資料夾 ID: " .. folder_id)
	
	local success, result = api.delete_folder(folder_id)
	if not success then
		print("❌ 刪除資料夾失敗: " .. result)
		vim.notify("Failed to delete folder: " .. result, vim.log.levels.ERROR)
		return false
	end
	
	print("✅ 資料夾刪除成功")
	vim.notify("Folder deleted successfully", vim.log.levels.INFO)
	
	return true
end

-- 重新命名筆記
function M.rename_note(note_id, new_title)
	if not note_id then
		print("❌ 需要指定筆記 ID")
		return false
	end
	
	if not new_title or new_title == "" then
		print("❌ 需要指定新的筆記標題")
		return false
	end
	
	print("📝 重新命名筆記 ID: " .. note_id .. " -> " .. new_title)
	
	local success, result = api.update_note(note_id, {title = new_title})
	if not success then
		print("❌ 重新命名筆記失敗: " .. result)
		vim.notify("Failed to rename note: " .. result, vim.log.levels.ERROR)
		return false
	end
	
	print("✅ 筆記重新命名成功")
	vim.notify("Note renamed successfully", vim.log.levels.INFO)
	
	return true
end

-- 重新命名資料夾
function M.rename_folder(folder_id, new_title)
	if not folder_id then
		print("❌ 需要指定資料夾 ID")
		return false
	end
	
	if not new_title or new_title == "" then
		print("❌ 需要指定新的資料夾標題")
		return false
	end
	
	print("📁 重新命名資料夾 ID: " .. folder_id .. " -> " .. new_title)
	
	local success, result = api.update_folder(folder_id, {title = new_title})
	if not success then
		print("❌ 重新命名資料夾失敗: " .. result)
		vim.notify("Failed to rename folder: " .. result, vim.log.levels.ERROR)
		return false
	end
	
	print("✅ 資料夾重新命名成功")
	vim.notify("Folder renamed successfully", vim.log.levels.INFO)
	
	return true
end

-- 獲取指定 buffer 的 tree_state
function M.get_tree_state_for_buffer(bufnr)
	local tree_ui = require("joplin.ui.tree")
	return tree_ui.get_tree_state_for_buffer(bufnr)
end

-- 從樹狀檢視建立新項目 (筆記或資料夾)
function M.create_item_from_tree()
	-- 獲取當前 buffer 的 tree_state
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)
	
	if not tree_state then
		print("❌ 無法找到樹狀檢視狀態")
		return
	end
	
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then
		print("❌ 無法解析當前行")
		return
	end
	
	local parent_folder_id = nil
	
	-- 如果當前行是資料夾，使用該資料夾作為父資料夾
	if line_data.type == "folder" then
		parent_folder_id = line_data.id
	-- 如果當前行是筆記，使用其父資料夾
	elseif line_data.type == "note" then
		-- 需要找到該筆記的父資料夾 ID
		local success, note = api.get_note(line_data.id)
		if success and note.parent_id then
			parent_folder_id = note.parent_id
		else
			print("❌ 無法確定父資料夾，請在資料夾行上建立新項目")
			return
		end
	else
		print("❌ 請選擇一個資料夾或筆記來建立新項目")
		return
	end
	
	-- 顯示輸入對話框
	local input = vim.fn.input("建立新項目 (以 '/' 結尾建立資料夾): ")
	if input == "" then
		print("❌ 取消建立操作")
		return
	end
	
	local result = nil
	
	-- 檢查是否以 '/' 結尾
	if input:sub(-1) == "/" then
		-- 建立資料夾
		local folder_name = input:sub(1, -2)  -- 移除最後的 '/'
		if folder_name == "" then
			print("❌ 資料夾名稱不能為空")
			return
		end
		result = M.create_folder(parent_folder_id, folder_name)
	else
		-- 建立筆記
		result = M.create_note(parent_folder_id, input)
	end
	
	-- 如果建立成功，立即更新本地狀態
	if result then
		print("✅ 項目建立成功，更新顯示...")
		
		-- 如果建立的是資料夾，立即添加到本地狀態
		if input:sub(-1) == "/" then
			-- 添加新資料夾到本地狀態
			local new_folder = {
				id = result.id,
				title = result.title,
				parent_id = parent_folder_id
			}
			table.insert(tree_state.folders, new_folder)
			tree_state.expanded[result.id] = false
			tree_state.loading[result.id] = false
		else
			-- 如果建立的是筆記，將新筆記添加到已載入的筆記列表中
			if tree_state.folder_notes[parent_folder_id] then
				-- 如果該資料夾的筆記已經載入，將新筆記添加到列表中
				local new_note = {
					id = result.id,
					title = result.title,
					parent_id = parent_folder_id,
					created_time = result.created_time,
					updated_time = result.updated_time
				}
				table.insert(tree_state.folder_notes[parent_folder_id], new_note)
				
				-- 按標題排序筆記列表
				table.sort(tree_state.folder_notes[parent_folder_id], function(a, b)
					return (a.title or "") < (b.title or "")
				end)
			else
				-- 如果該資料夾的筆記尚未載入，不需要做任何事
				-- 下次展開時會自動載入包含新筆記的完整列表
			end
		end
		
		-- 立即重建顯示
		M.rebuild_tree_display(tree_state)
	end
end

-- 從樹狀檢視建立新資料夾 (A 鍵快捷方式)
function M.create_folder_from_tree()
	-- 獲取當前 buffer 的 tree_state
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)
	
	if not tree_state then
		print("❌ 無法找到樹狀檢視狀態")
		return
	end
	
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then
		print("❌ 無法解析當前行")
		return
	end
	
	local parent_folder_id = nil
	
	-- 如果當前行是資料夾，使用該資料夾作為父資料夾
	if line_data.type == "folder" then
		parent_folder_id = line_data.id
	-- 如果當前行是筆記，使用其父資料夾
	elseif line_data.type == "note" then
		-- 需要找到該筆記的父資料夾 ID
		local success, note = api.get_note(line_data.id)
		if success and note.parent_id then
			parent_folder_id = note.parent_id
		else
			print("❌ 無法確定父資料夾，請在資料夾行上建立新資料夾")
			return
		end
	else
		print("❌ 請選擇一個資料夾或筆記來建立新資料夾")
		return
	end
	
	-- 顯示輸入對話框
	local folder_name = vim.fn.input("新資料夾名稱: ")
	if folder_name == "" then
		print("❌ 取消建立操作")
		return
	end
	
	local result = M.create_folder(parent_folder_id, folder_name)
	
	-- 如果建立成功，立即更新本地狀態
	if result then
		print("✅ 資料夾建立成功，更新顯示...")
		
		-- 添加新資料夾到本地狀態
		local new_folder = {
			id = result.id,
			title = result.title,
			parent_id = parent_folder_id
		}
		table.insert(tree_state.folders, new_folder)
		tree_state.expanded[result.id] = false
		tree_state.loading[result.id] = false
		
		-- 立即重建顯示
		M.rebuild_tree_display(tree_state)
	end
end

-- 輕量級樹狀檢視重新整理（只更新資料夾列表，不重新載入所有筆記）
function M.refresh_tree_lightweight(tree_state)
	-- 重新獲取資料夾列表
	local folders_success, folders = api.get_folders()
	if not folders_success then
		print("❌ Failed to refresh folders")
		return
	end
	
	-- 更新資料夾列表
	tree_state.folders = folders
	
	-- 為新資料夾初始化狀態（不影響已存在的資料夾）
	for _, folder in ipairs(folders) do
		if tree_state.expanded[folder.id] == nil then
			tree_state.expanded[folder.id] = false
		end
		if tree_state.loading[folder.id] == nil then
			tree_state.loading[folder.id] = false
		end
	end
	
	-- 重建顯示內容
	M.rebuild_tree_display(tree_state)
	print("✅ 樹狀檢視已更新")
end

-- 建立新資料夾
function M.create_folder(parent_id, title)
	if not title or title == "" then
		print("❌ 資料夾標題不能為空")
		return
	end
	
	if not parent_id then
		print("❌ 需要指定父資料夾 ID")
		return
	end
	
	print("📁 建立新資料夾: " .. title)
	
	local success, result = api.create_folder(title, parent_id)
	if not success then
		print("❌ 建立資料夾失敗: " .. result)
		vim.notify("Failed to create folder: " .. result, vim.log.levels.ERROR)
		return
	end
	
	print("✅ 資料夾建立成功: " .. result.id)
	vim.notify("Folder created successfully: " .. title, vim.log.levels.INFO)
	
	return result
end

-- 從樹狀檢視刪除筆記或資料夾
function M.delete_item_from_tree()
	-- 獲取當前 buffer 的 tree_state
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)
	
	if not tree_state then
		print("❌ 無法找到樹狀檢視狀態")
		return
	end
	
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then
		print("❌ 無法解析當前行")
		return
	end
	
	if line_data.type ~= "note" and line_data.type ~= "folder" then
		print("❌ 只能刪除筆記或資料夾")
		return
	end
	
	local success
	if line_data.type == "note" then
		success = M.delete_note(line_data.id)
	else -- folder
		success = M.delete_folder(line_data.id)
	end
	
	-- 如果刪除成功，立即更新本地狀態
	if success then
		if line_data.type == "note" then
			print("✅ 筆記刪除成功，更新顯示...")
			
			-- 從已載入的筆記列表中移除該筆記
			for folder_id, notes in pairs(tree_state.folder_notes) do
				if notes then
					for i, note in ipairs(notes) do
						if note.id == line_data.id then
							table.remove(notes, i)
							break
						end
					end
				end
			end
		else -- folder
			print("✅ 資料夾刪除成功，更新顯示...")
			
			-- 從資料夾列表中移除已刪除的資料夾
			if tree_state.folders then
				for i, folder in ipairs(tree_state.folders) do
					if folder.id == line_data.id then
						table.remove(tree_state.folders, i)
						break
					end
				end
			end
			
			-- 清除與該資料夾相關的快取
			if tree_state.folder_notes then
				tree_state.folder_notes[line_data.id] = nil
			end
			if tree_state.expanded then
				tree_state.expanded[line_data.id] = nil
			end
			if tree_state.loading then
				tree_state.loading[line_data.id] = nil
			end
		end
		
		-- 重建樹狀顯示
		M.rebuild_tree_display(tree_state)
	end
end

-- 從樹狀檢視重新命名筆記或資料夾
function M.rename_item_from_tree()
	-- 獲取當前 buffer 的 tree_state
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)
	
	if not tree_state then
		print("❌ 無法找到樹狀檢視狀態")
		return
	end
	
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then
		print("❌ 無法解析當前行")
		return
	end
	
	if line_data.type ~= "note" and line_data.type ~= "folder" then
		print("❌ 只能重新命名筆記或資料夾")
		return
	end
	
	-- 獲取當前名稱作為預設值
	local current_title = line_data.title or ""
	if line_data.type == "folder" then
		-- 從 folders 列表中獲取確切的標題
		for _, folder in ipairs(tree_state.folders or {}) do
			if folder.id == line_data.id then
				current_title = folder.title or ""
				break
			end
		end
	else -- note
		-- 從 folder_notes 中獲取確切的標題
		for _, notes in pairs(tree_state.folder_notes or {}) do
			if notes then
				for _, note in ipairs(notes) do
					if note.id == line_data.id then
						current_title = note.title or ""
						break
					end
				end
			end
		end
	end
	
	-- 顯示輸入對話框，使用當前標題作為預設值
	local new_title = vim.fn.input({
		prompt = "新名稱: ",
		default = current_title,
		completion = "file"
	})
	
	-- 檢查用戶是否取消了輸入
	if not new_title or new_title == "" then
		print("❌ 取消重新命名操作")
		return
	end
	
	-- 檢查名稱是否有變化
	if new_title == current_title then
		print("⚠️  名稱沒有變化")
		return
	end
	
	local success
	if line_data.type == "note" then
		success = M.rename_note(line_data.id, new_title)
	else -- folder
		success = M.rename_folder(line_data.id, new_title)
	end
	
	-- 如果重新命名成功，立即更新本地狀態
	if success then
		if line_data.type == "note" then
			print("✅ 筆記重新命名成功，更新顯示...")
			
			-- 更新已載入的筆記列表中的標題
			for folder_id, notes in pairs(tree_state.folder_notes) do
				if notes then
					for _, note in ipairs(notes) do
						if note.id == line_data.id then
							note.title = new_title
							break
						end
					end
				end
			end
		else -- folder
			print("✅ 資料夾重新命名成功，更新顯示...")
			
			-- 更新資料夾列表中的標題
			for _, folder in ipairs(tree_state.folders or {}) do
				if folder.id == line_data.id then
					folder.title = new_title
					break
				end
			end
		end
		
		-- 重建樹狀顯示
		M.rebuild_tree_display(tree_state)
	end
end

-- 搜尋筆記 (Telescope fuzzy finder)
function M.search_notes(default_text)
	local search_ui = require("joplin.ui.search")
	
	-- 檢查 Telescope 是否可用
	if not search_ui.is_telescope_available() then
		vim.notify("Telescope is not installed. Please install telescope.nvim to use search functionality.", vim.log.levels.ERROR)
		return
	end
	
	-- 檢查 Joplin 連接
	local ping_ok, ping_result = api.ping()
	if not ping_ok then
		vim.notify("Cannot connect to Joplin: " .. ping_result, vim.log.levels.ERROR)
		return
	end
	
	-- 開啟搜尋界面
	search_ui.search_notes({
		default_text = default_text,
		layout_strategy = 'horizontal',
		layout_config = {
			height = 0.8,
			width = 0.9,
			preview_width = 0.6,
		},
	})
end

-- 搜尋 notebooks (Telescope fuzzy finder)
function M.search_notebooks(default_text)
	local search_ui = require("joplin.ui.search")
	
	-- 檢查 Telescope 是否可用
	if not search_ui.is_telescope_available() then
		vim.notify("Telescope is not installed. Please install telescope.nvim to use search functionality.", vim.log.levels.ERROR)
		return
	end
	
	-- 檢查 Joplin 連接
	local ping_ok, ping_result = api.ping()
	if not ping_ok then
		vim.notify("Cannot connect to Joplin: " .. ping_result, vim.log.levels.ERROR)
		return
	end
	
	-- 開啟搜尋界面
	search_ui.search_notebooks({
		default_text = default_text,
		layout_strategy = 'horizontal',
		layout_config = {
			height = 0.6,
			width = 0.8,
		},
	})
end
-- 展開到指定 folder 並顯示其筆記
function M.expand_to_folder(folder_id)
	if not folder_id then
		vim.notify("Folder ID is required", vim.log.levels.ERROR)
		return
	end
	
	print("🔍 正在展開到資料夾: " .. folder_id)
	
	-- 開啟 tree view
	M.create_tree()
	
	-- 等待 tree 創建完成後再展開
	vim.defer_fn(function()
		local tree_ui = require("joplin.ui.tree")
		tree_ui.expand_to_folder(folder_id)
	end, 100) -- 100ms 延遲確保 tree 已建立
end
return M
