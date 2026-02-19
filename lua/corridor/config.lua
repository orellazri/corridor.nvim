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

	-- Normalize exclude_filetypes: accept a list {"md", "help"} or map {md = true}
	-- and always store as a map for O(1) lookup
	local raw = M.values.exclude_filetypes
	if raw then
		local normalized = {}
		for k, v in pairs(raw) do
			if type(k) == "number" then
				-- List-style: {"markdown", "help"}
				normalized[v] = true
			else
				-- Map-style: {markdown = true}
				normalized[k] = v
			end
		end
		M.values.exclude_filetypes = normalized
	end
end

M.get = function(key)
	return M.values[key]
end

return M
