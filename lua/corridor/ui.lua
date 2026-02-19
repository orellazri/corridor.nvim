local M = {}
local ns_id = vim.api.nvim_create_namespace("corridor_suggestions")

M.current_suggestion = nil

M.show = function(text)
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line, col = cursor[1] - 1, cursor[2]

	M.clear()
	M.current_suggestion = text

	-- Split suggestion into lines
	local lines = vim.split(text, "\n", { plain = true })

	-- Build the extmark options
	local extmark_opts = {
		virt_text = { { lines[1], "Comment" } },
		virt_text_pos = "overlay",
	}

	-- If multi-line, add remaining lines as virt_lines below the current line
	if #lines > 1 then
		local virt_lines = {}
		for i = 2, #lines do
			table.insert(virt_lines, { { lines[i], "Comment" } })
		end
		extmark_opts.virt_lines = virt_lines
	end

	vim.api.nvim_buf_set_extmark(buf, ns_id, line, col, extmark_opts)
end

M.clear = function()
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	M.current_suggestion = nil
end

return M
