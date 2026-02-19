local api = require("corridor.api")
local ui = require("corridor.ui")
local config = require("corridor.config")

local M = {}

local timer = nil

M.setup = function(opts)
	config.setup(opts)

	-- Clean up any existing timer from a previous setup() call
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
	end
	timer = vim.uv.new_timer()

	-- Create an Augroup to prevent duplicate listeners
	local group = vim.api.nvim_create_augroup("CorridorAutoSuggest", { clear = true })

	-- Trigger whenever text is changed in Insert Mode
	vim.api.nvim_create_autocmd({ "CursorMovedI" }, {
		group = group,
		callback = function()
			M.handle_typing()
		end,
	})

	-- Map Tab to accept in Insert Mode
	vim.keymap.set("i", config.get("accept_keymap"), function()
		if ui.current_suggestion then
			vim.schedule(function()
				M.accept_suggestion()
			end)
		else
			-- Fallback to normal key behavior if no suggestion
			local key = config.get("accept_keymap")
			local termcodes = vim.api.nvim_replace_termcodes(key, true, true, true)
			vim.api.nvim_feedkeys(termcodes, "n", false)
		end
	end, { desc = "Accept AI Suggestion" })

	-- Map Shift-Tab to dismiss in Insert Mode
	vim.keymap.set("i", config.get("dismiss_keymap"), function()
		if ui.current_suggestion then
			M.dismiss_suggestion()
		else
			-- Fallback to normal key behavior if no suggestion
			local key = config.get("dismiss_keymap")
			local termcodes = vim.api.nvim_replace_termcodes(key, true, true, true)
			vim.api.nvim_feedkeys(termcodes, "n", false)
		end
	end, { desc = "Dismiss AI Suggestion" })

	-- Auto-clear on cursor move in normal mode or before a character is inserted
	vim.api.nvim_create_autocmd({ "CursorMoved", "InsertCharPre" }, {
		group = group,
		callback = function()
			ui.clear()
		end,
	})

	-- Full cleanup when leaving insert mode
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		callback = function()
			ui.clear()
			api.cancel()
			timer:stop()
		end,
	})
end

M.handle_typing = function()
	-- Skip excluded filetypes
	local excluded = config.get("exclude_filetypes")
	if excluded[vim.bo.filetype] then
		return
	end

	ui.clear()
	api.cancel()
	timer:stop()
	timer:start(
		config.get("debounce_ms"),
		0,
		vim.schedule_wrap(function()
			local mode = vim.api.nvim_get_mode().mode
			if mode == "i" then
				M.get_ai_suggestion()
			end
		end)
	)
end

M.get_ai_suggestion = function()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]

	local filetype = vim.bo.filetype
	-- Relative path from cwd, falls back to basename, then "[unnamed]"
	local filepath = vim.fn.expand("%:.")
	if filepath == "" then
		filepath = "[unnamed]"
	end

	local max_lines = config.get("max_context_lines")

	-- Gather prefix (everything before cursor)
	local before_start
	if max_lines == 0 then
		before_start = 0
	else
		-- Asymmetric split: ~70% before, ~30% after
		local before_limit = math.floor(max_lines * 0.7)
		before_start = math.max(0, row - before_limit)
	end
	local before_lines = vim.api.nvim_buf_get_lines(buf, before_start, row, false)
	local current_line_before_cursor = vim.api.nvim_get_current_line():sub(1, col)
	table.insert(before_lines, current_line_before_cursor)

	-- Gather suffix (everything after cursor)
	local total_lines = vim.api.nvim_buf_line_count(buf)
	local after_end
	if max_lines == 0 then
		after_end = total_lines
	else
		local after_limit = max_lines - math.floor(max_lines * 0.7)
		after_end = math.min(total_lines, row + 1 + after_limit)
	end
	local after_lines = vim.api.nvim_buf_get_lines(buf, row + 1, after_end, false)
	local current_line_after_cursor = vim.api.nvim_get_current_line():sub(col + 1)
	table.insert(after_lines, 1, current_line_after_cursor)

	local prefix = table.concat(before_lines, "\n")
	local suffix = table.concat(after_lines, "\n")

	-- Track whether there's text after cursor on the same line.
	-- Used to limit completions to single-line when filling mid-line.
	local midline = current_line_after_cursor ~= ""
		and current_line_after_cursor:match("%S") ~= nil

	local context = {
		filepath = filepath,
		filetype = filetype,
		prefix = prefix,
		suffix = suffix,
		midline = midline,
	}

	api.fetch_suggestion(context, ui.show)
end

M.dismiss_suggestion = function()
	ui.clear()
	api.cancel()
	timer:stop()
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
