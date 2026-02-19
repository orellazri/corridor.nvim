local config = require("corridor.config")

local M = {}

-- Monotonically increasing ID to track the latest request.
-- We don't kill in-flight jobs because plenary's curl doesn't support clean
-- cancellation (shutdown() causes "cannot resume dead coroutine" errors).
-- Instead, stale responses are silently discarded via request_id comparison.
local current_request_id = 0

-- Check for plenary once at load time
local has_plenary, curl = pcall(require, "plenary.curl")
if not has_plenary then
	vim.notify("corridor.nvim requires plenary.nvim to be installed", vim.log.levels.ERROR)
end

M.cancel = function()
	current_request_id = current_request_id + 1
end

M.fetch_suggestion = function(context, callback)
	if not has_plenary then
		return
	end

	-- Cancel any previous in-flight request
	M.cancel()

	-- Capture this request's ID so the callback can check for staleness
	local my_request_id = current_request_id

	-- Capture cursor position at request time for stale response detection
	local request_buf = vim.api.nvim_get_current_buf()
	local request_cursor = vim.api.nvim_win_get_cursor(0)

	-- Build FIM prompt
	local fim = config.get("fim")
	local prompt = string.format(
		"%s%s%s%s%s",
		fim.prefix,
		context.prefix,
		fim.suffix,
		context.suffix,
		fim.middle
	)

	-- Build stop sequences
	local stop = config.get("stop")
	if not stop then
		stop = { fim.prefix, fim.suffix, fim.middle, "<|endoftext|>", "\n\n" }
	end

	local ok, err = pcall(function()
		curl.post(config.get("endpoint"), {
			headers = { ["Content-Type"] = "application/json" },
			body = vim.fn.json_encode({
				model = config.get("model"),
				prompt = prompt,
				temperature = config.get("temperature"),
				max_tokens = config.get("max_tokens"),
				stop = stop,
			}),
			callback = function(res)
				-- Discard if a newer request has been made since this one fired
				if my_request_id ~= current_request_id then
					return
				end

				-- Guard against nil/missing response body
				if not res or not res.body or res.body == "" then
					return
				end

				-- Guard against non-200 HTTP status
				if res.status and res.status ~= 200 then
					vim.schedule(function()
						vim.notify(
							string.format("Corridor: API returned status %d", res.status),
							vim.log.levels.WARN
						)
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

				-- Guard against missing/empty choices
				if not decoded.choices or #decoded.choices == 0 then
					return
				end

				local choice = decoded.choices[1]
				if not choice or not choice.text then
					return
				end

				local result = choice.text

				-- Strip leading newline if the completion starts with one
				-- (common artifact from FIM models)
				if result:sub(1, 1) == "\n" then
					result = result:sub(2)
				end

				-- When completing mid-line (non-whitespace after cursor),
				-- keep only the first line to avoid over-generation
				if context.midline then
					result = result:match("^([^\n]*)")
				end

				-- Discard empty completions
				if result == "" then
					return
				end

				vim.schedule(function()
					-- Discard if request was cancelled while waiting for vim.schedule
					if my_request_id ~= current_request_id then
						return
					end

					-- Stale response guard: discard if cursor moved since request was made
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
			end,
		})
	end)

	if not ok then
		vim.notify(string.format("Corridor: Request failed: %s", err), vim.log.levels.WARN)
	end
end

return M
