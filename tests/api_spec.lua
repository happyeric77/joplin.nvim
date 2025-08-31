local joplin = require('joplin')

describe('Joplin API 基本測試', function()
  it('ping 應該回傳 JoplinClipperServer', function()
    local ok, result = joplin.ping()
    assert.is_true(ok)
    assert.is_truthy(result:match('JoplinClipperServer'))
  end)
end)
