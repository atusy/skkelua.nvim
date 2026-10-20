-- 組み込み以外の補完 UI (pum.vim / nvim-cmp) の状態取得と確定。
-- 補完候補そのものは lsp.lua の in-process サーバーが返し、
-- ここは「いま補完メニューが開いているか・何が選択されているか」と
-- 「選択中の候補を確定するキー」だけを UI ごとの差異として吸収する。

local M = {}

local function is_truthy(v)
	return v == true or v == 1
end

local pum_adapter = {
	state = function()
		local info = vim.fn["pum#complete_info"]({ "pum_visible", "selected" })
		return { visible = is_truthy(info.pum_visible), selected = (info.selected or -1) >= 0 }
	end,
	confirm = function()
		return "<Cmd>call pum#map#confirm()"
	end,
}

local cmp_adapter = {
	state = function()
		return { visible = true, selected = package.loaded["cmp"].get_active_entry() ~= nil }
	end,
	confirm = function()
		return "<Cmd>lua require('cmp').confirm({select = true})"
	end,
}

--- 表示中のメニューを持つ UI を検出する。組み込みの補完メニューなら nil
local function detect()
	if vim.fn.exists("*pum#visible") == 1 and is_truthy(vim.fn["pum#visible"]()) then
		return pum_adapter
	end
	local cmp = package.loaded["cmp"]
	if cmp then
		local ok, visible = pcall(cmp.visible)
		if ok and visible then
			return cmp_adapter
		end
	end
	return nil
end

---@return {visible: boolean, selected: boolean}? state nil なら組み込みの補完メニューが担当する
function M.state()
	local adapter = detect()
	return adapter and adapter.state() or nil
end

--- 選択中の候補を確定するキー列
---@return string?
function M.confirm()
	local adapter = detect()
	return adapter and adapter.confirm() or nil
end

return M
