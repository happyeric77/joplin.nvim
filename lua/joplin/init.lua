local config = require("joplin.config")
local api = require("joplin.api.client")
local M = {}

-- Validate startup requirements (token and web clipper)
function M.validate_startup_requirements()
	local config = require("joplin.config")

	-- Skip validation if disabled
	if not config.options.startup.validate_on_load then
		return
	end

	local warnings = {}

	-- Check token immediately (synchronous)
	local token = config.get_token()
	if not token or token == "" then
		table.insert(warnings, {
			type = "token_missing",
			title = "Joplin Token Missing",
			message = "⚠️  Joplin token not found. Please set JOPLIN_TOKEN environment variable or configure token in setup().",
			help = "Run :JoplinHelp for setup instructions",
		})
	end

	-- Check web clipper asynchronously if enabled
	if config.options.startup.async_validation then
		vim.defer_fn(function()
			local ping_ok, ping_result = api.ping()
			if not ping_ok then
				table.insert(warnings, {
					type = "web_clipper_unavailable",
					title = "Joplin Web Clipper Unavailable",
					message = string.format(
						"⚠️  Cannot connect to Joplin Web Clipper at %s. Please ensure Joplin is running with Web Clipper enabled.",
						config.get_base_url()
					),
					help = "Run :JoplinHelp for setup instructions",
				})
			end

			-- Display all warnings
			M.display_startup_warnings(warnings)
		end, config.options.startup.validation_delay)
	else
		-- Synchronous validation - may block startup briefly
		local ping_ok, ping_result = api.ping()
		if not ping_ok then
			table.insert(warnings, {
				type = "web_clipper_unavailable",
				title = "Joplin Web Clipper Unavailable",
				message = string.format(
					"⚠️  Cannot connect to Joplin Web Clipper at %s. Please ensure Joplin is running with Web Clipper enabled.",
					config.get_base_url()
				),
				help = "Run :JoplinHelp for setup instructions",
			})
		end

		-- Display warnings immediately
		M.display_startup_warnings(warnings)
	end
end

-- Display startup warnings to user
function M.display_startup_warnings(warnings)
	local config = require("joplin.config")

	-- Skip display if disabled
	if not config.options.startup.show_warnings then
		return
	end

	if #warnings == 0 then
		return
	end

	-- Display warnings using vim.notify for better UX
	for _, warning in ipairs(warnings) do
		vim.notify(warning.message, vim.log.levels.WARN, {
			title = "Joplin.nvim: " .. warning.title,
		})
	end

	-- Provide help information
	if #warnings > 0 then
		vim.notify("💡 Run :JoplinHelp for detailed setup instructions", vim.log.levels.INFO, {
			title = "Joplin.nvim",
		})
	end
end

function M.setup(opts)
	opts = opts or {}

	-- Setup configuration
	config.setup(opts)

	-- Validate startup requirements (token and web clipper)
	M.validate_startup_requirements()

	-- Register basic commands
	vim.api.nvim_create_user_command("JoplinPing", function()
		M.ping()
	end, { desc = "Test Joplin connection" })

	vim.api.nvim_create_user_command("JoplinHelp", function()
		M.show_help()
	end, { desc = "Show Joplin plugin help" })

	vim.api.nvim_create_user_command("JoplinBrowse", function()
		M.browse()
	end, { desc = "Browse Joplin notebooks and notes" })

	vim.api.nvim_create_user_command("JoplinTree", function()
		M.create_tree()
	end, { desc = "Open Joplin tree view" })

	-- Search related commands
	vim.api.nvim_create_user_command("JoplinFind", function(opts)
		M.search_notes(opts.args)
	end, {
		desc = "Search Joplin notes with Telescope",
		nargs = "?",
	})

	vim.api.nvim_create_user_command("JoplinSearch", function(opts)
		M.search_notes(opts.args)
	end, {
		desc = "Search Joplin notes with Telescope",
		nargs = "?",
	})

	vim.api.nvim_create_user_command("JoplinFindNotebook", function(opts)
		M.search_notebooks(opts.args)
	end, {
		desc = "Search Joplin notebooks with Telescope",
		nargs = "?",
	})

	-- Setup shortcut keys
	local search_keymap = config.options.keymaps.search
	if search_keymap and search_keymap ~= "" then
		vim.keymap.set("n", search_keymap, function()
			M.search_notes()
		end, {
			desc = "Search Joplin notes",
			silent = true,
		})
	end

	local search_notebook_keymap = config.options.keymaps.search_notebook
	if search_notebook_keymap and search_notebook_keymap ~= "" then
		vim.keymap.set("n", search_notebook_keymap, function()
			M.search_notebooks()
		end, {
			desc = "Search Joplin notebooks",
			silent = true,
		})
	end

	local toggle_tree_keymap = config.options.keymaps.toggle_tree
	if toggle_tree_keymap and toggle_tree_keymap ~= "" then
		vim.keymap.set("n", toggle_tree_keymap, function()
			M.toggle_tree()
		end, {
			desc = "Toggle Joplin tree view",
			silent = true,
		})
	end
end

