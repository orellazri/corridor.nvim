local M = {}

local defaults = {
	endpoint = "http://localhost:1234/v1/chat/completions",
	model = "zai-org/glm-4.7-flash",
	debounce_ms = 250,
	max_context_before = 50,
	max_context_after = 30,
	max_tokens = 128,
	temperature = 0.2,
	accept_keymap = "<Tab>",
	dismiss_keymap = "<S-Tab>",
	exclude_filetypes = {},
}

M.values = vim.deepcopy(defaults)

M.setup = function(opts)
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

M.get = function(key)
	return M.values[key]
end

return M
