local config = require("joplin.config")
local api = require("joplin.api.client")

local M = {}

function M.setup(opts)
	config.setup(opts)
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

return M