-- Test API connection
function M.ping()
	local success, result = api.ping()
	if success then
		print("✅ Joplin connection successful: " .. result)
	else
		print("❌ Joplin connection failed: " .. result)
	end
	return success, result
end

-- Test full connection and display basic information
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

-- List all folders
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

-- List notes (optional folder selection)
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

-- Get single note
function M.get_note(note_id)
	return api.get_note(note_id)
end

-- Open tree view
function M.create_tree()
	local tree_ui = require("joplin.ui.tree")
	tree_ui.create_tree()
end

-- Toggle tree view
function M.toggle_tree()
	local tree_ui = require("joplin.ui.tree")

	-- Find active tree view window
	local tree_winid, tree_bufnr = tree_ui.find_active_tree_window()

	if tree_winid then
		-- If found active tree view window, close it
		vim.api.nvim_win_close(tree_winid, false)
		print("✅ Joplin tree view closed")
	else
		-- If no active tree view window, create new one
		tree_ui.create_tree()
	end
end

-- Find suitable window for opening notes
function M.find_target_window(tree_state)
	local tree_winid = vim.api.nvim_get_current_win()
	local all_wins = vim.api.nvim_list_wins()

	-- If there's recorded original window, use it first
	if tree_state.original_win then
		for _, winid in ipairs(all_wins) do
			if winid == tree_state.original_win then
				return winid
			end
		end
	end

	-- Find first normal window that's not tree view
	for _, winid in ipairs(all_wins) do
		if winid ~= tree_winid then
			local bufnr = vim.api.nvim_win_get_buf(winid)
			local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
			-- Exclude special buffers (nofile, quickfix, etc.)
			if buftype == "" or buftype == "acwrite" then
				return winid
			end
		end
	end

	-- If no suitable window found, return nil
	return nil
end

-- Open note in specified window
function M.open_note_in_window(note_id, target_win, split_type)
	local config = require("joplin.config")
	local buffer_utils = require("joplin.utils.buffer")

	if target_win then
		-- Switch to target window
		vim.api.nvim_set_current_win(target_win)

		if split_type == "vsplit" then
			-- Vertical split to open note
			local success, result = pcall(buffer_utils.open_note, note_id, "vsplit")
			if not success then
				print("❌ Failed to open note: " .. result)
			end
		else
			-- Directly open note in current window (replace content)
			local success, result = pcall(buffer_utils.open_note, note_id, "edit")
			if not success then
				print("❌ Failed to open note: " .. result)
			end
		end

		-- Decide whether to return focus to tree view based on configuration
		if not config.options.tree.focus_after_open then
			-- Stay in note window
			return
		end
	else
		-- No target window found, create new vertical split
		print("💡 No suitable window found, creating new split")
		local success, result = pcall(buffer_utils.open_note, note_id, "vsplit")
		if not success then
			print("❌ Failed to open note: " .. result)
		end
	end
end

-- Rebuild tree display content
function M.rebuild_tree_display(tree_state)
	local tree_ui = require("joplin.ui.tree")
	tree_ui.rebuild_tree_display(tree_state)
end

-- Build folder hierarchy tree structure
function M.build_folder_tree(folders)
	local tree = {}
	local folder_map = {}

	-- Create folder id to folder object mapping
	for _, folder in ipairs(folders) do
		folder_map[folder.id] = folder
		folder.children = {}
	end

	-- Build parent-child relationships
	for _, folder in ipairs(folders) do
		if folder.parent_id and folder.parent_id ~= "" then
			-- Has parent folder, add to parent folder's children
			local parent = folder_map[folder.parent_id]
			if parent then
				table.insert(parent.children, folder)
			end
		else
			-- No parent folder, is root level
			table.insert(tree, folder)
		end
	end

	-- Sort root level folders
	table.sort(tree, function(a, b)
		return (a.title or "") < (b.title or "")
	end)

	-- Recursively sort child folders
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

-- Recursively display folder tree structure
function M.display_folder_tree(tree_state, folders, depth)
	for _, folder in ipairs(folders) do
		local indent = string.rep("  ", depth)
		local is_expanded = tree_state.expanded[folder.id]
		local icon = is_expanded and "📂" or "📁"
		local expand_icon = is_expanded and "▼" or "▶"

		-- Folder line
		local folder_line = string.format("%s%s %s %s", indent, expand_icon, icon, folder.title)
		table.insert(tree_state.lines, folder_line)
		table.insert(tree_state.line_data, {
			type = "folder",
			id = folder.id,
			title = folder.title,
			expanded = is_expanded,
			depth = depth,
		})

		-- If expanded, show content
		if is_expanded then
			-- First show child folders
			if folder.children and #folder.children > 0 then
				M.display_folder_tree(tree_state, folder.children, depth + 1)
			end

			-- Then show notes in this folder
			if tree_state.loading[folder.id] then
				-- Show loading indicator
				local loading_indent = string.rep("  ", depth + 1)
				local loading_line = string.format("%s⏳ Loading notes...", loading_indent)
				table.insert(tree_state.lines, loading_line)
				table.insert(tree_state.line_data, {
					type = "loading",
					id = folder.id,
					depth = depth + 1,
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
							depth = depth + 1,
						})
					end
				end
			end
		end
	end
