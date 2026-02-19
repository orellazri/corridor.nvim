local config = require("corridor.config")

local M = {}

-- Monotonically increasing ID to track the latest request.
-- Stale responses are silently discarded via request_id comparison
-- (plenary's curl doesn't support clean cancellation).
local current_request_id = 0

-- Check for plenary once at load time
local has_plenary, curl = pcall(require, "plenary.curl")
if not has_plenary then
	vim.notify("corridor.nvim requires plenary.nvim to be installed", vim.log.levels.ERROR)
end

M.cancel = function()
	current_request_id = current_request_id + 1
end

--- Build a FIM prompt string from context.
M._build_prompt = function(context)
	local fim = config.get("fim")
	return fim.prefix .. context.prefix .. fim.suffix .. context.suffix .. fim.middle
end

--- Build the request body for the completions API.
M._build_request_body = function(prompt)
	return vim.fn.json_encode({
		model = config.get("model"),
		prompt = prompt,
		temperature = config.get("temperature"),
		max_tokens = config.get("max_tokens"),
		stop = config.get("stop"),
	})
end

--- Post-process a raw completion string.
--- Strips leading newlines and truncates to single-line for mid-line completions.
--- Returns nil if the result is empty.
M._process_completion = function(text, midline)
	-- Strip leading newline (common FIM artifact)
	if text:sub(1, 1) == "\n" then
		text = text:sub(2)
	end

	-- When completing mid-line, keep only the first line
	if midline then
		text = text:match("^([^\n]*)")
	end

	if text == "" then
		return nil
	end

	return text
end

--- Extract the completion text from a decoded API response.
--- Returns nil if the response is invalid or empty.
M._extract_completion = function(decoded)
	if not decoded.choices or #decoded.choices == 0 then
		return nil
	end

	local choice = decoded.choices[1]
	if not choice or not choice.text then
		return nil
	end

	return choice.text
end

M.fetch_suggestion = function(context, callback)
	if not has_plenary then
		return
	end

	M.cancel()
	local my_request_id = current_request_id

	-- Capture state at request time for staleness detection
	local request_buf = vim.api.nvim_get_current_buf()
	local request_cursor = vim.api.nvim_win_get_cursor(0)

	local prompt = M._build_prompt(context)
	local body = M._build_request_body(prompt)

	local ok, err = pcall(function()
		curl.post(config.get("endpoint"), {
			headers = { ["Content-Type"] = "application/json" },
			body = body,
			callback = function(res)
				M._handle_response(res, my_request_id, request_buf, request_cursor, context.midline, callback)
			end,
		})
	end)

	if not ok then
		vim.notify(string.format("Corridor: Request failed: %s", err), vim.log.levels.WARN)
	end
end

--- Handle the HTTP response from the completions API.
--- Validates, extracts, post-processes, and delivers the result via callback.
M._handle_response = function(res, my_request_id, request_buf, request_cursor, midline, callback)
	if my_request_id ~= current_request_id then
		return
	end

	if not res or not res.body or res.body == "" then
		return
	end

	if res.status and res.status ~= 200 then
		vim.schedule(function()
			vim.notify(string.format("Corridor: API returned status %d", res.status), vim.log.levels.WARN)
		end)
		return
	end

	local decode_ok, decoded = pcall(vim.json.decode, res.body)
	if not decode_ok then
		vim.schedule(function()
			vim.notify("Corridor: Failed to parse API response", vim.log.levels.WARN)
		end)
		return
	end

	local raw_text = M._extract_completion(decoded)
	if not raw_text then
		return
	end

	local result = M._process_completion(raw_text, midline)
	if not result then
		return
	end

	vim.schedule(function()
		-- Final staleness checks inside the vim.schedule callback
		if my_request_id ~= current_request_id then
			return
		end

		local current_buf = vim.api.nvim_get_current_buf()
		local current_cursor = vim.api.nvim_win_get_cursor(0)
		if
			current_buf ~= request_buf
			or current_cursor[1] ~= request_cursor[1]
			or current_cursor[2] ~= request_cursor[2]
		then
			return
		end

		callback(result)
	end)
end

return M
