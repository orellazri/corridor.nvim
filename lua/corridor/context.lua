local config = require("corridor.config")
local neighbors = require("corridor.neighbors")

---@class corridor.Context
---@field filepath string Relative file path from cwd
---@field filetype string Buffer filetype
---@field prefix string Text before the cursor
---@field suffix string Text after the cursor
---@field midline boolean Whether the cursor is mid-line (non-whitespace after cursor)
---@field neighbor_context string Formatted cross-file context from open buffers

local M = {}

--- Gather buffer context around the cursor for FIM completion.
---@return corridor.Context
M.gather = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local current_line = vim.api.nvim_get_current_line()
	local max_lines = config.get("max_context_lines")

	-- Relative path from cwd, falls back to "[unnamed]"
	local filepath = vim.fn.expand("%:.")
	if filepath == "" then
		filepath = "[unnamed]"
	end

	local prefix = M._build_prefix(buf, row, col, current_line, max_lines)
	local suffix = M._build_suffix(buf, row, col, current_line, max_lines)

	-- Detect mid-line editing (non-whitespace after cursor on the same line)
	local after_cursor = current_line:sub(col + 1)
	local midline = after_cursor ~= "" and after_cursor:match("%S") ~= nil

	-- Gather cross-file context from other open buffers
	local neighbor_context = neighbors.gather(buf)

	return {
		filepath = filepath,
		filetype = vim.bo.filetype,
		prefix = prefix,
		suffix = suffix,
		midline = midline,
		neighbor_context = neighbor_context,
	}
end

--- Build the prefix string (everything before the cursor within the context window).
---@param buf number Buffer handle
---@param row number 0-indexed cursor row
---@param col number 0-indexed cursor column
---@param current_line string Full text of the current line
---@param max_lines number Maximum context lines (0 = unlimited)
---@return string
M._build_prefix = function(buf, row, col, current_line, max_lines)
	local before_start
	if max_lines == 0 then
		before_start = 0
	else
		-- Asymmetric split: ~70% before, ~30% after
		local before_limit = math.floor(max_lines * 0.7)
		before_start = math.max(0, row - before_limit)
	end

	local lines = vim.api.nvim_buf_get_lines(buf, before_start, row, false)
	table.insert(lines, current_line:sub(1, col))
	return table.concat(lines, "\n")
end

--- Build the suffix string (everything after the cursor within the context window).
---@param buf number Buffer handle
---@param row number 0-indexed cursor row
---@param col number 0-indexed cursor column
---@param current_line string Full text of the current line
---@param max_lines number Maximum context lines (0 = unlimited)
---@return string
M._build_suffix = function(buf, row, col, current_line, max_lines)
	local total_lines = vim.api.nvim_buf_line_count(buf)
	local after_end
	if max_lines == 0 then
		after_end = total_lines
	else
		local after_limit = max_lines - math.floor(max_lines * 0.7)
		after_end = math.min(total_lines, row + 1 + after_limit)
	end

	local lines = vim.api.nvim_buf_get_lines(buf, row + 1, after_end, false)
	table.insert(lines, 1, current_line:sub(col + 1))
	return table.concat(lines, "\n")
end

return M