end

-- Asynchronously load folder notes
function M.load_folder_notes_async(tree_state, folder_id, cursor_line)
	-- Set loading state
	tree_state.loading[folder_id] = true

	-- Immediately update display, show loading indicator
	M.rebuild_tree_display(tree_state)
	vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

	-- Show loading message
	local folder_name = ""
	for _, folder in ipairs(tree_state.folders) do
		if folder.id == folder_id then
			folder_name = folder.title
			break
		end
	end
	print("🔄 Loading notes for " .. folder_name .. "...")

	-- Use vim.defer_fn to simulate asynchronous behavior
	vim.defer_fn(function()
		local success, notes = api.get_notes(folder_id)
		if success then
			tree_state.folder_notes[folder_id] = notes
			print("✅ Loaded " .. #notes .. " notes")
		else
			tree_state.folder_notes[folder_id] = {}
			print("❌ Failed to load notes: " .. notes)
		end

		-- Clear loading state
		tree_state.loading[folder_id] = false

		-- Re-render
		M.rebuild_tree_display(tree_state)
		vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
	end, 10) -- 10ms delay to let UI update
end

-- Handle Enter key
function M.handle_tree_enter(tree_state)
	local config = require("joplin.config")
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		return
	end

	if line_data.type == "folder" then
		-- Toggle folder expand/collapse state
		local is_expanding = not tree_state.expanded[line_data.id]
		tree_state.expanded[line_data.id] = is_expanding

		-- If expanding and notes not yet loaded, load on demand
		if is_expanding and not tree_state.folder_notes[line_data.id] then
			M.load_folder_notes_async(tree_state, line_data.id, line_num)
		else
			M.rebuild_tree_display(tree_state)
			-- Keep cursor position
			vim.api.nvim_win_set_cursor(0, { line_num, 0 })
		end
	elseif line_data.type == "note" then
		-- Enter: Decide opening method based on configuration (default is replace upper window)
		local open_mode = config.options.keymaps.enter
		local target_win = M.find_target_window(tree_state)
		local split_type = (open_mode == "vsplit") and "vsplit" or "replace"

		M.open_note_in_window(line_data.id, target_win, split_type)

		-- If configuration requires keeping focus in tree view, switch back to tree view
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

-- Handle o key (open)
function M.handle_tree_open(tree_state)
	local config = require("joplin.config")
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		return
	end

	if line_data.type == "note" then
		-- o: Decide opening method based on configuration (default is vertical split)
		local open_mode = config.options.keymaps.o
		local target_win = M.find_target_window(tree_state)
		local split_type = (open_mode == "replace") and "replace" or "vsplit"

		M.open_note_in_window(line_data.id, target_win, split_type)

		-- If configuration requires keeping focus in tree view, switch back to tree view
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
		-- Pressing o on folder also expands/collapses
		M.handle_tree_enter(tree_state)
	end
end

-- Open note from tree view
function M.open_note_from_tree(note_id)
	print("🔍 Attempting to open note ID: " .. (note_id or "nil"))
	if not note_id then
		print("❌ Note ID is empty")
		return
	end

	local buffer_utils = require("joplin.utils.buffer")
	local success, result = pcall(buffer_utils.open_note, note_id, "vsplit")
	if not success then
		print("❌ Failed to open note: " .. result)
	else
		print("✅ Note opened successfully in vsplit")
	end
end

-- Refresh tree view
function M.refresh_tree(tree_state)
	-- Re-fetch folders
	local folders_success, folders = api.get_folders()
	if not folders_success then
		print("❌ Failed to refresh folders")
		return
	end

	tree_state.folders = folders

	-- Keep notes of expanded folders, clear notes of other folders
	local old_folder_notes = tree_state.folder_notes
	local old_expanded = tree_state.expanded
	tree_state.folder_notes = {}
	tree_state.expanded = {}

	-- Re-initialize expanded state and keep notes of expanded folders
	for _, folder in ipairs(folders) do
		local was_expanded = old_expanded[folder.id] or false
		tree_state.expanded[folder.id] = was_expanded

		-- If folder was previously expanded and has note data, keep this data
		if was_expanded and old_folder_notes[folder.id] then
			tree_state.folder_notes[folder.id] = old_folder_notes[folder.id]
		end
		-- Otherwise don't preload notes (load on demand)
	end

	M.rebuild_tree_display(tree_state)
	print("✅ Tree view refreshed")
end

-- Provide an alternative browser function that doesn't depend on Neo-tree
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

-- Display help information
function M.show_help()
	print("📖 Joplin.nvim User Guide")
	print("=======================")
	print("")
	print("🔧 Setup Requirements:")
	print("  1. Joplin Desktop Application must be running")
	print("  2. Web Clipper Service must be enabled in Joplin:")
	print("     • Go to Tools > Options > Web Clipper")
	print("     • Enable 'Enable Web Clipper Service'")
	print("     • Note the Authorization token")
	print("  3. Set token in environment variable:")
	print("     export JOPLIN_TOKEN='your_token_here'")
	print("  4. Or configure directly in Neovim:")
	print("     require('joplin').setup({ token = 'your_token_here' })")
	print("")
	print("🎯 Main Commands:")
	print("  :JoplinTree         - Open interactive tree browser")
	print("  :JoplinFind         - Open Telescope note search")
	print("  :JoplinSearch       - Open Telescope note search (same as JoplinFind)")
	print("  :JoplinFindNotebook - Open Telescope Notebook search")
	print("  :JoplinBrowse       - Open simple text list browser")
	print("  :JoplinPing         - Test Joplin connection status")
	print("  :JoplinHelp         - Display this help message")
	print("")
	print("⌨️  Shortcut Keys:")
	print("  " .. config.options.keymaps.search .. "         - Search notes (default: <leader>js)")
	print("  " .. config.options.keymaps.search_notebook .. "   - Search Notebook (default: <leader>jsnb)")
	print("  " .. config.options.keymaps.toggle_tree .. "       - Toggle tree view (default: <leader>jt)")
	print("")
	print("🔍 Note Search Features:")
	print("  • Uses Telescope for instant search experience")
	print("  • Search note titles and content")
	print("  • Provides note preview")
	print("  • Enter    - Open note in current window")
	print("  • Ctrl+V   - Open note in split window")
	print("")
	print("📁 Notebook Search Features:")
	print("  • Uses Telescope to search folders")
	print("  • Instant search of Notebook titles")
	print("  • Enter    - Expand folder in existing tree view (or create new tree view)")
	print("  • Automatically loads and displays all notes in folder")
	print("")
	print("🌳 Tree Browser Operations:")
	print("  Enter    - Open note in upper window (replace content)")
	print("  o        - Open note in upper window with vertical split")
	print("  a        - Create new item (name ending with '/' creates folder, otherwise creates note)")
	print("  A        - Create new folder (shortcut)")
	print("  d        - Delete note or folder (requires confirmation)")
	print("  r        - Rename note or folder")
	print("  m        - Move note or folder (use Telescope to select target)")
	print("  R        - Refresh tree structure")
	print("  q        - Close tree browser")
	print("")
	print("⚙️  Configuration Options:")
	print("  token                   - Joplin API token (alternative to environment variable)")
	print("  port                    - Web Clipper port (default: 41184)")
	print("  host                    - Web Clipper host (default: localhost)")
	print("  tree.height             - Tree view height (default: 12)")
	print("  tree.position           - Tree view position (default: 'botright')")
	print("  keymaps.enter           - Enter key behavior ('replace' or 'vsplit')")
	print("  keymaps.o               - o key behavior ('vsplit' or 'replace')")
	print("  keymaps.search          - Note search shortcut key (default: '<leader>js')")
	print("  keymaps.search_notebook - Notebook search shortcut key (default: '<leader>jsnb')")
	print("  keymaps.toggle_tree     - Tree view toggle shortcut key (default: '<leader>jt')")
	print("  startup.validate_on_load - Validate requirements on plugin load (default: true)")
	print("  startup.show_warnings   - Show startup warning messages (default: true)")
	print("")
	print("🚨 Troubleshooting:")
	print("  • 'Token Missing' Warning:")
	print("    - Set JOPLIN_TOKEN environment variable")
	print("    - Or use: require('joplin').setup({token = 'your_token'})")
	print("  • 'Web Clipper Unavailable' Warning:")
	print("    - Ensure Joplin application is running")
	print("    - Enable Web Clipper in Tools > Options > Web Clipper")
	print("    - Check if port 41184 is available")
	print("  • 'Invalid Token' Error:")
	print("    - Copy the correct token from Joplin Web Clipper settings")
	print("    - Token should be a long hexadecimal string")
	print("")
	print("⚠️  Important Reminders:")
	print("  • Ensure Joplin Web Clipper service is running")
	print("  • Search functionality requires telescope.nvim installation")
	print("  • Tree view opens at bottom, similar to quickfix window")
	print("  • Notes intelligently open in upper window")
	print("")
	print("💡 Need help? Please refer to GitHub repository or submit an issue")
end

-- Create new note
function M.create_note(folder_id, title)
	if not title or title == "" then
		print("❌ Note title cannot be empty")
		return
	end

	if not folder_id then
		print("❌ Folder ID is required")
		return
	end

	print("📝 Creating new note: " .. title)

	local success, result = api.create_note(title, "", folder_id)
	if not success then
		print("❌ Failed to create note: " .. result)
		vim.notify("Failed to create note: " .. result, vim.log.levels.ERROR)
		return
	end

	print("✅ Note created successfully: " .. result.id)
	vim.notify("Note created successfully: " .. title, vim.log.levels.INFO)

	-- Automatically open newly created note, using same logic as normal note opening
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)

	if tree_state then
		-- Use same logic as Enter key to open note
		local target_win = M.find_target_window(tree_state)
		local config = require("joplin.config")
		M.open_note_in_window(result.id, target_win, config.options.keymaps.enter)
		print("✅ New note opened in upper window")
	else
		-- If no tree structure, fallback to original method
		local buffer_utils = require("joplin.utils.buffer")
		local open_success, open_result = pcall(buffer_utils.open_note, result.id, "vsplit")
		if not open_success then
			print("❌ Failed to open new note: " .. open_result)
		else
			print("✅ New note opened in vsplit")
		end
	end

	return result
