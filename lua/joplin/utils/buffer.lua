local api = require("joplin.api.client")
local M = {}

-- Store buffer to note mapping relationship
local buffer_note_map = {}
local note_buffer_map = {}

-- Get or create note buffer
function M.open_note(note_id, open_cmd)
	-- If input is table, extract id
	if type(note_id) == "table" then
		note_id = note_id.id
	end

	if not note_id then
		vim.notify("Note ID is required", vim.log.levels.ERROR)
		return
	end

	open_cmd = open_cmd or "edit"

	-- Check if buffer for this note already exists
	local existing_bufnr = note_buffer_map[note_id]
	if existing_bufnr and vim.api.nvim_buf_is_valid(existing_bufnr) then
		-- Buffer already exists, open directly
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

	-- Fetch note content from Joplin
	local success, note = api.get_note(note_id)
	if not success then
		vim.notify("Failed to fetch note: " .. note, vim.log.levels.ERROR)
		return
	end

	-- Create new buffer
	local bufnr = vim.api.nvim_create_buf(true, false) -- listed=true, scratch=false
	if not bufnr or bufnr == 0 then
		vim.notify("Failed to create buffer", vim.log.levels.ERROR)
		return
	end

	-- Set buffer content
	local lines = {}
	if note.body then
		lines = vim.split(note.body, "\n", { plain = true })
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	-- Set buffer attributes, create more standard environment for Copilot
	-- Use current working directory instead of /tmp to let Copilot recognize this as project file
	local safe_title = (note.title or "Untitled")
		:gsub("[^%w%s%-_%.%+]", "_") -- Keep more safe characters
		:gsub("%s+", "_") -- Convert spaces to underscores
		:sub(1, 50) -- Limit length to avoid overly long filenames

	-- Use hidden .joplin directory in current working directory
	local cwd = vim.fn.getcwd()
	local joplin_dir = cwd .. "/.joplin"

	-- Create directory (if doesn't exist)
	vim.fn.mkdir(joplin_dir, "p")

	-- Use simplified file path, avoid over-complexity
	local filename = string.format("%s/%s_%s.md", joplin_dir, note_id:sub(1, 8), safe_title)

	-- Immediately create real file, ensure file exists and content is correct
	vim.fn.writefile(lines, filename)

	vim.api.nvim_buf_set_name(bufnr, filename)
	vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
	vim.api.nvim_buf_set_option(bufnr, "buftype", "")
	vim.api.nvim_buf_set_option(bufnr, "modified", false) -- File already synced, no modification marker needed
	vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
	vim.api.nvim_buf_set_option(bufnr, "writebackup", false)

	-- Save mapping relationship
	buffer_note_map[bufnr] = {
		note_id = note_id,
		title = note.title,
		parent_id = note.parent_id,
		created_time = note.created_time,
		updated_time = note.updated_time,
	}
	note_buffer_map[note_id] = bufnr

	-- Setup autocmds to handle saving
	-- Use more forceful method to ensure BufWriteCmd is triggered

	vim.api.nvim_buf_set_var(bufnr, "joplin_temp_file", filename)

	-- Set buffer to require custom writing
	vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")

	-- Use BufWriteCmd to completely take over saving
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = bufnr,
		callback = function()
			print("💾 Starting Joplin note save process...")

			-- 1. Manually trigger formatting (if conform.nvim is available)
			local conform_ok, conform = pcall(require, "conform")
			if conform_ok then
				print("🎨 Formatting...")
				local format_ok, format_err = pcall(conform.format, {
					bufnr = bufnr,
					async = false, -- Synchronous formatting to ensure completion
				})
				if format_ok then
					print("✨ Formatting complete")
				else
					print("⚠️  Formatting failed: " .. tostring(format_err))
				end
			else
				print("ℹ️  conform.nvim not found, skipping formatting")
			end

			-- 2. Get (possibly already formatted) content
			local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local current_filename = vim.api.nvim_buf_get_name(bufnr)

			-- 3. Sync to Joplin
			local joplin_success = M.save_note(bufnr)

			-- 4. Update local file
			local file_success = pcall(vim.fn.writefile, current_lines, current_filename)

			-- 5. Set as unmodified (this is key for BufWriteCmd)
			vim.api.nvim_buf_set_option(bufnr, "modified", false)

			-- 6. Report result
			if joplin_success and file_success then
				print("✅ Save complete (Joplin + local file)")
			elseif file_success then
				print("⚠️  Local file saved, but Joplin sync failed")
			else
				print("❌ Save failed")
			end
		end,
	})

	-- Set multiple autocmds to ensure cleanup of mappings and temp files
	local cleanup_callback = function()
		local note_info = buffer_note_map[bufnr]
		if note_info then
			-- Clean up mapping relationship
			note_buffer_map[note_info.note_id] = nil
			buffer_note_map[bufnr] = nil

			-- Clean up temp files
			local buf_filename = filename -- Use simplified filename
			if buf_filename and buf_filename:find("/.joplin/") then
				local delete_ok = pcall(vim.fn.delete, buf_filename)
				if delete_ok then
					print("🗑️  Joplin temp file cleaned: " .. vim.fn.fnamemodify(buf_filename, ":t"))
				else
					print("⚠️  Failed to clean temp file: " .. vim.fn.fnamemodify(buf_filename, ":t"))
				end
			end
		end
	end

	-- Set multiple triggers to ensure cleanup
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		buffer = bufnr,
		callback = cleanup_callback,
	})

	vim.api.nvim_create_autocmd("BufUnload", {
		buffer = bufnr,
		callback = function()
			-- Delayed cleanup as a backup
			vim.schedule(cleanup_callback)
		end,
	})

	-- Delay trigger Copilot to recheck this buffer
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			-- Temporarily set as normal buffer to let Copilot initialize
			vim.api.nvim_buf_set_option(bufnr, "buftype", "")

			-- Trigger Copilot to recheck
			vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })
			vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })

			-- After a short delay, reset to acwrite
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
				end
			end)
		end
	end)

	-- Set auto sync command (when entering this buffer)
	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = bufnr,
		callback = function()
			-- Delay execution to avoid triggering during buffer creation
			vim.schedule(function()
				local joplin = require("joplin")
				if joplin.auto_sync_to_current_note then
					joplin.auto_sync_to_current_note()
				end
			end)
		end,
	})

	-- Open buffer according to open_cmd
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

