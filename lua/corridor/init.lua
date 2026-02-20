local api = require("corridor.api")
local ui = require("corridor.ui")
local config = require("corridor.config")
local context = require("corridor.context")

local M = {}

---@type uv_timer_t|nil
local timer = nil

---@type boolean
local enabled = true

--- Set up corridor with the given options.
---@param opts corridor.Config|nil User-provided configuration options
M.setup = function(opts)
	config.setup(opts)
	enabled = config.get("enabled")

	M._init_timer()
	M._register_autocmds()
	M._register_keymaps()
	M._register_commands()
end

--- Initialize (or reinitialize) the debounce timer.
M._init_timer = function()
	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
	end
	timer = vim.uv.new_timer()
end

--- Register all autocmds for suggestion triggering and cleanup.
M._register_autocmds = function()
	local group = vim.api.nvim_create_augroup("CorridorAutoSuggest", { clear = true })

	-- Trigger suggestion on typing in insert mode
	vim.api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = M.handle_typing,
	})

	-- Clear ghost text on cursor move or before inserting a character
	vim.api.nvim_create_autocmd({ "CursorMoved", "InsertCharPre" }, {
		group = group,
		callback = ui.clear,
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

--- Register accept/dismiss keymaps with fallback behavior.
M._register_keymaps = function()
	--- Create a callback that runs action if a suggestion is active,
	--- otherwise falls through to the default key behavior.
	---@param key string The keymap string
	---@param action fun() Action to run when suggestion is active
	---@return fun()
	local function with_suggestion_or_fallback(key, action)
		return function()
			if ui.current_suggestion then
				action()
			else
				local termcodes = vim.api.nvim_replace_termcodes(key, true, true, true)
				vim.api.nvim_feedkeys(termcodes, "n", false)
			end
		end
	end

	vim.keymap.set(
		"i",
		config.get("accept_keymap"),
		with_suggestion_or_fallback(config.get("accept_keymap"), function()
			vim.schedule(M.accept_suggestion)
		end),
		{ desc = "Accept AI Suggestion" }
	)

	vim.keymap.set(
		"i",
		config.get("dismiss_keymap"),
		with_suggestion_or_fallback(config.get("dismiss_keymap"), M.dismiss_suggestion),
		{ desc = "Dismiss AI Suggestion" }
	)
end

--- Handle typing events in insert mode: debounce and trigger suggestions.
M.handle_typing = function()
	if not enabled then
		return
	end

	-- Skip non-normal buffers (prompt, nofile, terminal, quickfix, help, etc.)
	if vim.bo.buftype ~= "" then
		return
	end

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
			if vim.api.nvim_get_mode().mode == "i" then
				M._request_suggestion()
			end
		end)
	)
end

--- Register user commands for enabling/disabling completions.
M._register_commands = function()
	vim.api.nvim_create_user_command("CorridorEnable", function()
		M.enable()
	end, { desc = "Enable Corridor completions" })

	vim.api.nvim_create_user_command("CorridorDisable", function()
		M.disable()
	end, { desc = "Disable Corridor completions" })
end

--- Enable completions globally.
M.enable = function()
	enabled = true
	vim.notify("Corridor: enabled", vim.log.levels.INFO)
end

--- Disable completions globally and clear any active suggestion.
M.disable = function()
	enabled = false
	ui.clear()
	api.cancel()
	timer:stop()
	vim.notify("Corridor: disabled", vim.log.levels.INFO)
end

--- Gather context and fetch a suggestion from the API.
M._request_suggestion = function()
	local ctx = context.gather()
	api.fetch_suggestion(ctx, ui.show)
end

--- Dismiss the current suggestion, cancel pending requests, and stop the timer.
M.dismiss_suggestion = function()
	ui.clear()
	api.cancel()
	timer:stop()
end

--- Accept the current suggestion by inserting its text at the cursor.
M.accept_suggestion = function()
	local text = ui.current_suggestion
	if not text then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]

	local lines = M._split_suggestion(text)
	vim.api.nvim_buf_set_text(0, row, col, row, col, lines)

	-- Move cursor to the end of the insertion
	local last_line_len = #lines[#lines]
	local new_row = row + #lines
	local new_col = (#lines > 1) and last_line_len or (col + last_line_len)
	vim.api.nvim_win_set_cursor(0, { new_row, new_col })

	ui.clear()
end

--- Split a suggestion string into a list of lines suitable for buf_set_text.
---@param text string The suggestion text
---@return string[] Lines of the suggestion
M._split_suggestion = function(text)
	local lines = {}
	for line in text:gmatch("([^\n]*)\n?") do
		table.insert(lines, line)
	end
	-- Remove trailing empty element from gmatch
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

return M
