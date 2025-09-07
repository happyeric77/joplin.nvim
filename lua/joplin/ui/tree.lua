-- Joplin Tree UI - Custom tree browser
-- This module contains the main tree view functionality, independent of Neo-tree

local api = require("joplin.api.client")

local M = {}

-- Tree state management
local buffer_tree_states = {}

-- Setup tree view shortcut keys
function M.setup_tree_keymaps(bufnr)
	local tree_state = buffer_tree_states[bufnr]
	if not tree_state then
		print("❌ Cannot find tree view state")
		return
	end

	-- o/Enter: Expand/collapse folder or open note
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

	-- R: Refresh
	vim.api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").refresh_tree(tree_state)
		end,
	})

	-- q: Close
	vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>q<cr>", {
		noremap = true,
		silent = true,
	})

	-- a: Create new note in current folder
	vim.api.nvim_buf_set_keymap(bufnr, "n", "a", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").create_item_from_tree()
		end,
	})

	-- A: Create new folder in current folder
	vim.api.nvim_buf_set_keymap(bufnr, "n", "A", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").create_folder_from_tree()
		end,
	})

	-- d: Delete note or folder
	vim.api.nvim_buf_set_keymap(bufnr, "n", "d", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").delete_item_from_tree()
		end,
	})

	-- r: Rename note or folder
	vim.api.nvim_buf_set_keymap(bufnr, "n", "r", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").rename_item_from_tree()
		end,
	})

	-- m: Move note or folder
	vim.api.nvim_buf_set_keymap(bufnr, "n", "m", "", {
		noremap = true,
		silent = true,
		callback = function()
			require("joplin").move_item_from_tree()
		end,
	})
end

-- Rebuild tree display
function M.rebuild_tree_display(tree_state)
	if not tree_state or not tree_state.bufnr then
		print("❌ Invalid tree state")
		return
	end

	-- Rebuild display content
	tree_state.lines = {}
	tree_state.line_data = {}

	-- Title
	table.insert(tree_state.lines, "📋 Joplin Notes")
	table.insert(tree_state.line_data, { type = "header" })
	table.insert(tree_state.lines, "")
	table.insert(tree_state.line_data, { type = "empty" })

	-- Build and display hierarchical tree structure
	local folder_tree = require("joplin").build_folder_tree(tree_state.folders or {})
	require("joplin").display_folder_tree(tree_state, folder_tree, 0)

	-- Update buffer content
	vim.api.nvim_buf_set_option(tree_state.bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(tree_state.bufnr, 0, -1, false, tree_state.lines)
	vim.api.nvim_buf_set_option(tree_state.bufnr, "modifiable", false)
end

-- Create tree browser
function M.create_tree()
	local success, error_msg = pcall(function()
		local config = require("joplin.config")
		local tree_height = config.options.tree.height
		local tree_position = config.options.tree.position

		-- Record current window ID as target window for opening notes later
		local original_win = vim.api.nvim_get_current_win()

		local bufnr

		-- Always create new buffer
		bufnr = vim.api.nvim_create_buf(false, true)
		local timestamp = os.time()
		vim.api.nvim_buf_set_name(bufnr, "Joplin Tree " .. timestamp)

		vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
		vim.api.nvim_buf_set_option(bufnr, "filetype", "joplin-tree")
		vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

		print("🔄 Loading folder structure...")

		-- Get Joplin folder data
		local folders_success, folders = api.get_folders()
		if not folders_success then
			error("Failed to fetch folders: " .. folders)
		end

		print("✅ Loaded " .. #folders .. " folders, building tree structure...")

		-- Build tree structure state management
		local tree_state = {
			bufnr = bufnr,
			folders = folders,
			folder_notes = {},
			expanded = {},
			loading = {},
			lines = {},
			line_data = {},
			original_win = original_win, -- Record original window
		}

		-- Initial state: all folders are collapsed
		for _, folder in ipairs(folders) do
			tree_state.expanded[folder.id] = false
			tree_state.loading[folder.id] = false
		end

		-- Rebuild display content
		M.rebuild_tree_display(tree_state)

		-- Store tree_state for use by other functions
		buffer_tree_states[bufnr] = tree_state

		-- Cleanup autocmd: clear state when buffer is closed
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = bufnr,
			callback = function()
				buffer_tree_states[bufnr] = nil
			end,
		})

		-- Setup shortcut keys
		M.setup_tree_keymaps(bufnr)

		-- Open tree view using configured position and height
		vim.cmd(tree_position .. " " .. tree_height .. "split")
		vim.api.nvim_set_current_buf(bufnr)

		print("✅ Joplin tree view opened")
		print("💡 Press 'Enter' to open note in upper window, 'o' for vertical split, 'q' to close tree view")
	end)

	if not success then
		print("❌ Failed to open tree view: " .. error_msg)
		vim.notify("Failed to open Joplin tree: " .. error_msg, vim.log.levels.ERROR)
	end
