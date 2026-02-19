local config = require("corridor.config")

local M = {}

-- Monotonically increasing ID to track the latest request
local current_request_id = 0

-- Reference to the currently in-flight plenary job so we can kill it
local current_job = nil

M.cancel = function()
	current_request_id = current_request_id + 1
	if current_job then
		-- pcall because plenary's curl raises an error when a job is killed
		-- mid-flight (exit_code=nil triggers error() in its on_exit handler)
		pcall(function()
			current_job:shutdown()
		end)
		current_job = nil
	end
end

M.fetch_suggestion = function(context, callback)
	local curl = require("plenary.curl")

	-- Cancel any previous in-flight request
	M.cancel()

	-- Capture this request's ID so the callback can check for staleness
	local my_request_id = current_request_id

	-- Capture cursor position at request time for stale response detection
	local request_buf = vim.api.nvim_get_current_buf()
	local request_cursor = vim.api.nvim_win_get_cursor(0)

	local system_prompt = string.format(
		"You are an expert %s developer. Provide code completion for the file '%s'. "
			.. "Respond ONLY with the code that fits between the provided PREFIX and SUFFIX. "
			.. "Do not repeat the prefix. No markdown. No explanations.",
		context.filetype,
		context.filename
	)

	local user_prompt = string.format("PREFIX:\n%s\n\nSUFFIX:\n%s", context.prefix, context.suffix)

	current_job = curl.post(config.get("endpoint"), {
		headers = { ["Content-Type"] = "application/json" },
		body = vim.fn.json_encode({
			model = config.get("model"),
			messages = {
				{
					role = "system",
					content = system_prompt,
				},
				{ role = "user", content = user_prompt },
			},
			temperature = config.get("temperature"),
			max_tokens = config.get("max_tokens"),
			stop = { "\n\n", "SUFFIX:", "PREFIX:" },
		}),
		callback = function(res)
			-- Discard if a newer request has been made since this one fired
			if my_request_id ~= current_request_id then
				return
			end

			local status, decoded = pcall(vim.json.decode, res.body)
			if not status or not decoded.choices then
				print("Corridor Error: Could not parse API response: ", decoded)
				return
			end

			local result = decoded.choices[1].message.content

			vim.schedule(function()
				-- Discard if request was cancelled while waiting for vim.schedule
				if my_request_id ~= current_request_id then
					return
				end

				-- Stale response guard: discard if cursor moved since request was made
				local current_buf = vim.api.nvim_get_current_buf()
				local current_cursor = vim.api.nvim_win_get_cursor(0)
				if current_buf ~= request_buf
					or current_cursor[1] ~= request_cursor[1]
					or current_cursor[2] ~= request_cursor[2]
				then
					return
				end

				current_job = nil
				callback(result)
			end)
		end,
	})
end

return M
