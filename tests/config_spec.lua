local config = require "joplin.config"

describe("Joplin Config Tests", function()
  it("should have default options", function()
    local defaults = config.options

    assert.is_table(defaults)
    assert.are.equal(defaults.port, 41184)
    assert.are.equal(defaults.host, "localhost")
    assert.are.equal(defaults.token_env, "JOPLIN_TOKEN")
    assert.is_table(defaults.tree)
    assert.is_table(defaults.keymaps)
    assert.is_table(defaults.startup)
  end)

  it("should setup configuration with custom values", function()
    local original_port = config.options.port

    config.setup {
      port = 8080,
      host = "example.com",
      token = "custom-token",
    }

    assert.are.equal(config.options.port, 8080)
    assert.are.equal(config.options.host, "example.com")
    assert.are.equal(config.options.token, "custom-token")

    -- Reset for other tests
    config.options.port = original_port
    config.options.host = "localhost"
    config.options.token = nil
  end)

  it("should handle nested config correctly", function()
    local original_height = config.options.tree.height
    local original_enter = config.options.keymaps.enter

    config.setup {
      tree = {
        height = 20,
      },
      keymaps = {
        enter = "vsplit",
      },
    }

    assert.are.equal(config.options.tree.height, 20)
    assert.are.equal(config.options.keymaps.enter, "vsplit")
    -- Other defaults should remain
    assert.is_truthy(config.options.tree.position)
    assert.is_truthy(config.options.keymaps.search)

    -- Reset for other tests
    config.options.tree.height = original_height
    config.options.keymaps.enter = original_enter
  end)

  it("should provide base URL", function()
    config.setup {
      host = "localhost",
      port = 41184,
    }

    local base_url = config.get_base_url()
    assert.are.equal(base_url, "http://localhost:41184")
  end)

  it("should handle token from environment", function()
    -- Test token getter
    config.setup { token = nil, token_env = "JOPLIN_TOKEN" }
    local token = config.get_token()

    -- Should either be nil or the actual env var value
    if token then
      assert.is_string(token)
    else
      assert.is_nil(token)
    end
  end)
end)

