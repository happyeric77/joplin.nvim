local config = require("joplin.config")
local endpoints = require("joplin.api.endpoints")
local M = {}

local DEFAULT_RETRY_COUNT = 3
local DEFAULT_RETRY_DELAY = 1000 -- ms

local function build_url(path, params)
	local base = config.get_base_url() .. path
	params = params or {}
	params.token = config.get_token()
	local query = {}
	for k, v in pairs(params) do
		-- URL encode parameter values, but don't escape commas (fields parameter needs commas)
		local encoded_value = tostring(v):gsub("([^%w%-%.%_%~])", function(c)
			return string.format("%%%02X", string.byte(c))
		end)
		table.insert(query, string.format("%s=%s", k, encoded_value))
	end
	if #query > 0 then
		return base .. "?" .. table.concat(query, "&")
	else
		return base
	end
end

local function sleep(ms)
	vim.fn.system(string.format("sleep %f", ms / 1000))
end

-- Execute DELETE requests (DELETE requests may return empty response when successful)
local function execute_delete_request(cmd, retry_count)
	retry_count = retry_count or DEFAULT_RETRY_COUNT
	local last_error = nil

	for attempt = 1, retry_count do
		local result = vim.fn.system(cmd)

		if vim.v.shell_error == 0 then
			-- DELETE request successful, treat as success even if response is empty
			return true, result or ""
		else
			last_error = string.format(
				"HTTP DELETE request failed (attempt %d/%d): %s",
				attempt,
				retry_count,
				result or "Unknown error"
			)

			-- If not the last attempt, wait and retry
			if attempt < retry_count then
				sleep(DEFAULT_RETRY_DELAY * attempt) -- exponential backoff
			end
		end
	end

	return false, last_error
end

-- Execute HTTP requests with retry logic
local function execute_request(cmd, retry_count)
	retry_count = retry_count or DEFAULT_RETRY_COUNT
	local last_error = nil

	for attempt = 1, retry_count do
		local result = vim.fn.system(cmd)

		if vim.v.shell_error == 0 then
			-- Successful execution, check response format
			if result and result ~= "" then
				return true, result
			else
				last_error = "Empty response from server"
			end
		else
			last_error = string.format(
				"HTTP request failed (attempt %d/%d): %s",
				attempt,
				retry_count,
				result or "Unknown error"
			)

			-- If not the last attempt, wait and retry
			if attempt < retry_count then
				sleep(DEFAULT_RETRY_DELAY * attempt) -- exponential backoff
			end
		end
	end

	return false, last_error
end

-- Helper function to create user-friendly error messages
local function create_friendly_error(raw_error, context)
	local config = require("joplin.config")

	-- Check for common connection issues
	if raw_error:match("Connection refused") or raw_error:match("Failed to connect") then
		return string.format(
			"Cannot connect to Joplin Web Clipper at %s. Please ensure Joplin is running with Web Clipper enabled.",
			config.get_base_url()
		)
	end

	-- Check for token issues
	if raw_error:match("Invalid.*token") then
		return "Invalid Joplin token. Please check your JOPLIN_TOKEN environment variable or configuration."
	end

	-- Check for timeout issues
	if raw_error:match("timeout") or raw_error:match("Operation timed out") then
		return "Connection timeout. Joplin Web Clipper may be slow to respond."
	end

	-- Default to more descriptive error
	return string.format("%s failed: %s", context or "Joplin API request", raw_error)
end

-- Basic GET request
function M.get(path, params)
	local url = build_url(path, params)
	local cmd = string.format('curl -s -m 10 "%s"', url) -- 10 second timeout

	local success, result = execute_request(cmd)
	if not success then
		local friendly_error = create_friendly_error(result, "GET request")
		error(friendly_error)
	end

	-- Try to parse JSON
	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok then
		-- Check if it's a Joplin error response
		if result:match('"error"') then
			local friendly_error = create_friendly_error(result, "API call")
			error(friendly_error)
		else
			error("Invalid JSON response from Joplin API: " .. (result or "empty"))
		end
	end

	return decoded
end