end

-- Delete note
function M.delete_note(note_id)
	if not note_id then
		print("❌ Note ID is required")
		return
	end

	-- Confirm deletion
	local confirm = vim.fn.input("Are you sure you want to delete this note? (y/n): ")
	if confirm ~= "y" and confirm ~= "Y" then
		print("❌ Deletion cancelled")
		return false
	end

	print("🗑️  Deleting note ID: " .. note_id)

	local success, result = api.delete_note(note_id)
	if not success then
		print("❌ Failed to delete note: " .. result)
		vim.notify("Failed to delete note: " .. result, vim.log.levels.ERROR)
		return false
	end

	print("✅ Note deleted successfully")
	vim.notify("Note deleted successfully", vim.log.levels.INFO)

	return true
end

-- Delete folder
function M.delete_folder(folder_id)
	if not folder_id then
		print("❌ Folder ID is required")
		return false
	end

	-- Confirm deletion
	local confirm = vim.fn.input("Are you sure you want to delete this folder? (y/n): ")
	if confirm ~= "y" and confirm ~= "Y" then
		print("❌ Deletion cancelled")
		return false
	end

	print("🗑️  Deleting folder ID: " .. folder_id)

	local success, result = api.delete_folder(folder_id)
	if not success then
		print("❌ Failed to delete folder: " .. result)
		vim.notify("Failed to delete folder: " .. result, vim.log.levels.ERROR)
		return false
	end

	print("✅ Folder deleted successfully")
	vim.notify("Folder deleted successfully", vim.log.levels.INFO)

	return true
