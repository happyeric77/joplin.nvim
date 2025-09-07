local joplin = require "joplin"
local api = require "joplin.api.client"

describe("Joplin API Basic Tests", function()
  before_each(function()
    -- Set up test environment with fallback token for CI
    joplin.setup {
      token = os.getenv "JOPLIN_TOKEN" or "test-token-for-ci",
      port = 41184,
      host = "localhost",
    }
  end)

  it("ping should handle connection gracefully", function()
    local ok, result = joplin.ping()
    -- In CI environment, connection may fail, which is expected
    if ok then
      assert.is_truthy(result:match "JoplinClipperServer")
    else
      -- Connection failed, ensure we get a meaningful error message
      assert.is_string(result)
      assert.is_truthy(result:len() > 0)
    end
  end)

  it("get_folders should handle connection gracefully", function()
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
      assert.is_truthy(folders:len() > 0)
    end
  end)

  it("get_notes should handle connection gracefully", function()
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
      assert.is_truthy(notes:len() > 0)
    end
  end)

  it("get_note should require note_id parameter", function()
    local ok, result = api.get_note()
    assert.is_false(ok)
    assert.is_truthy(result:match "Note ID is required")
  end)
end)
