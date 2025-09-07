local client = require("joplin.api.client")
local buffer_utils = require("joplin.utils.buffer")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local entry_display = require("telescope.pickers.entry_display")

local M = {}

-- Folder cache (module level)
local _folder_cache = nil
local _folder_map_cache = nil
local _cache_timestamp = 0
local CACHE_TTL = 300000 -- 5 minute cache

-- Get cached folder mapping
local function get_cached_folder_map()
	local current_time = vim.loop.now()

	-- Check if cache is expired
	if not _folder_cache or not _folder_map_cache or (current_time - _cache_timestamp) > CACHE_TTL then
		local success, folders = client.get_folders()
		if success then
			_folder_cache = folders
			_folder_map_cache = {}
			for _, folder in ipairs(folders) do
				_folder_map_cache[folder.id] = folder
			end
			_cache_timestamp = current_time
		else
			return nil
		end
	end

	return _folder_map_cache
end

-- Build full path for note
local function build_note_path(note, folder_map)
	if not note.parent_id or note.parent_id == "" then
		return "📕 Root"
	end

	local path_parts = {}
	local current_id = note.parent_id

	-- Trace upward to root folder
	while current_id and current_id ~= "" do
		local folder = folder_map[current_id]
		if not folder then
			break
		end

		table.insert(path_parts, 1, folder.title or "Untitled")
		current_id = folder.parent_id
	end

	if #path_parts == 0 then
		return "📕 Root"
	else
		return "📕 " .. table.concat(path_parts, "/")
	end
end

-- Format search result display
local function format_entry(note)
	local title = note.title or "Untitled"
	local updated = note.updated_time or 0
	local date_str = os.date("%Y-%m-%d %H:%M", updated / 1000)

	return string.format("%-40s │ %s", title, date_str)
end

-- Create note displayer (using dynamic width)
local function create_note_displayer(opts)
	opts = opts or {}
	local display_mode = opts.display_mode or "balanced" -- balanced, compact, detailed

	if display_mode == "compact" then
		-- Compact mode: only show title and path
		return entry_display.create({
			separator = " ",
			hl_chars = { ["/"] = "TelescopePathSeparator" },
			items = {
				{ width = 0.6 }, -- 60% width for title
				{ remaining = true }, -- Remaining width for path
			},
		})
	elseif display_mode == "detailed" then
		-- Detailed mode: title, path, date each occupy fixed width
		return entry_display.create({
			separator = " │ ",
			hl_chars = {
				["│"] = "TelescopeBorder",
				["/"] = "TelescopePathSeparator",
			},
			items = {
				{ width = 45 }, -- Fixed width for title
				{ width = 35 }, -- Fixed width for path
				{ remaining = true }, -- Remaining width for date
			},
		})
	else
		-- Balanced mode (default): dynamically allocate width
		return entry_display.create({
			separator = " │ ",
			hl_chars = {
				["│"] = "TelescopeBorder",
				["/"] = "TelescopePathSeparator",
			},
			items = {
				{ width = 0.4 }, -- 40% width for title
				{ width = 0.35 }, -- 35% width for path
				{ remaining = true }, -- Remaining width for date
			},
		})
	end
end

-- Format search result display (with path)
local function format_entry_with_path(note, folder_map, displayer, opts)
	opts = opts or {}
	local display_mode = opts.display_mode or "balanced"

	local title = note.title or "Untitled"
	local updated = note.updated_time or 0
	local date_str = os.date("%Y-%m-%d %H:%M", updated / 1000)
	local path = build_note_path(note, folder_map)

	return {
		value = note,
		display = function(entry)
			if display_mode == "compact" then
				return displayer({
					{ title, "TelescopeResultsIdentifier" },
					{ path, "TelescopeResultsComment" },
				})
			else
				return displayer({
					{ title, "TelescopeResultsIdentifier" },
					{ path, "TelescopeResultsComment" },
					{ date_str, "TelescopeResultsNumber" },
				})
			end
		end,
		ordinal = title .. " " .. path, -- Include path when searching
	}
end