end

-- Rename note
function M.rename_note(note_id, new_title)
	if not note_id then
		print("❌ Note ID is required")
		return false
	end

	if not new_title or new_title == "" then
		print("❌ New note title is required")
		return false
	end

	print("📝 Renaming note ID: " .. note_id .. " -> " .. new_title)

	local success, result = api.update_note(note_id, { title = new_title })
	if not success then
		print("❌ Failed to rename note: " .. result)
		vim.notify("Failed to rename note: " .. result, vim.log.levels.ERROR)
		return false
	end

	print("✅ Note renamed successfully")
	vim.notify("Note renamed successfully", vim.log.levels.INFO)

	return true
end

-- Rename folder
function M.rename_folder(folder_id, new_title)
	if not folder_id then
		print("❌ Folder ID is required")
		return false
	end

	if not new_title or new_title == "" then
		print("❌ New folder title is required")
		return false
	end

	print("📁 Renaming folder ID: " .. folder_id .. " -> " .. new_title)

	local success, result = api.update_folder(folder_id, { title = new_title })
	if not success then
		print("❌ Failed to rename folder: " .. result)
		vim.notify("Failed to rename folder: " .. result, vim.log.levels.ERROR)
		return false
	end

	print("✅ Folder renamed successfully")
	vim.notify("Folder renamed successfully", vim.log.levels.INFO)

	return true
end

-- Get tree_state for the specified buffer
function M.get_tree_state_for_buffer(bufnr)
	local tree_ui = require("joplin.ui.tree")
	return tree_ui.get_tree_state_for_buffer(bufnr)
end

-- Create new item from tree (note or folder)
function M.create_item_from_tree()
	-- Get tree_state for the current buffer
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)

	if not tree_state then
		print("❌ Cannot find tree view state")
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		print("❌ Cannot parse current line")
		return
	end

	local parent_folder_id = nil

	-- If the current line is a folder, use it as the parent folder
	if line_data.type == "folder" then
		parent_folder_id = line_data.id
	-- If the current line is a note, use its parent folder
	elseif line_data.type == "note" then
		-- Need to find the parent folder ID of the note
		local success, note = api.get_note(line_data.id)
		if success and note.parent_id then
			parent_folder_id = note.parent_id
		else
			print("❌ Cannot determine parent folder, please create new item on a folder line")
			return
		end
	else
		print("❌ Please select a folder or note to create a new item")
		return
	end

	-- Show input dialog
	local input = vim.fn.input("Create new item (end with '/' to create a folder): ")
	if input == "" then
		print("❌ Create operation cancelled")
		return
	end

	local result = nil

	-- Check if it ends with '/'
	if input:sub(-1) == "/" then
		-- Create folder
		local folder_name = input:sub(1, -2) -- remove last '/'
		if folder_name == "" then
			print("❌ Folder name cannot be empty")
			return
		end
		result = M.create_folder(parent_folder_id, folder_name)
	else
		-- Create note
		result = M.create_note(parent_folder_id, input)
	end

	-- If creation is successful, update local state immediately
	if result then
		print("✅ Item created successfully, updating display...")

		-- If a folder was created, add it to the local state immediately
		if input:sub(-1) == "/" then
			-- Add new folder to local state
			local new_folder = {
				id = result.id,
				title = result.title,
				parent_id = parent_folder_id,
			}
			table.insert(tree_state.folders, new_folder)
			tree_state.expanded[result.id] = false
			tree_state.loading[result.id] = false
		else
			-- If a note was created, add the new note to the loaded notes list
			if tree_state.folder_notes[parent_folder_id] then
				-- If the notes for this folder are already loaded, add the new note to the list
				local new_note = {
					id = result.id,
					title = result.title,
					parent_id = parent_folder_id,
					created_time = result.created_time,
					updated_time = result.updated_time,
				}
				table.insert(tree_state.folder_notes[parent_folder_id], new_note)

				-- Sort note list by title
				table.sort(tree_state.folder_notes[parent_folder_id], function(a, b)
					return (a.title or "") < (b.title or "")
				end)
			else
				-- If the notes for this folder are not yet loaded, do nothing
				-- The full list including the new note will be loaded automatically next time it is expanded
			end
		end

		-- Rebuild display immediately
		M.rebuild_tree_display(tree_state)
	end
