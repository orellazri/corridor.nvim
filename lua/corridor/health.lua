local M = {}

--- Run health checks for :checkhealth corridor.
M.check = function()
	vim.health.start("corridor.nvim")

	-- Check Neovim version >= 0.10
	if vim.fn.has("nvim-0.10") == 1 then
		vim.health.ok("Neovim >= 0.10")
	else
		vim.health.error("Neovim >= 0.10 is required", { "Upgrade Neovim to 0.10 or later" })
	end

	-- Check plenary.nvim
	local has_plenary = pcall(require, "plenary")
	if has_plenary then
		vim.health.ok("plenary.nvim is installed")
	else
		vim.health.error("plenary.nvim is not installed", {
			"Install plenary.nvim: https://github.com/nvim-lua/plenary.nvim",
		})
	end

	-- Check configuration
	local config = require("corridor.config")

	-- Provider
	local provider = config.get("provider")
	if provider and (provider == "lmstudio" or provider == "codestral") then
		vim.health.ok(string.format("Provider: %s", provider))
	elseif provider then
		vim.health.warn(string.format("Unknown provider: %q", provider), {
			'Supported providers: "lmstudio", "codestral"',
		})
	else
		vim.health.error("No provider configured")
	end

	-- Endpoint
	local endpoint = config.get("endpoint")
	if endpoint and endpoint ~= "" then
		vim.health.ok(string.format("Endpoint: %s", endpoint))
	else
		vim.health.error("No endpoint configured", {
			"Set an endpoint explicitly or use a known provider to auto-resolve it",
		})
	end

	-- Model
	local model = config.get("model")
	if model and model ~= "" then
		vim.health.ok(string.format("Model: %s", model))
	else
		vim.health.warn("No model configured", { 'Set the "model" option in setup()' })
	end

	-- API key (required for codestral, optional for lmstudio)
	local api_key = config.get("api_key") or os.getenv("CORRIDOR_API_KEY")
	if provider == "codestral" then
		if api_key and api_key ~= "" then
			vim.health.ok("API key is set (codestral)")
		else
			vim.health.error("API key is required for codestral provider", {
				'Set "api_key" in setup() or the CORRIDOR_API_KEY environment variable',
			})
		end
	else
		if api_key and api_key ~= "" then
			vim.health.ok("API key is set")
		else
			vim.health.info("No API key set (not required for lmstudio)")
		end
	end

	-- FIM tokens
	local fim = config.get("fim")
	if fim and fim.prefix and fim.suffix and fim.middle then
		vim.health.ok("FIM tokens are configured")
	else
		vim.health.error("FIM tokens are incomplete", {
			'The "fim" table must have "prefix", "suffix", and "middle" keys',
		})
	end
end

return M