-- Format notebook search result display
local function format_notebook_entry(notebook)
	local title = notebook.title or "Untitled"
	local updated = notebook.updated_time or 0
	local date_str = os.date("%Y-%m-%d %H:%M", updated / 1000)

	return string.format("📁 %-37s │ %s", title, date_str)
end

-- Create note previewer
local function create_note_previewer()
	return previewers.new_buffer_previewer({
		title = "Note Preview",
		define_preview = function(self, entry, status)
			local note_id = entry.value.id
			local success, note_data = client.get_note(note_id)

			if success and note_data then
				local lines = {}

				-- Add title
				table.insert(lines, "# " .. (note_data.title or "Untitled"))
				table.insert(lines, "")

				-- Add metadata
				local created = note_data.created_time or 0
				local updated = note_data.updated_time or 0
				table.insert(lines, "**Created:** " .. os.date("%Y-%m-%d %H:%M:%S", created / 1000))
				table.insert(lines, "**Updated:** " .. os.date("%Y-%m-%d %H:%M:%S", updated / 1000))
				table.insert(lines, "")
				table.insert(lines, "---")
				table.insert(lines, "")

				-- Add content
				if note_data.body then
					for line in note_data.body:gmatch("[^\r\n]+") do
						table.insert(lines, line)
					end
				end

				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
			else
				vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Failed to load note preview" })
			end
		end,
	})
end

-- Execute search and display results
function M.search_notes(opts)
	opts = opts or {}
	local initial_query = opts.default_text or ""

	pickers
		.new(opts, {
			prompt_title = "Search Joplin Notes",
			finder = finders.new_dynamic({
				fn = function(prompt)
					if not prompt or prompt == "" then
						return {}
					end

					-- Get folder mapping (cached)
					local folder_map = get_cached_folder_map()

					-- Create displayer (create once per search, not per entry)
					local displayer = create_note_displayer(opts)

					local success, result = client.search_notes(prompt, {
						limit = 50,
						fields = "id,title,body,parent_id,updated_time,created_time",
					})

					if not success or not result or not result.items then
						return {}
					end

					local entries = {}
					for _, note in ipairs(result.items) do
						if folder_map then
							-- Use format with path
							local formatted = format_entry_with_path(note, folder_map, displayer, opts)
							table.insert(entries, formatted)
						else
							-- Fallback to original format (if unable to get folders)
							table.insert(entries, {
								value = note,
								display = format_entry(note),
								ordinal = note.title .. " " .. (note.body or ""),
							})
						end
					end

					return entries
				end,
				entry_maker = function(entry)
					return entry
				end,
			}),
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

				-- Add Ctrl+V for vertical split open
				map("i", "<C-v>", function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						buffer_utils.open_note_split(selection.value)
					end
				end)

				return true
			end,
		})
		:find()
end

