-- バッファローカルマッピングの保存・復元 (autoload/skkeleton/internal/map.vim に相当)

local M = {}

---@type table<integer, table<string, table[]>> bufnr -> mode -> keymaps
local vault = {}

-- bufnr は再利用されるため、消えたバッファの保存内容は破棄する
vim.api.nvim_create_autocmd("BufWipeout", {
	group = vim.api.nvim_create_augroup("skkelua-map-vault", { clear = true }),
	callback = function(ev)
		vault[ev.buf] = nil
	end,
})

--- 現在のバッファの指定モードのマッピングを保存する
---@param mode string
function M.save(mode)
	local bufnr = vim.api.nvim_get_current_buf()
	vault[bufnr] = vault[bufnr] or {}
	local buf = vault[bufnr]
	if buf[mode] then
		return
	end
	buf[mode] = vim.api.nvim_buf_get_keymap(bufnr, mode)
end

--- 保存したマッピングを復元する
---@param bufnr? integer 省略時は現在のバッファ
function M.restore(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local buf = vault[bufnr] or {}
	vault[bufnr] = nil
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.api.nvim_buf_call(bufnr, function()
		for mode, maps in pairs(buf) do
			vim.cmd(mode .. "mapclear <buffer>")
			for _, m in ipairs(maps) do
				pcall(vim.fn.mapset, mode, false, m)
			end
		end
	end)
end

return M