-- Save note to Joplin
function M.save_note(bufnr)
	local note_info = buffer_note_map[bufnr]
	if not note_info then
		print("❌ Buffer is not associated with a Joplin note")
		return false
	end

	print("🔍 Start saving note ID: " .. note_info.note_id)

	-- Get buffer content
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	print("📝 Note content length: " .. #content .. " characters")

	-- Prepare update data
	local update_data = {
		body = content,
	}

	print("🚀 Sending API update request...")

	-- Call API to update note
	local success, result = api.update_note(note_info.note_id, update_data)

	if success then
		print("✅ Note saved successfully")
		return true
	else
		print("❌ Failed to save note: " .. tostring(result))
		return false
	end
end

-- Check if buffer is a Joplin note
function M.is_joplin_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	return buffer_note_map[bufnr] ~= nil
end

-- Get note info for buffer
function M.get_note_info(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	return buffer_note_map[bufnr]
end

-- Reload note content
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

	-- Update buffer content
	local lines = {}
	if note.body then
		lines = vim.split(note.body, "\n", { plain = true })
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(bufnr, "modified", false)

	-- Update note info
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

-- Convenience function: open note in split window (used from search results)
function M.open_note_split(note)
	return M.open_note(note, "vsplit")
end

-- Convenience function: directly replace current window (used from search results)
function M.open_note_current(note)
	return M.open_note(note, "edit")
end

-- Clean up all Joplin temp files
function M.cleanup_all_temp_files()
	local cwd = vim.fn.getcwd()
	local joplin_dir = cwd .. "/.joplin"

	if vim.fn.isdirectory(joplin_dir) == 1 then
		local files = vim.fn.readdir(joplin_dir)
		for _, file in ipairs(files) do
			if file:match("%.md$") then
				local filepath = joplin_dir .. "/" .. file
				pcall(vim.fn.delete, filepath)
			end
		end
		-- If directory is empty, delete the directory
		if #vim.fn.readdir(joplin_dir) == 0 then
			pcall(vim.fn.delete, joplin_dir, "d")
		end
	end
end

-- Clean up all temp files on Neovim exit
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		M.cleanup_all_temp_files()
	end,
})

return M

