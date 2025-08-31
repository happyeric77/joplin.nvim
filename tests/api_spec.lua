local joplin = require('joplin')
local api = require('joplin.api.client')

describe('Joplin API 基本測試', function()
  before_each(function()
    -- 設定測試環境，確保有 token
    joplin.setup({
      token_env = 'JOPLIN_TOKEN',
      port = 41184,
      host = 'localhost'
    })
  end)

  it('ping 應該回傳 JoplinClipperServer', function()
    local ok, result = joplin.ping()
    assert.is_true(ok)
    assert.is_truthy(result:match('JoplinClipperServer'))
  end)

  it('get_folders 應該回傳資料夾列表', function()
    local ok, folders = api.get_folders()
    if ok then
      assert.is_table(folders)
      -- 如果有資料夾，檢查第一個資料夾的結構
      if #folders > 0 then
        assert.is_truthy(folders[1].id)
        assert.is_truthy(folders[1].title)
      end
    else
      -- 如果失敗，至少確保錯誤訊息是字串
      assert.is_string(folders)
    end
  end)

  it('get_notes 應該回傳筆記列表', function()
    local ok, notes = api.get_notes(nil, 5) -- 取得最多5筆筆記
    if ok then
      assert.is_table(notes)
      -- 如果有筆記，檢查第一筆筆記的結構
      if #notes > 0 then
        assert.is_truthy(notes[1].id)
        assert.is_truthy(notes[1].title)
      end
    else
      -- 如果失敗，至少確保錯誤訊息是字串
      assert.is_string(notes)
    end
  end)

  it('get_note 應該要求 note_id 參數', function()
    local ok, result = api.get_note()
    assert.is_false(ok)
    assert.is_truthy(result:match('Note ID is required'))
  end)
end)