end

-- Get tree_state for specified buffer
function M.get_tree_state_for_buffer(bufnr)
	return buffer_tree_states[bufnr]
end

-- Find active tree buffer
function M.find_active_tree_buffer()
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			return bufnr
		end
	end
	return nil
end

-- Find active window displaying tree view
function M.find_active_tree_window()
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			-- Check if any window is displaying this buffer
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

-- Find and highlight specified note in tree window (without switching focus)
function M.highlight_note_in_tree(note_id)
	local tree_bufnr = M.find_active_tree_buffer()
	if not tree_bufnr then
		return false
	end

	local tree_state = buffer_tree_states[tree_bufnr]
	if not tree_state then
		return false
	end

	-- Find specified note in tree display
	for line_num, line_data in ipairs(tree_state.line_data) do
		if line_data.type == "note" and line_data.id == note_id then
			-- Find tree window
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_bufnr then
					-- Record current active window
					local current_win = vim.api.nvim_get_current_win()

					-- Use nvim_win_call to set cursor in tree window without switching focus
					vim.api.nvim_win_call(winid, function()
						vim.api.nvim_win_set_cursor(0, { line_num, 0 })
					end)

					-- Ensure focus stays in original window
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

-- Expand to specified folder and highlight specified note (silent mode)
function M.expand_and_highlight_note(parent_folder_id, note_id, silent)
	silent = silent or false

	if not silent then
		print("🔄 Expanding to folder: " .. parent_folder_id)
	end

	-- First expand to target folder, passing silent parameter
	M.expand_to_folder(parent_folder_id, silent)

	-- Wait for tree rebuild to complete then try to highlight note
	vim.schedule(function()
		-- Give a brief delay to ensure tree rebuild is complete
		vim.defer_fn(function()
			local highlighted = M.highlight_note_in_tree(note_id)
			if not silent and not highlighted then
				-- Only provide diagnostic information in non-silent mode
				local tree_bufnr = M.find_active_tree_buffer()
				if tree_bufnr then
					local tree_state = buffer_tree_states[tree_bufnr]
					if tree_state and tree_state.folder_notes[parent_folder_id] then
						local notes = tree_state.folder_notes[parent_folder_id]
						print("📝 Total " .. #notes .. " notes in folder")
						for i, note in ipairs(notes) do
							if note.id == note_id then
								print("✅ Target note is indeed in folder: " .. note.title)
								break
							end
						end
					end
				end
			end
		end, 200) -- 200ms delay
	end)
end

-- Build mapping from folder ID to folder object
function M.build_folder_map(folders)
	local folder_map = {}
	for _, folder in ipairs(folders) do
		folder_map[folder.id] = folder
	end
	return folder_map
end

-- Get path to target folder (list of folder IDs from root to target)
function M.get_folder_path(target_folder_id, folder_map)
	local path = {}
	local current_id = target_folder_id

	-- Trace upward from target folder to root folder
	while current_id do
		table.insert(path, 1, current_id)
		local folder = folder_map[current_id]
		if not folder then
			break
		end
		current_id = folder.parent_id
		-- If parent_id is empty or blank, reached root level
		if not current_id or current_id == "" then
			break
		end
	end

	return path
end

-- Expand to specified folder and load its notes
function M.expand_to_folder(target_folder_id, silent)
	silent = silent or false

	if not silent then
		print("🔍 Start locating notebooks: " .. target_folder_id)
	end

	-- Find active tree view buffer
	local tree_bufnr = nil
	for bufnr, _ in pairs(buffer_tree_states) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			tree_bufnr = bufnr
			break
		end
	end

	if not tree_bufnr then
		if not silent then
			print("❌ Unable to find active tree view")
		end
		return false
	end

	local tree_state = buffer_tree_states[tree_bufnr]
	if not tree_state then
		if not silent then
			print("❌ Unable to find tree view state")
		end
		return false
	end

	-- Ensure folders data is up-to-date (for cases using existing tree view)
	if not tree_state.folders or #tree_state.folders == 0 then
		if not silent then
			print("🔄 Loading folder data...")
		end
		local api = require("joplin.api.client")
		local success, folders = api.get_folders()
		if success then
			tree_state.folders = folders
			-- Initialize state for new folders
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
				print("❌ Failed to load folder data: " .. folders)
			end
			return false
		end
	end

	-- Build folder mapping
	local folder_map = M.build_folder_map(tree_state.folders)

	-- Check if target folder exists
	if not folder_map[target_folder_id] then
		if not silent then
			print("❌ Unable to find notebook: " .. target_folder_id)
			print("🐛 Available notebook ID: ")
			for id, folder in pairs(folder_map) do
				print("  - " .. id .. ": " .. (folder.title or "Untitled"))
			end
		end
		return false
	end

	-- Get path to target folder
	local path = M.get_folder_path(target_folder_id, folder_map)

	if not silent then
		print("🗂️  Expend directory (" .. #path .. " level): " .. table.concat(path, " -> "))
		for i, folder_id in ipairs(path) do
			local folder_name = folder_map[folder_id] and folder_map[folder_id].title or "Unknown"
			print("  " .. i .. ". " .. folder_id .. " (" .. folder_name .. ")")
		end
	end

	-- Expand each folder along the path
	for _, folder_id in ipairs(path) do
		if not tree_state.expanded[folder_id] then
			tree_state.expanded[folder_id] = true

			-- Load notes for this folder (if not already loaded)
			if not tree_state.folder_notes[folder_id] then
				tree_state.loading[folder_id] = true

				-- Synchronously load notes (keep in sync during expansion)
				local success, notes = api.get_notes(folder_id)
				if success then
					tree_state.folder_notes[folder_id] = notes
					if not silent then
						local folder_name = folder_map[folder_id].title or "Unknown"
						if #notes > 0 then
							print("✅ " .. #notes .. " notes successfully loaded (" .. folder_name .. ")")
						else
							print("📝 Notebook opened，but no notes (" .. folder_name .. ")")
						end
					end
				else
					tree_state.folder_notes[folder_id] = {}
					if not silent then
						print("❌ Failed to load notes: " .. notes)
					end
				end
				tree_state.loading[folder_id] = false
			end
		end
	end

	-- Rebuild tree display
	local joplin = require("joplin")
	joplin.rebuild_tree_display(tree_state)

	-- Find line number of target folder in display and set cursor
	for line_num, line_data in ipairs(tree_state.line_data) do
		if line_data.type == "folder" and line_data.id == target_folder_id then
			-- Find the tree view window
			local tree_wins = vim.api.nvim_list_wins()
			for _, winid in ipairs(tree_wins) do
				local bufnr = vim.api.nvim_win_get_buf(winid)
				if bufnr == tree_bufnr then
					if silent then
						-- Silent mode: use nvim_win_call without switching focus
						local current_win = vim.api.nvim_get_current_win()
						vim.api.nvim_win_call(winid, function()
							vim.api.nvim_win_set_cursor(0, { line_num, 0 })
						end)
						-- Ensure focus stays in original window
						if vim.api.nvim_get_current_win() ~= current_win then
							vim.api.nvim_set_current_win(current_win)
						end
					else
						-- Non-silent mode: switch to tree window normally
						vim.api.nvim_set_current_win(winid)
						vim.api.nvim_win_set_cursor(winid, { line_num, 0 })
						local folder_name = folder_map[target_folder_id].title or "Unknown"
						local note_count = tree_state.folder_notes[target_folder_id]
								and #tree_state.folder_notes[target_folder_id]
							or 0
						print("✅ Notbook found: " .. folder_name .. " (" .. note_count .. " notes)")
					end
					return true
				end
			end
			break
		end
	end

	if not silent then
		print("⚠️  Folder expanded but cursor not located")
	end
	return true
end

return M
