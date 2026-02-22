local config = require("corridor.config")

local M = {}

--- Build a comment-header string for a neighbor file snippet.
--- Uses the buffer's filetype to determine the comment syntax.
---@param filepath string Relative file path
---@param filetype string Buffer filetype
---@return string Header line (e.g., "-- File: src/utils.lua" or "# File: script.py")
M._build_header = function(filepath, filetype)
	local hash_comment_types = {
		python = true,
		ruby = true,
		perl = true,
		bash = true,
		sh = true,
		zsh = true,
		yaml = true,
		toml = true,
		dockerfile = true,
		make = true,
		cmake = true,
		r = true,
		julia = true,
		elixir = true,
		nim = true,
	}

	if hash_comment_types[filetype] then
		return string.format("# File: %s", filepath)
	end

	-- Default to double-dash comment (works for Lua, Haskell, SQL, etc.)
	-- Also a reasonable fallback for languages where it may appear as a separator
	return string.format("-- File: %s", filepath)
end

--- Gather cross-file context snippets from other open buffers.
--- Returns neighbor snippets ordered by recency (most recently used first).
---@param current_buf number Handle of the current buffer to exclude
---@return string Formatted cross-file context string ready for prompt injection
M.gather = function(current_buf)
	if not config.get("cross_file_context") then
		return ""
	end

	local max_lines = config.get("max_cross_file_lines")
	local max_count = config.get("max_cross_file_count")
	local excluded = config.get("exclude_filetypes")

	local candidates = M._get_candidates(current_buf, excluded)

	-- Sort by lastused descending (most recently visited first)
	table.sort(candidates, function(a, b)
		return a.lastused > b.lastused
	end)

	-- Take top N candidates
	local selected = {}
	for i = 1, math.min(max_count, #candidates) do
		table.insert(selected, candidates[i])
	end

	return M._format_snippets(selected, max_lines)
end

--- Get candidate buffers for cross-file context.
---@param current_buf number Buffer handle to exclude
---@param excluded table<string, boolean> Excluded filetypes map
---@return table[] List of candidate buffer info tables with bufnr, filepath, filetype, lastused
M._get_candidates = function(current_buf, excluded)
	local candidates = {}
	local bufinfos = vim.fn.getbufinfo({ buflisted = 1 })

	for _, info in ipairs(bufinfos) do
		local bufnr = info.bufnr
		local name = info.name

		-- Only include file buffers that are not the current buffer
		if
			bufnr ~= current_buf
			and name
			and name ~= ""
			and vim.bo[bufnr].buftype == ""
			and not excluded[vim.bo[bufnr].filetype]
		then
			local filepath = vim.fn.fnamemodify(name, ":.")
			table.insert(candidates, {
				bufnr = bufnr,
				filepath = filepath,
				filetype = vim.bo[bufnr].filetype,
				lastused = info.lastused or 0,
			})
		end
	end

	return candidates
end

--- Format selected buffer snippets into a single context string.
---@param selected table[] List of candidate info tables
---@param max_lines number Maximum lines to include per file
---@return string Formatted context string
M._format_snippets = function(selected, max_lines)
	if #selected == 0 then
		return ""
	end

	local parts = {}

	for _, candidate in ipairs(selected) do
		local line_count = vim.api.nvim_buf_line_count(candidate.bufnr)
		local end_line = math.min(line_count, max_lines)
		local lines = vim.api.nvim_buf_get_lines(candidate.bufnr, 0, end_line, false)

		if #lines > 0 then
			local header = M._build_header(candidate.filepath, candidate.filetype)
			local content = table.concat(lines, "\n")
			table.insert(parts, header .. "\n" .. content)
		end
	end

	if #parts == 0 then
		return ""
	end

	-- Join all snippets with double newline and add trailing separator
	return table.concat(parts, "\n\n") .. "\n\n"
end

return M
