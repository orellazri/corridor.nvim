local api = require("corridor.api")
local ui = require("corridor.ui")

local M = {}

M.setup = function()
	-- Keymap to trigger AI
	vim.keymap.set("n", "<leader>a", function()
		M.get_ai_suggestion()
	end, { desc = "Get AI Suggestion" })

	-- Keymap to accept the suggestion
	vim.keymap.set("n", "<Tab>", M.accept_suggestion, { desc = "Accept AI Suggestion" })

	-- Auto-clear logic
	vim.api.nvim_create_autocmd({ "CursorMoved", "InsertCharPre" }, {
		callback = function()
			ui.clear()
		end,
	})
end

M.get_ai_suggestion = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]

	local filetype = vim.bo.filetype
	local filename = vim.fn.expand("%:t")
	local before_lines = vim.api.nvim_buf_get_lines(buf, math.max(0, row - 20), row, false)
	local current_line_before_cursor = vim.api.nvim_get_current_line():sub(1, col)
	table.insert(before_lines, current_line_before_cursor)

	local after_lines = vim.api.nvim_buf_get_lines(buf, row + 1, row + 11, false)
	local current_line_after_cursor = vim.api.nvim_get_current_line():sub(col + 1)
	table.insert(after_lines, 1, current_line_after_cursor)

	local prefix = table.concat(before_lines, "\n")
	local suffix = table.concat(after_lines, "\n")

	local context = {
		filename = filename,
		filetype = filetype,
		prefix = prefix,
		suffix = suffix,
	}

	ui.show("Thinking...")
	api.fetch_suggestion(context, ui.show)
end

M.accept_suggestion = function()
	if ui.current_suggestion then
		local buf = vim.api.nvim_get_current_buf()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local row, col = cursor[1] - 1, cursor[2]

		-- 1. Split the suggestion by newlines into a table
		local lines = {}
		for line in ui.current_suggestion:gmatch("([^\n]*)\n?") do
			table.insert(lines, line)
		end

		-- Remove the last empty element gmatch might create
		if lines[#lines] == "" then
			table.remove(lines)
		end

		-- 2. Insert the table of lines
		-- Using row, col for both start and end creates an "insertion"
		vim.api.nvim_buf_set_text(buf, row, col, row, col, lines)

		-- 3. Move cursor to the end of the insertion
		local last_line_len = #lines[#lines]
		local new_row = row + #lines
		local new_col = (#lines > 1) and last_line_len or (col + last_line_len)

		vim.api.nvim_win_set_cursor(0, { new_row, new_col })

		ui.clear()
	end
end

return M