-- Basic POST request
function M.post(path, data, params)
	local url = build_url(path, params)
	local json_data = vim.fn.json_encode(data or {})
	local cmd = string.format(
		'curl -s -m 10 -X POST -H "Content-Type: application/json" -d %s "%s"',
		vim.fn.shellescape(json_data),
		url
	)

	local success, result = execute_request(cmd)
	if not success then
		local friendly_error = create_friendly_error(result, "POST request")
		error(friendly_error)
	end

	-- Try to parse JSON response
	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok then
		-- Check if it's a Joplin error response
		if result:match('"error"') then
			local friendly_error = create_friendly_error(result, "API call")
			error(friendly_error)
		else
			error("Invalid JSON response from Joplin API: " .. (result or "empty"))
		end
	end

	return decoded
end

-- Basic PUT request
function M.put(path, data, params)
	local url = build_url(path, params)
	local json_data = vim.fn.json_encode(data or {})
	local cmd = string.format(
		'curl -s -m 10 -X PUT -H "Content-Type: application/json" -d %s "%s"',
		vim.fn.shellescape(json_data),
		url
	)

	local success, result = execute_request(cmd)
	if not success then
		error("Joplin API PUT failed: " .. result)
	end

	-- Try to parse JSON
	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok then
		error("Invalid JSON response: " .. result)
	end

	return decoded
end

-- Test /ping
function M.ping()
	local url = build_url(endpoints.PING)
	local cmd = string.format('curl -s -m 5 "%s"', url) -- 5 second timeout

	local success, result = execute_request(cmd, 1) -- ping only tries once
	if not success then
		return false, result
	end

	return result:match("JoplinClipperServer") ~= nil, result
end

-- Get all folders (notebooks)
function M.get_folders()
	local limit = 100 -- single query limit
	local all_folders = {}
	local page = 1
	local has_more = true

	-- Paginate to get all folders
	while has_more do
		local params = {
			limit = limit,
			page = page,
		}

		local ok, result = pcall(function()
			return M.get(endpoints.FOLDERS, params)
		end)

		if not ok then
			-- Return user-friendly error message
			local error_msg = result or "Unknown error"
			if error_msg:match("Cannot connect to Joplin") then
				return false, error_msg
			elseif error_msg:match("Invalid.*token") then
				return false, "Invalid Joplin token. Please check your JOPLIN_TOKEN environment variable."
			else
				return false, "Failed to fetch notebooks: " .. error_msg
			end
		end

		if result and result.items then
			for _, folder in ipairs(result.items) do
				table.insert(all_folders, folder)
			end
			has_more = result.has_more or false
			page = page + 1

			-- Prevent infinite loop
			if page > 50 then -- maximum 50 pages
				break
			end
		else
			has_more = false
		end
	end

	return true, all_folders
end

-- Get notes from specified folder
function M.get_notes(folder_id, limit)
	limit = limit or 100 -- single query limit
	local all_notes = {}
	local page = 1
	local has_more = true

	-- Paginate to get all notes
	while has_more do
		local params = {
			limit = limit,
			page = page,
			fields = "id,title,updated_time,created_time,parent_id",
		}

		local ok, result = pcall(function()
			return M.get(endpoints.NOTES, params)
		end)

		if not ok then
			return false, "Failed to fetch notes: " .. result
		end

		if result and result.items then
			for _, note in ipairs(result.items) do
				table.insert(all_notes, note)
			end
			has_more = result.has_more or false
			page = page + 1

			-- Prevent infinite loop
			if page > 50 then -- maximum 50 pages
				break
			end
		else
			has_more = false
		end
	end

	-- If folder_id is specified, filter notes belonging to that folder
	if folder_id then
		local filtered_notes = {}

		for _, note in ipairs(all_notes) do
			if note.parent_id == folder_id then
				table.insert(filtered_notes, note)
			end
		end

		return true, filtered_notes
	end

	return true, all_notes
end

-- Get single note content
function M.get_note(note_id)
	if not note_id then
		return false, "Note ID is required"
	end

	local ok, result = pcall(function()
		return M.get(endpoints.NOTES .. "/" .. note_id, {
			fields = "id,title,body,parent_id,created_time,updated_time",
		})
	end)

	if not ok then
		return false, "Failed to fetch note: " .. result
	end

	return true, result
end

