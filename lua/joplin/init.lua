local config = require("joplin.config")
local api = require("joplin.api.client")
local config = require("joplin.config")
local M = {}

-- 全局變數來存儲每個 buffer 的 tree_state
local buffer_tree_states = {}

function M.setup(opts)
	opts = opts or {}
	
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
	
	vim.api.nvim_create_user_command('JoplinRegisterNeotree', function()
		M.register_neotree()
	end, { desc = 'Manually register Neo-tree source' })
	
	-- 創建自定義 Neo-tree joplin 命令（作為備用方案）
	vim.api.nvim_create_user_command('NeotreeJoplin', function()
		M.open_neotree_joplin()
	end, { desc = 'Open Neo-tree with Joplin source (alternative)' })
	
	-- 創建一個更簡單的命令，直接繞過 Neo-tree 的解析器
	vim.api.nvim_create_user_command('JoplinTree', function()
		M.simple_neotree_joplin()
	end, { desc = 'Open Joplin in a simple tree view' })
	
	-- 延遲執行 Neo-tree 整合，給出使用提示
	vim.defer_fn(function()
		local neotree_ok, _ = pcall(require, "neo-tree")
		if neotree_ok then
			M.register_neotree()
			print("💡 Joplin 指令使用說明:")
			print("   :JoplinTree     - 開啟 Joplin 樹狀瀏覽器 (推薦)")
			print("   :NeotreeJoplin  - 嘗試 Neo-tree 整合")
			print("   :JoplinBrowse   - 文字式清單瀏覽")
			print("   :JoplinPing     - 測試 Joplin 連線")
			print("")
			print("⚠️  重要：請勿使用 ':Neotree joplin'")
			print("   該指令在 Neo-tree v3.x 中不支援")
			print("   請改用 ':JoplinTree' 來獲得相同功能")
		end
	end, 500)
end

-- 手動註冊 Neo-tree source（Neo-tree v3.x 兼容版本）
function M.register_neotree()
	-- 檢查 Neo-tree 是否可用
	local neo_tree_ok = pcall(require, "neo-tree")
	if not neo_tree_ok then
		print("❌ Neo-tree plugin not found. Please install nvim-neo-tree/neo-tree.nvim")
		return false
	end
	
	local success = false
	local joplin_source = require("joplin.ui.neotree")
	
	-- Neo-tree v3.x 方法: 直接修改 package.loaded
	local sources_module = "neo-tree.sources"
	if not package.loaded[sources_module] then
		package.loaded[sources_module] = {}
	end
	package.loaded[sources_module][joplin_source.name] = joplin_source
	print("✅ Method 1: Joplin source registered via package.loaded")
	success = true
	
	-- 方法 2: 嘗試使用 neo-tree 的內部註冊
	local setup_ok, setup = pcall(require, "neo-tree.setup")
	if setup_ok and setup.register_source then
		setup.register_source(joplin_source)
		print("✅ Method 2: Joplin source registered via setup.register_source")
		success = true
	end
	
	-- 方法 3: 直接設置到 global sources table
	if not _G.neo_tree_sources then
		_G.neo_tree_sources = {}
	end
	_G.neo_tree_sources[joplin_source.name] = joplin_source
	print("✅ Method 3: Joplin source registered to global table")
	success = true
	
	-- 方法 4: 嘗試 require 並設置
	local sources_ok, sources = pcall(require, "neo-tree.sources")
	if sources_ok and type(sources) == "table" then
		sources[joplin_source.name] = joplin_source
		print("✅ Method 4: Joplin source registered to neo-tree.sources")
		success = true
	else
		print("❌ Method 4 failed: sources not accessible")
	end
	
	-- 方法 5: 修復命令解析器（關鍵修復）
	local parser_ok, parser = pcall(require, "neo-tree.command.parser")
	if parser_ok then
		-- 保存原始的 get_sources 函數
		if not parser._original_get_sources then
			parser._original_get_sources = parser.get_sources
		end
		
		-- 覆寫 get_sources 函數來包含我們的 source
		parser.get_sources = function()
			local original_sources = parser._original_get_sources()
			original_sources[joplin_source.name] = joplin_source
			return original_sources
		end
		
		print("✅ Method 5: Command parser patched to include joplin source")
		success = true
	else
		print("❌ Method 5 failed: could not access command parser")
	end
	
	-- 方法 6: 直接修補命令驗證（更穩定的版本）
	local command_ok, command_init = pcall(require, "neo-tree.command.init")
	if command_ok and command_init._command then
		-- 保存原始的 _command 函數
		if not command_init._original_command then
			command_init._original_command = command_init._command
		end
		
		-- 覆寫 _command 函數來處理 joplin 命令
		command_init._command = function(input)
			-- 檢查是否是 joplin 命令
			if type(input) == "table" and input.args and input.args[1] == "joplin" then
				-- 直接調用我們的函數
				M.open_neotree_joplin()
				return
			elseif type(input) == "string" and input:match("^%s*joplin%s*$") then
				-- 處理字符串形式的命令
				M.open_neotree_joplin()
				return
			end
			-- 否則使用原始函數
			return command_init._original_command(input)
		end
		
		print("✅ Method 6: Command init function patched for joplin")
		success = true
	end
	
	return success
