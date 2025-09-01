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
		-- 對參數值進行 URL encoding，但不要轉義逗號（fields 參數需要逗號）
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

-- 執行刪除請求（DELETE 請求成功時可能返回空響應）
local function execute_delete_request(cmd, retry_count)
	retry_count = retry_count or DEFAULT_RETRY_COUNT
	local last_error = nil

	for attempt = 1, retry_count do
		local result = vim.fn.system(cmd)

		if vim.v.shell_error == 0 then
			-- DELETE 請求成功，即使回應為空也視為成功
			return true, result or ""
		else
			last_error = string.format(
				"HTTP DELETE request failed (attempt %d/%d): %s",
				attempt,
				retry_count,
				result or "Unknown error"
			)

			-- 如果不是最後一次嘗試，等待後重試
			if attempt < retry_count then
				sleep(DEFAULT_RETRY_DELAY * attempt) -- 指數退避
			end
		end
	end

	return false, last_error
end

-- 執行 HTTP 請求與重試邏輯
local function execute_request(cmd, retry_count)
	retry_count = retry_count or DEFAULT_RETRY_COUNT
	local last_error = nil

	for attempt = 1, retry_count do
		local result = vim.fn.system(cmd)

		if vim.v.shell_error == 0 then
			-- 成功執行，檢查回應格式
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

			-- 如果不是最後一次嘗試，等待後重試
			if attempt < retry_count then
				sleep(DEFAULT_RETRY_DELAY * attempt) -- 指數退避
			end
		end
	end

	return false, last_error
end

-- 基本 GET 請求
function M.get(path, params)
	local url = build_url(path, params)
	local cmd = string.format('curl -s -m 10 "%s"', url) -- 10秒超時

	local success, result = execute_request(cmd)
	if not success then
		error("Joplin API GET failed: " .. result)
	end

	-- 嘗試解析 JSON
	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok then
		error("Invalid JSON response: " .. result)
	end

	return decoded
end

-- 基本 POST 請求
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
		error("Joplin API POST failed: " .. result)
	end

	-- 嘗試解析 JSON
	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok then
		error("Invalid JSON response: " .. result)
	end

	return decoded
end

-- 基本 PUT 請求
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

	-- 嘗試解析 JSON
	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok then
		error("Invalid JSON response: " .. result)
	end

	return decoded
end

-- 測試 /ping
function M.ping()
	local url = build_url(endpoints.PING)
	local cmd = string.format('curl -s -m 5 "%s"', url) -- 5秒超時

	local success, result = execute_request(cmd, 1) -- ping 只試一次
	if not success then
		return false, result
	end

	return result:match("JoplinClipperServer") ~= nil, result
end

-- 取得所有資料夾 (notebooks)
function M.get_folders()
	local limit = 100  -- 單次查詢限制
	local all_folders = {}
	local page = 1
	local has_more = true

	-- 分頁獲取所有資料夾
	while has_more do
		local params = { 
			limit = limit,
			page = page
		}

		local ok, result = pcall(function()
			return M.get(endpoints.FOLDERS, params)
		end)

		if not ok then
			return false, "Failed to fetch folders: " .. result
		end

		if result and result.items then
			for _, folder in ipairs(result.items) do
				table.insert(all_folders, folder)
			end
			has_more = result.has_more or false
			page = page + 1
			
			-- 防止無限循環
			if page > 50 then  -- 最多查詢 50 頁
				break
			end
		else
			has_more = false
		end
	end

	return true, all_folders
end

-- 取得指定資料夾的筆記
function M.get_notes(folder_id, limit)
	limit = limit or 100  -- 單次查詢限制
	local all_notes = {}
	local page = 1
	local has_more = true

	-- 分頁獲取所有筆記
	while has_more do
		local params = { 
			limit = limit,
			page = page,
			fields = 'id,title,updated_time,created_time,parent_id'
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
			
			-- 防止無限循環
			if page > 50 then  -- 最多查詢 50 頁
				break
			end
		else
			has_more = false
		end
	end
	
	-- 如果有指定 folder_id，過濾出屬於該資料夾的筆記
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

-- 取得單一筆記內容
function M.get_note(note_id)
	if not note_id then
		return false, "Note ID is required"
	end

	local ok, result = pcall(function()
		return M.get(endpoints.NOTES .. "/" .. note_id, {
			fields = 'id,title,body,parent_id,created_time,updated_time'
		})
	end)

	if not ok then
		return false, "Failed to fetch note: " .. result
	end

	return true, result
end

-- 創建新資料夾 (notebook)
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

-- 創建新筆記
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

-- 更新筆記內容
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

-- 更新資料夾
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

-- 刪除資料夾
function M.delete_folder(folder_id)
	if not folder_id then
		return false, "Folder ID is required"
	end

	local cmd = string.format('curl -s -m 10 -X DELETE "%s"', 
		build_url(endpoints.FOLDERS .. "/" .. folder_id))

	local success, result = execute_delete_request(cmd)
	if not success then
		return false, "Failed to delete folder: " .. result
	end

	return true, result
end

-- 刪除筆記
function M.delete_note(note_id)
	if not note_id then
		return false, "Note ID is required"
	end

	local cmd = string.format('curl -s -m 10 -X DELETE "%s"', 
		build_url(endpoints.NOTES .. "/" .. note_id))

	local success, result = execute_delete_request(cmd)
	if not success then
		return false, "Failed to delete note: " .. result
	end

	return true, result
end

-- 搜尋筆記
function M.search_notes(query, options)
	if not query or query == "" then
		return false, "Search query is required"
	end

	options = options or {}
	local limit = options.limit or 50
	local page = options.page or 1
	local fields = options.fields or 'id,title,body,parent_id,updated_time'
	local order_by = options.order_by or 'updated_time'
	local order_dir = options.order_dir or 'desc'
	local type = options.type or 'note'

	local params = {
		query = query,
		type = type,
		fields = fields,
		limit = limit,
		page = page,
		order_by = order_by,
		order_dir = order_dir
	}

	local ok, result = pcall(function()
		return M.get(endpoints.SEARCH, params)
	end)

	if not ok then
		return false, "Failed to search notes: " .. result
	end

	return true, result
end

-- 搜尋 notebook（資料夾）
function M.search_notebooks(query, options)
	if not query or query == "" then
		return false, "Search query is required"
	end

	options = options or {}
	options.type = 'folder'
	options.fields = options.fields or 'id,title,parent_id,created_time,updated_time'
	options.order_by = options.order_by or 'updated_time'
	
	return M.search_notes(query, options)
end

return M
