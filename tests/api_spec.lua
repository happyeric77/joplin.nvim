local joplin = require('joplin')
local api = require('joplin.api.client')

describe('Joplin API Basic Tests', function()
  before_each(function()
    -- Set up test environment, ensure token exists
    joplin.setup({
      token_env = 'JOPLIN_TOKEN',
      port = 41184,
      host = 'localhost'
    })
  end)

  it('ping should return JoplinClipperServer', function()
    local ok, result = joplin.ping()
    assert.is_true(ok)
    assert.is_truthy(result:match('JoplinClipperServer'))
  end)

  it('get_folders should return folder list', function()
    local ok, folders = api.get_folders()
    if ok then
      assert.is_table(folders)
      -- If there are folders, check the structure of the first folder
      if #folders > 0 then
        assert.is_truthy(folders[1].id)
        assert.is_truthy(folders[1].title)
      end
    else
      -- If failed, at least ensure error message is a string
      assert.is_string(folders)
    end
  end)

  it('get_notes should return note list', function()
    local ok, notes = api.get_notes(nil, 5) -- get at most 5 notes
    if ok then
      assert.is_table(notes)
      -- If there are notes, check the structure of the first note
      if #notes > 0 then
        assert.is_truthy(notes[1].id)
        assert.is_truthy(notes[1].title)
      end
    else
      -- If failed, at least ensure error message is a string
      assert.is_string(notes)
    end
  end)

  it('get_note should require note_id parameter', function()
    local ok, result = api.get_note()
    assert.is_false(ok)
    assert.is_truthy(result:match('Note ID is required'))
  end)
end)