end

-- 調試 Neo-tree 註冊狀態（Neo-tree v3.x 兼容版本）
function M.debug_neotree()
	print("🔍 Debugging Neo-tree integration...")
	
	-- 檢查 Neo-tree 是否載入
	local neo_tree_ok, neo_tree = pcall(require, "neo-tree")
	print("Neo-tree loaded:", neo_tree_ok)
	
	-- 檢查 Neo-tree 版本信息
	if neo_tree_ok then
		local version_ok, version = pcall(function() return neo_tree.version or "unknown" end)
		print("Neo-tree version:", version_ok and version or "unknown")
	end
	
	-- 檢查 sources - 多種方法
	print("\nChecking sources registration methods:")
	
	-- 方法 1: package.loaded
	local sources_module = "neo-tree.sources"
	local pkg_sources = package.loaded[sources_module]
	print("package.loaded[neo-tree.sources]:", pkg_sources ~= nil)
	if pkg_sources then
		print("Sources in package.loaded:")
		for name, _ in pairs(pkg_sources) do
			print("  - " .. name)
		end
		print("Joplin in package.loaded:", pkg_sources.joplin ~= nil)
	end
	
	-- 方法 2: require sources
	local sources_ok, sources = pcall(require, "neo-tree.sources")
	print("require('neo-tree.sources'):", sources_ok)
	if sources_ok and type(sources) == "table" then
		print("Sources via require:")
		for name, _ in pairs(sources) do
			print("  - " .. name)
		end
		print("Joplin via require:", sources.joplin ~= nil)
	end
	
	-- 方法 3: global table
	print("_G.neo_tree_sources:", _G.neo_tree_sources ~= nil)
	if _G.neo_tree_sources then
		print("Global sources:")
		for name, _ in pairs(_G.neo_tree_sources) do
			print("  - " .. name)
		end
		print("Joplin in global:", _G.neo_tree_sources.joplin ~= nil)
	end
	
	-- 檢查我們的 source
	local joplin_source_ok, joplin_source = pcall(require, "joplin.ui.neotree")
	print("\nJoplin source loadable:", joplin_source_ok)
	if joplin_source_ok then
		print("Joplin source name:", joplin_source.name)
		print("Joplin source has navigate function:", type(joplin_source.navigate) == "function")
		print("Joplin source has setup function:", type(joplin_source.setup) == "function")
	else
		print("Error loading joplin source:", joplin_source)
	end
	
	-- 檢查命令解析器
	local parser_ok, parser = pcall(require, "neo-tree.command.parser")
	print("\nCommand parser loaded:", parser_ok)
	if parser_ok and parser.get_sources then
		local cmd_sources = parser.get_sources()
		print("Sources known to parser:", type(cmd_sources) == "table")
		if type(cmd_sources) == "table" then
			for name, _ in pairs(cmd_sources) do
				print("  - " .. name)
			end
		end
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

