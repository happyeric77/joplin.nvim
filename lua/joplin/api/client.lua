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
		table.insert(query, string.format("%s=%s", k, vim.fn.escape(tostring(v), ",")))
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
	local ok, result = pcall(function()
		return M.get(endpoints.FOLDERS)
	end)

	if not ok then
		return false, "Failed to fetch folders: " .. result
	end

	return true, result.items or result
end

-- 取得指定資料夾的筆記
function M.get_notes(folder_id, limit)
	limit = limit or 50
	local params = { limit = limit }
	if folder_id then
		params.folder_id = folder_id
	end

	local ok, result = pcall(function()
		return M.get(endpoints.NOTES, params)
	end)

	if not ok then
		return false, "Failed to fetch notes: " .. result
	end

	return true, result.items or result
end

-- 取得單一筆記內容
function M.get_note(note_id)
	if not note_id then
		return false, "Note ID is required"
	end

	local ok, result = pcall(function()
		return M.get(endpoints.NOTES .. "/" .. note_id)
	end)

	if not ok then
		return false, "Failed to fetch note: " .. result
	end

	return true, result
end

return M