-- Create new folder (notebook)
function M.create_folder(title, parent_id)
	if not title or title == "" then
		return false, "Folder title is required"
	end

	local data = {
		title = title,
	}
	if parent_id then
		data.parent_id = parent_id
	end

	local ok, result = pcall(function()
		return M.post(endpoints.FOLDERS, data)
	end)

	if not ok then
		return false, "Failed to create folder: " .. result
	end

	return true, result
end

-- Create new note
function M.create_note(title, body, parent_id)
	if not title or title == "" then
		return false, "Note title is required"
	end

	local data = {
		title = title,
		body = body or "",
	}
	if parent_id then
		data.parent_id = parent_id
	end

	local ok, result = pcall(function()
		return M.post(endpoints.NOTES, data)
	end)

	if not ok then
		return false, "Failed to create note: " .. result
	end

	return true, result
end

-- Update note content
function M.update_note(note_id, data)
	if not note_id then
		return false, "Note ID is required"
	end

	local ok, result = pcall(function()
		return M.put(endpoints.NOTES .. "/" .. note_id, data)
	end)

	if not ok then
		return false, "Failed to update note: " .. result
	end

	return true, result
end

-- Update folder
function M.update_folder(folder_id, data)
	if not folder_id then
		return false, "Folder ID is required"
	end

	local ok, result = pcall(function()
		return M.put(endpoints.FOLDERS .. "/" .. folder_id, data)
	end)

	if not ok then
		return false, "Failed to update folder: " .. result
	end

	return true, result
end

-- Delete folder
function M.delete_folder(folder_id)
	if not folder_id then
		return false, "Folder ID is required"
	end

	local cmd = string.format('curl -s -m 10 -X DELETE "%s"', build_url(endpoints.FOLDERS .. "/" .. folder_id))

	local success, result = execute_delete_request(cmd)
	if not success then
		return false, "Failed to delete folder: " .. result
	end

	return true, result
end

-- Delete note
function M.delete_note(note_id)
	if not note_id then
		return false, "Note ID is required"
	end

	local cmd = string.format('curl -s -m 10 -X DELETE "%s"', build_url(endpoints.NOTES .. "/" .. note_id))

	local success, result = execute_delete_request(cmd)
	if not success then
		return false, "Failed to delete note: " .. result
	end

	return true, result
end

-- Search notes
function M.search_notes(query, options)
	if not query or query == "" then
		return false, "Search query is required"
	end

	options = options or {}
	local limit = options.limit or 50
	local page = options.page or 1
	local fields = options.fields or "id,title,body,parent_id,updated_time"
	local order_by = options.order_by or "updated_time"
	local order_dir = options.order_dir or "desc"
	local type = options.type or "note"

	local params = {
		query = query,
		type = type,
		fields = fields,
		limit = limit,
		page = page,
		order_by = order_by,
		order_dir = order_dir,
	}

	local ok, result = pcall(function()
		return M.get(endpoints.SEARCH, params)
	end)

	if not ok then
		return false, "Failed to search notes: " .. result
	end

	return true, result
end

-- Search notebooks (folders)
function M.search_notebooks(query, options)
	if not query or query == "" then
		return false, "Search query is required"
	end

	options = options or {}
	options.type = "folder"
	options.fields = options.fields or "id,title,parent_id,created_time,updated_time"
	options.order_by = options.order_by or "updated_time"

	return M.search_notes(query, options)
end

-- Move note to specified folder
function M.move_note(note_id, new_parent_id)
	if not note_id then
		return false, "Note ID is required"
	end

	if not new_parent_id then
		return false, "New parent folder ID is required"
	end

	local data = {
		parent_id = new_parent_id,
	}

	local ok, result = pcall(function()
		return M.put(endpoints.NOTES .. "/" .. note_id, data)
	end)

	if not ok then
		return false, "Failed to move note: " .. result
	end

	return true, result
end

-- Move folder to specified parent folder
function M.move_folder(folder_id, new_parent_id)
	if not folder_id then
		return false, "Folder ID is required"
	end

	if not new_parent_id then
		return false, "New parent folder ID is required"
	end

	local data = {
		parent_id = new_parent_id,
	}

	local ok, result = pcall(function()
		return M.put(endpoints.FOLDERS .. "/" .. folder_id, data)
	end)

	if not ok then
		return false, "Failed to move folder: " .. result
	end

	return true, result
end

return M