-- 備用的 Neo-tree joplin 開啟函數
function M.open_neotree_joplin()
	local neo_tree_ok = pcall(require, "neo-tree")
	if not neo_tree_ok then
		print("❌ Neo-tree not found, using JoplinTree instead")
		M.simple_neotree_joplin()
		return
	end
	
	local success, error_msg = pcall(function()
		M.register_neotree()
		
		-- 使用 Neo-tree 命令來開啟 joplin source
		vim.cmd("Neotree left joplin")
	end)
	
	if not success then
		print("❌ Failed to open Neo-tree joplin:", error_msg)
		print("📁 Using simple tree browser instead...")
		M.simple_neotree_joplin()
	end
end

-- 簡單的樹狀瀏覽器（不依賴 Neo-tree 的複雜狀態管理）
function M.simple_neotree_joplin()
	local success, error_msg = pcall(function()
		local bufnr
		
		-- 總是創建新的 buffer，避免重用問題
		bufnr = vim.api.nvim_create_buf(false, true)
		local timestamp = os.time()
		vim.api.nvim_buf_set_name(bufnr, "Joplin Tree " .. timestamp)
		
		vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
		vim.api.nvim_buf_set_option(bufnr, "filetype", "joplin-tree")
		vim.api.nvim_buf_set_option(bufnr, "modifiable", true)  -- 確保可修改
		
		print("🔄 正在載入資料夾結構...")
		
		-- 獲取 Joplin 資料夾數據
		local folders_success, folders = api.get_folders()
		if not folders_success then
			error("Failed to fetch folders: " .. folders)
		end
		
		print("✅ 已載入 " .. #folders .. " 個資料夾，正在建立樹狀結構...")
		
		-- 建立樹狀結構的狀態管理（不預先載入筆記）
		local tree_state = {
			bufnr = bufnr,
			folders = folders,
			folder_notes = {},  -- 開始時為空，按需載入
			expanded = {},      -- 記錄哪些 folder 是展開的
			loading = {},       -- 記錄哪些 folder 正在載入筆記
			lines = {},         -- 顯示的行
			line_data = {},     -- 每行對應的數據
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
		
		-- 設置 autocmd 來清理 tree_state
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = bufnr,
			callback = function()
				buffer_tree_states[bufnr] = nil
			end,
		})
		
		-- 設置鍵盤映射
		M.setup_tree_keymaps(tree_state)
		
		-- 在垂直分割中打開
		vim.cmd("vsplit")
		vim.api.nvim_set_current_buf(bufnr)
		
		print("✅ Joplin 樹狀瀏覽器已開啟")
		print("💡 快捷鍵：Enter=展開, o=開啟, a=建立, D=刪除, R=重新整理, q=關閉")
	end)
	
	if not success then
		print("❌ Failed to open tree browser:", error_msg)
		M.browse()
	end
end

-- 重建樹狀顯示內容
function M.rebuild_tree_display(tree_state)
	tree_state.lines = {}
	tree_state.line_data = {}
	
	-- 標題
	table.insert(tree_state.lines, "📁 Joplin Notebooks")
	table.insert(tree_state.line_data, {type = "header"})
	table.insert(tree_state.lines, "")
	table.insert(tree_state.line_data, {type = "empty"})
	
	-- 建立 folder 階層結構
	local folder_tree = M.build_folder_tree(tree_state.folders)
	
	-- 遞迴顯示 folder 樹
	M.display_folder_tree(tree_state, folder_tree, 0)
	
	-- 更新 buffer 內容
	vim.api.nvim_buf_set_option(tree_state.bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(tree_state.bufnr, 0, -1, false, tree_state.lines)
	vim.api.nvim_buf_set_option(tree_state.bufnr, "modifiable", false)
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

-- 設置鍵盤映射
function M.setup_tree_keymaps(tree_state)
	local bufnr = tree_state.bufnr
	
	-- Enter: 展開/收縮 folder 或開啟 note
	vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '', {
		noremap = true,
		silent = true,
		callback = function()
			M.handle_tree_enter(tree_state)
		end
	})
	
	-- o: 開啟 note
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'o', '', {
		noremap = true,
		silent = true,
		callback = function()
			M.handle_tree_open(tree_state)
		end
	})
	
	-- R: 重新整理
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'R', '', {
		noremap = true,
		silent = true,
		callback = function()
			M.refresh_tree(tree_state)
		end
	})
	
	-- d: 除錯資訊（顯示當前行的詳細資訊）
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', '', {
		noremap = true,
		silent = true,
		callback = function()
			M.debug_current_line(tree_state)
		end
	})
	
	-- q: 關閉
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<cr>', {
		noremap = true,
		silent = true
	})
	
	-- a: 建立新項目 (筆記或資料夾)
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'a', '', {
		noremap = true,
		silent = true,
		callback = function()
			M.create_item_from_tree()
		end
	})
	
	-- d: 刪除筆記或資料夾
	vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', '', {
		noremap = true,
		silent = true,
		callback = function()
			M.delete_item_from_tree()
		end
	})
