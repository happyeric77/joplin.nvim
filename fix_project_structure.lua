-- 修復 Project 資料夾結構的工具
local api = require("joplin.api.client")

local function fix_project_structure()
    print("🔧 開始修復 Project 資料夾結構...")
    
    -- Project 資料夾 ID
    local project_id = "c8114a3424af4b8590663f517e017cc2"
    
    -- 需要移到 Project 下的資料夾
    local folders_to_move = {
        "98a1b74d186e4e06918221dc5ec0d1c6", -- 💼 notifi-feat-sdk4-target-flow
        "2ba8f043a4424c1ba27c79b197c24a64", -- 💼 Notifi
        "0a5231acaf2e458f9475cc4d4545a68e", -- 💼notifi-sdk4-m2-tg-target-renew
        "b19cc79d6ed24023ac8ee43430388efb", -- 💼notifi-alterTarget
        "63ab691af67949cd9fe676032b8f1b4a", -- 💼🇺🇸notifi-hacker-house-2503
        "894a28e372054e30b7bdbdd7ca585107", -- 💼notifi-xmtp-isolation & 💼notifi-popup-blocked
        "ce0b6c1a49c34f1fb5558c5254ffa0b8", -- 💳paypay-card-前倒し支払い & 🧑🏻‍💻sideproject-event-reminder
    }
    
    print("⚠️  警告：這將修改你的 Joplin 資料夾結構！")
    print("建議先備份你的 Joplin 資料")
    print("按 Ctrl+C 取消，或按 Enter 繼續...")
    io.read()
    
    for _, folder_id in ipairs(folders_to_move) do
        print("移動資料夾 ID:", folder_id, "到 Project 下...")
        local success, result = api.update_folder(folder_id, {parent_id = project_id})
        if success then
            print("✅ 成功")
        else
            print("❌ 失敗:", result)
        end
    end
    
    print("🎉 修復完成！請重新載入 JoplinTree 查看結果")
end

return {
    fix_project_structure = fix_project_structure
}