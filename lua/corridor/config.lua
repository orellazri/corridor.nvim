local M = {}

M.fim_presets = {
	starcoder = { prefix = "<fim_prefix>", suffix = "<fim_suffix>", middle = "<fim_middle>" },
	codellama = { prefix = "<PRE>", suffix = "<SUF>", middle = "<MID>" },
	deepseek = { prefix = "<｜fim▁begin｜>", suffix = "<｜fim▁hole｜>", middle = "<｜fim▁end｜>" },
	qwen = { prefix = "<|fim_prefix|>", suffix = "<|fim_suffix|>", middle = "<|fim_middle|>" },
}

local defaults = {
	endpoint = "http://localhost:1234/v1/completions",
	model = "qwen/qwen3-coder-30b",
	debounce_ms = 250,
	max_tokens = 128,
	temperature = 0.2,
	accept_keymap = "<Tab>",
	dismiss_keymap = "<S-Tab>",
	exclude_filetypes = {},

	-- Context: 0 = full buffer, positive number = max lines
	max_context_lines = 0,

	-- FIM tokens (default: Qwen family)
	fim = {
		prefix = "<|fim_prefix|>",
		suffix = "<|fim_suffix|>",
		middle = "<|fim_middle|>",
	},

	-- Stop sequences: nil = auto (uses fim.prefix as stop + <|endoftext|>)
	stop = nil,
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
