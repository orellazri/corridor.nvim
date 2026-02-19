local config = require("corridor.config")

local M = {}

M.fetch_suggestion = function(context, callback)
	local curl = require("plenary.curl")

	local system_prompt = string.format(
		"You are an expert %s developer. Provide code completion for the file '%s'. "
			.. "Respond ONLY with the code that fits between the provided PREFIX and SUFFIX. "
			.. "Do not repeat the prefix. No markdown. No explanations.",
		context.filetype,
		context.filename
	)

	local user_prompt = string.format("PREFIX:\n%s\n\nSUFFIX:\n%s", context.prefix, context.suffix)

	curl.post(config.get("endpoint"), {
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
			local status, decoded = pcall(vim.json.decode, res.body)
			if not status or not decoded.choices then
				print("Corridor Error: Could not parse API response: ", decoded)
				return
			end

			local result = decoded.choices[1].message.content

			vim.schedule(function()
				callback(result)
			end)
		end,
	})
end

return M