end

-- 除錯當前行
function M.debug_current_line(tree_state)
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then
		print("無資料")
		return
	end
	
	print("=== 除錯資訊 ===")
	print("類型: " .. (line_data.type or "unknown"))
	print("ID: " .. (line_data.id or "none"))
	print("標題: " .. (line_data.title or "none"))
	print("父ID: " .. (line_data.parent_id or "none"))
	print("層級: " .. (line_data.depth or "unknown"))
	if line_data.type == "folder" then
		print("展開狀態: " .. (line_data.expanded and "是" or "否"))
		local notes_count = #(tree_state.folder_notes[line_data.id] or {})
		print("筆記數量: " .. notes_count)
		-- 顯示一些 notes 的詳細資訊
		if notes_count > 0 then
			print("前幾個筆記:")
			local notes = tree_state.folder_notes[line_data.id]
			for i, note in ipairs(notes) do
				if i <= 3 then
					print("  " .. i .. ". " .. (note.title or "No title") .. " (id: " .. (note.id or "No ID") .. ")")
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
		-- 開啟 note
		M.open_note_from_tree(line_data.id)
	end
end

-- 處理 o 按鍵（開啟）
function M.handle_tree_open(tree_state)
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]
	
	if not line_data then return end
	
	if line_data.type == "note" then
		M.open_note_from_tree(line_data.id)
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
	print("  :JoplinTree      - 開啟互動式樹狀瀏覽器 (推薦)")
	print("  :JoplinBrowse    - 開啟簡單文字清單瀏覽器")
	print("  :JoplinPing      - 測試 Joplin 連線狀態")
	print("  :JoplinHelp      - 顯示此幫助訊息")
	print("")
	print("🌳 樹狀瀏覽器操作:")
	print("  Enter    - 展開/收縮資料夾 或 開啟筆記")
	print("  o        - 開啟筆記 或 展開資料夾")
	print("  a        - 建立新項目 (名稱以 '/' 結尾建立資料夾，否則建立筆記)")
	print("  D        - 刪除筆記 (需要確認)")
	print("  R        - 重新整理樹狀結構")
	print("  d        - 顯示當前行的除錯資訊")
	print("  q        - 關閉瀏覽器")
	print("")
	print("⚠️  重要提醒:")
	print("  • 請勿使用 ':Neotree joplin' - 該指令不支援")
	print("  • 請改用 ':JoplinTree' 來獲得完整功能")
	print("  • 確保 Joplin Web Clipper 服務正在運行")
	print("")
	print("🔧 實驗性指令:")
	print("  :NeotreeJoplin   - 嘗試 Neo-tree 整合 (可能不穩定)")
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
	
	-- 自動開啟新建立的筆記
	local buffer_utils = require('joplin.utils.buffer')
	local open_success, open_result = pcall(buffer_utils.open_note, result.id, "vsplit")
	if not open_success then
		print("❌ 開啟新筆記失敗: " .. open_result)
	else
		print("✅ 新筆記已在 vsplit 中開啟")
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

-- 獲取指定 buffer 的 tree_state
function M.get_tree_state_for_buffer(bufnr)
	return buffer_tree_states[bufnr]
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
			
			-- 清除與該資料夾相關的快取
			tree_state.folder_notes[line_data.id] = nil
			tree_state.folder_expanded[line_data.id] = nil
		end
		
		-- 重建樹狀顯示
		M.rebuild_tree_display(tree_state)
	end
end

return M