-- Execute notebook search and display results
function M.search_notebooks(opts)
	opts = opts or {}
	local initial_query = opts.default_text or ""

	pickers
		.new(opts, {
			prompt_title = "Search Joplin Notebooks",
			finder = finders.new_dynamic({
				fn = function(prompt)
					-- Always use get_folders() and filter manually, ensure result consistency
					local success, folders = client.get_folders()
					if not success then
						return {}
					end

					local filtered_entries = {}

					-- For empty query, return first 20 folders
					if not prompt or prompt == "" then
						for i = 1, math.min(20, #folders) do
							local folder = folders[i]
							table.insert(filtered_entries, {
								value = folder,
								display = format_notebook_entry(folder),
								ordinal = tostring(folder.title or "Untitled"),
							})
						end
						return filtered_entries
					end

					-- For non-empty query, perform string matching
					local search_term = tostring(prompt):lower()

					for _, folder in ipairs(folders) do
						local title = tostring(folder.title or "")
						if title:lower():find(search_term, 1, true) then -- Use plain text search
							table.insert(filtered_entries, {
								value = folder,
								display = format_notebook_entry(folder),
								ordinal = title,
							})
						end
					end

					return filtered_entries
				end,
				entry_maker = function(entry)
					-- Ensure all fields are of the correct type
					return {
						value = entry.value,
						display = tostring(entry.display),
						ordinal = tostring(entry.ordinal),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = false,
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						local joplin = require("joplin")
						joplin.expand_to_folder(selection.value.id)
					end
				end)

				return true
			end,
		})
		:find()
end

-- Check if Telescope is available
function M.is_telescope_available()
	local has_telescope, _ = pcall(require, "telescope")
	return has_telescope
end

-- Check if would create circular reference (moving folder to its own child folder)
local function would_create_circular_reference(source_folder_id, target_folder_id, all_folders)
	if source_folder_id == target_folder_id then
		return true -- Cannot move to itself
	end

	-- Build folder mapping
	local folder_map = {}
	for _, folder in ipairs(all_folders) do
		folder_map[folder.id] = folder
	end

	-- Check if target folder is a child folder of source folder
	local current_id = target_folder_id
	while current_id and current_id ~= "" do
		if current_id == source_folder_id then
			return true -- Found circular reference
		end
		local folder = folder_map[current_id]
		if not folder then
			break
		end
		current_id = folder.parent_id
	end

	return false
end

-- Execute notebook search and display results (for move operation)
function M.search_move_destination(item_type, item_id, item_title, opts)
	opts = opts or {}

	local prompt_title = string.format("Move %s '%s' to...", item_type, item_title or "Unknown")

	pickers
		.new(opts, {
			prompt_title = prompt_title,
			finder = finders.new_dynamic({
				fn = function(prompt)
					-- Always use get_folders() and filter manually to ensure result consistency
					local success, folders = client.get_folders()
					if not success then
						return {}
					end

					local filtered_entries = {}

					-- For empty query, return the first 20 folders
					if not prompt or prompt == "" then
						for i = 1, math.min(20, #folders) do
							local folder = folders[i]
							-- Exclude self and check for circular references (if moving a folder)
							if
								item_type ~= "folder"
								or (
									folder.id ~= item_id
									and not would_create_circular_reference(item_id, folder.id, folders)
								)
							then
								table.insert(filtered_entries, {
									value = folder,
									display = format_notebook_entry(folder),
									ordinal = tostring(folder.title or "Untitled"),
								})
							end
						end
						return filtered_entries
					end

					-- For non-empty query, perform string matching
					local search_term = tostring(prompt):lower()

					for _, folder in ipairs(folders) do
						local title = tostring(folder.title or "")
						-- Exclude self and check for circular references (if moving a folder)
						if
							(
								item_type ~= "folder"
								or (
									folder.id ~= item_id
									and not would_create_circular_reference(item_id, folder.id, folders)
								)
							) and title:lower():find(search_term, 1, true)
						then -- Use plain text search
							table.insert(filtered_entries, {
								value = folder,
								display = format_notebook_entry(folder),
								ordinal = title,
							})
						end
					end

					return filtered_entries
				end,
				entry_maker = function(entry)
					-- Ensure all fields are of the correct type
					return {
						value = entry.value,
						display = tostring(entry.display),
						ordinal = tostring(entry.ordinal),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = false,
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						-- Execute move operation
						local joplin = require("joplin")
						local success = false

						if item_type == "note" then
							success = joplin.move_note(item_id, selection.value.id)
						elseif item_type == "folder" then
							success = joplin.move_folder(item_id, selection.value.id)
						end

						if success then
							print("✅ " .. item_type .. " moved successfully to: " .. (selection.value.title or "Unknown"))

							-- Refresh tree view
							local tree_ui = require("joplin.ui.tree")
							local tree_winid, tree_bufnr = tree_ui.find_active_tree_window()
							if tree_winid then
								local tree_state = tree_ui.get_tree_state_for_buffer(tree_bufnr)
								if tree_state then
									joplin.refresh_tree_lightweight(tree_state)
								end
							end
						end
					end
				end)

				return true
			end,
		})
		:find()
end

-- Clear folder cache (for debugging or force refresh)
function M.clear_folder_cache()
	_folder_cache = nil
	_folder_map_cache = nil
	_cache_timestamp = 0
end

return M