end

-- Create new folder from tree view (A key shortcut)
function M.create_folder_from_tree()
	-- Get tree_state for the current buffer
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)

	if not tree_state then
		print("❌ Cannot find tree view state")
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		print("❌ Cannot parse current line")
		return
	end

	local parent_folder_id = nil

	-- If the current line is a folder, use it as the parent folder
	if line_data.type == "folder" then
		parent_folder_id = line_data.id
	-- If the current line is a note, use its parent folder
	elseif line_data.type == "note" then
		-- Need to find the parent folder ID of the note
		local success, note = api.get_note(line_data.id)
		if success and note.parent_id then
			parent_folder_id = note.parent_id
		else
			print("❌ Cannot determine parent folder, please create new folder on a folder line")
			return
		end
	else
		print("❌ Please select a folder or note to create a new folder")
		return
	end

	-- Show input dialog
	local folder_name = vim.fn.input("New folder name: ")
	if folder_name == "" then
		print("❌ Create operation cancelled")
		return
	end

	local result = M.create_folder(parent_folder_id, folder_name)

	-- If creation is successful, update local state immediately
	if result then
		print("✅ Folder created successfully, updating display...")

		-- Add new folder to local state
		local new_folder = {
			id = result.id,
			title = result.title,
			parent_id = parent_folder_id,
		}
		table.insert(tree_state.folders, new_folder)
		tree_state.expanded[result.id] = false
		tree_state.loading[result.id] = false

		-- Rebuild display immediately
		M.rebuild_tree_display(tree_state)
	end
end

-- Lightweight tree view refresh (only update folder list, do not reload all notes)
function M.refresh_tree_lightweight(tree_state)
	-- Re-fetch folder list
	local folders_success, folders = api.get_folders()
	if not folders_success then
		print("❌ Failed to refresh folders")
		return
	end

	-- Update folder list
	tree_state.folders = folders

	-- Initialize state for new folders (does not affect existing folders)
	for _, folder in ipairs(folders) do
		if tree_state.expanded[folder.id] == nil then
			tree_state.expanded[folder.id] = false
		end
		if tree_state.loading[folder.id] == nil then
			tree_state.loading[folder.id] = false
		end
	end

	-- Rebuild display content
	M.rebuild_tree_display(tree_state)
	print("✅ Tree view updated")
end

-- Create new folder
function M.create_folder(parent_id, title)
	if not title or title == "" then
		print("❌ Folder title cannot be empty")
		return
	end

	if not parent_id then
		print("❌ Parent folder ID is required")
		return
	end

	print("📁 Creating new folder: " .. title)

	local success, result = api.create_folder(title, parent_id)
	if not success then
		print("❌ Failed to create folder: " .. result)
		vim.notify("Failed to create folder: " .. result, vim.log.levels.ERROR)
		return
	end

	print("✅ Folder created successfully: " .. result.id)
	vim.notify("Folder created successfully: " .. title, vim.log.levels.INFO)

	return result
end

-- Delete note or folder from tree view
function M.delete_item_from_tree()
	-- Get tree_state for the current buffer
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)

	if not tree_state then
		print("❌ Cannot find tree view state")
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		print("❌ Cannot parse current line")
		return
	end

	if line_data.type ~= "note" and line_data.type ~= "folder" then
		print("❌ Only notes or folders can be deleted")
		return
	end

	local success
	if line_data.type == "note" then
		success = M.delete_note(line_data.id)
	else -- folder
		success = M.delete_folder(line_data.id)
	end

	-- If deletion is successful, update local state immediately
	if success then
		if line_data.type == "note" then
			print("✅ Note deleted successfully, updating display...")

			-- Remove the note from the loaded notes list
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
			print("✅ Folder deleted successfully, updating display...")

			-- Remove the deleted folder from the folder list
			if tree_state.folders then
				for i, folder in ipairs(tree_state.folders) do
					if folder.id == line_data.id then
						table.remove(tree_state.folders, i)
						break
					end
				end
			end

			-- Clear cache related to this folder
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

		-- Rebuild tree display
		M.rebuild_tree_display(tree_state)
	end
end

