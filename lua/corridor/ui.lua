local M = {}
local ns_id = vim.api.nvim_create_namespace("corridor_suggestions")

M.current_suggestion = nil

M.show = function(text)
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line, col = cursor[1] - 1, cursor[2]

	M.clear()
	M.current_suggestion = text

	vim.api.nvim_buf_set_extmark(buf, ns_id, line, col, {
		virt_text = { { text, "Comment" } },
		virt_text_pos = "overlay",
	})
end

M.clear = function()
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	M.current_suggestion = nil
end

return M