-- Rename note or folder from tree view
function M.rename_item_from_tree()
	-- Get tree_state for the current buffer
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)

	if not tree_state then
		print("❌ Cannot find tree view state")
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		print("❌ Cannot parse current line")
		return
	end

	if line_data.type ~= "note" and line_data.type ~= "folder" then
		print("❌ Only notes or folders can be renamed")
		return
	end

	-- Get current name as default value
	local current_title = line_data.title or ""
	if line_data.type == "folder" then
		-- Get the exact title from the folders list
		for _, folder in ipairs(tree_state.folders or {}) do
			if folder.id == line_data.id then
				current_title = folder.title or ""
				break
			end
		end
	else -- note
		-- Get the exact title from folder_notes
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

	-- Show input dialog, using the current title as the default value
	local new_title = vim.fn.input({
		prompt = "New name: ",
		default = current_title,
		completion = "file",
	})

	-- Check if the user cancelled the input
	if not new_title or new_title == "" then
		print("❌ Rename operation cancelled")
		return
	end

	-- Check if the name has changed
	if new_title == current_title then
		print("⚠️  Name has not changed")
		return
	end

	local success
	if line_data.type == "note" then
		success = M.rename_note(line_data.id, new_title)
	else -- folder
		success = M.rename_folder(line_data.id, new_title)
	end

	-- If renaming is successful, update local state immediately
	if success then
		if line_data.type == "note" then
			print("✅ Note renamed successfully, updating display...")

			-- Update the title in the loaded notes list
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
			print("✅ Folder renamed successfully, updating display...")

			-- Update the title in the folder list
			for _, folder in ipairs(tree_state.folders or {}) do
				if folder.id == line_data.id then
					folder.title = new_title
					break
				end
			end
		end

		-- Rebuild tree display
		M.rebuild_tree_display(tree_state)
	end
end

-- Search notes (Telescope fuzzy finder)
function M.search_notes(default_text)
	local search_ui = require("joplin.ui.search")

	-- Check if Telescope is available
	if not search_ui.is_telescope_available() then
		vim.notify(
			"Telescope is not installed. Please install telescope.nvim to use search functionality.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Check Joplin connection
	local ping_ok, ping_result = api.ping()
	if not ping_ok then
		vim.notify("Cannot connect to Joplin: " .. ping_result, vim.log.levels.ERROR)
		return
	end

	-- Open search interface
	search_ui.search_notes({
		default_text = default_text,
		layout_strategy = "horizontal",
		layout_config = {
			height = 0.8,
			width = 0.9,
			preview_width = 0.6,
		},
	})
end

-- Search notebooks (Telescope fuzzy finder)
function M.search_notebooks(default_text)
	local search_ui = require("joplin.ui.search")

	-- Check if Telescope is available
	if not search_ui.is_telescope_available() then
		vim.notify(
			"Telescope is not installed. Please install telescope.nvim to use search functionality.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Check Joplin connection
	local ping_ok, ping_result = api.ping()
	if not ping_ok then
		vim.notify("Cannot connect to Joplin: " .. ping_result, vim.log.levels.ERROR)
		return
	end

	-- Open search interface
	search_ui.search_notebooks({
		default_text = default_text,
		layout_strategy = "horizontal",
		layout_config = {
			height = 0.6,
			width = 0.8,
		},
	})
end
-- For debugging: verify folder expansion functionality
function M.debug_expand_folder(folder_id)
	print("=== Debug Expand Folder ===")
	print("Target folder ID: " .. (folder_id or "nil"))

	local tree_ui = require("joplin.ui.tree")
	local api = require("joplin.api.client")

	-- Check API connection
	local ping_success, ping_result = api.ping()
	if not ping_success then
		print("❌ API connection failed: " .. ping_result)
		return
	end
	print("✅ API connected: " .. ping_result)

	-- Get all folders
	local folders_success, folders = api.get_folders()
	if not folders_success then
		print("❌ Failed to get folders: " .. folders)
		return
	end
	print("✅ Retrieved " .. #folders .. " folders")

	-- Check if the target folder exists
	local target_folder = nil
	for _, folder in ipairs(folders) do
		if folder.id == folder_id then
			target_folder = folder
			break
		end
	end

	if not target_folder then
		print("❌ Target folder not found!")
		print("Available folders:")
		for i, folder in ipairs(folders) do
			print("  " .. i .. ". ID: " .. folder.id .. ", Title: " .. (folder.title or "Untitled"))
		end
		return
	end

	print("✅ Found target folder: " .. (target_folder.title or "Untitled"))
	print("    Parent ID: " .. (target_folder.parent_id or "none"))

	-- Check tree view state
	local tree_winid, tree_bufnr = tree_ui.find_active_tree_window()
	if tree_winid then
		print("✅ Found active tree window: " .. tree_winid)
		print("    Buffer: " .. tree_bufnr)
	else
		print("⚠️  No active tree window found")
	end

	print("=== Attempting expand ===")
	M.expand_to_folder(folder_id)
end

-- Expand to the specified folder and display its notes
function M.expand_to_folder(folder_id)
	if not folder_id then
		vim.notify("Folder ID is required", vim.log.levels.ERROR)
		return
	end

	print("🔍 Expanding to folder: " .. folder_id)

	local tree_ui = require("joplin.ui.tree")

	-- Check if there is an active tree view window
	local tree_winid, tree_bufnr = tree_ui.find_active_tree_window()

	if tree_winid then
		-- If there is an existing tree view window, expand directly in it
		print("✅ Using existing tree view")
		-- Try to expand immediately, if it fails, retry later
		local success = tree_ui.expand_to_folder(folder_id)
		if not success then
			print("⏳ First expand failed, retrying...")
			vim.defer_fn(function()
				local retry_success = tree_ui.expand_to_folder(folder_id)
				if not retry_success then
					print("❌ Expand failed, the folder may not exist")
				end
			end, 100)
		end
	else
		-- If there is no tree view window, create a new one
		print("📂 Creating new tree view")
		M.create_tree()

		-- Wait for the tree to be created before expanding
		vim.defer_fn(function()
			local success = tree_ui.expand_to_folder(folder_id)
			if not success then
				print("⏳ Expand failed after tree view creation, retrying...")
				vim.defer_fn(function()
					tree_ui.expand_to_folder(folder_id)
				end, 200) -- longer delay for newly created tree view
			end
		end, 150) -- slightly increase delay to ensure tree view is fully created
	end
end

-- Move note to specified folder
function M.move_note(note_id, new_parent_id)
	if not note_id then
		print("❌ Note ID is required")
		return false
	end

	if not new_parent_id then
		print("❌ Target folder ID is required")
		return false
	end

	print("📝 Moving note ID: " .. note_id .. " -> Folder ID: " .. new_parent_id)

	local success, result = api.move_note(note_id, new_parent_id)
	if not success then
		print("❌ Failed to move note: " .. result)
		vim.notify("Failed to move note: " .. result, vim.log.levels.ERROR)
		return false
	end

	print("✅ Note moved successfully")
	vim.notify("Note moved successfully", vim.log.levels.INFO)

	return true
end

-- Move folder to specified parent folder
function M.move_folder(folder_id, new_parent_id)
	if not folder_id then
		print("❌ Folder ID is required")
		return false
	end

	if not new_parent_id then
		print("❌ Target parent folder ID is required")
		return false
	end

	print("📁 Moving folder ID: " .. folder_id .. " -> Parent folder ID: " .. new_parent_id)

	local success, result = api.move_folder(folder_id, new_parent_id)
	if not success then
		print("❌ Failed to move folder: " .. result)
		vim.notify("Failed to move folder: " .. result, vim.log.levels.ERROR)
		return false
	end

	print("✅ Folder moved successfully")
	vim.notify("Folder moved successfully", vim.log.levels.INFO)

	return true
end

-- Move note or folder from tree view
function M.move_item_from_tree()
	-- Get tree_state for the current buffer
	local bufnr = vim.api.nvim_get_current_buf()
	local tree_state = M.get_tree_state_for_buffer(bufnr)

	if not tree_state then
		print("❌ Cannot find tree view state")
		return
	end

	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line_data = tree_state.line_data[line_num]

	if not line_data then
		print("❌ Cannot parse current line")
		return
	end

	if line_data.type ~= "note" and line_data.type ~= "folder" then
		print("❌ Only notes or folders can be moved")
		return
	end

	-- Get item information
	local item_type = line_data.type
	local item_id = line_data.id
	local item_title = line_data.title or "Unknown"

	print("📦 Preparing to move " .. item_type .. ": " .. item_title)

	-- Check if Telescope is available
	local search_ui = require("joplin.ui.search")
	if not search_ui.is_telescope_available() then
		vim.notify(
			"Telescope is not installed. Please install telescope.nvim to use move functionality.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Open move destination selection dialog
	search_ui.search_move_destination(item_type, item_id, item_title, {
		layout_strategy = "horizontal",
		layout_config = {
			height = 0.6,
			width = 0.8,
		},
	})
end

-- Auto-sync function (for automatic triggering)
local last_synced_note = nil

function M.auto_sync_to_current_note()
	local buffer_utils = require("joplin.utils.buffer")
	local tree_ui = require("joplin.ui.tree")

	-- Check if auto-sync is enabled
	local config = require("joplin.config")
	if not config.options.tree.auto_sync then
		return
	end

	-- Check if the current buffer is a Joplin note
	local note_info = buffer_utils.get_note_info()
	if not note_info then
		return
	end

	-- Check if there is an active tree window
	local tree_bufnr = tree_ui.find_active_tree_buffer()
	if not tree_bufnr then
		return
	end

	-- Avoid repeatedly syncing the same note
	if last_synced_note == note_info.note_id then
		return
	end

	-- Check if the note has a parent folder
	if not note_info.parent_id or note_info.parent_id == "" then
		return
	end

	-- Record the currently synced note to avoid repetition
	last_synced_note = note_info.note_id

	-- Silently execute synchronization (the third parameter being true indicates silent mode)
	tree_ui.expand_and_highlight_note(note_info.parent_id, note_info.note_id, true)
end

return M
