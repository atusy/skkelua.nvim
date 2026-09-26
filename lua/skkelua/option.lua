-- オプションの保存・設定・復元 (autoload/skkeleton/internal/option.vim に相当)

local M = {}

---@type table<integer, integer> bufnr -> textwidth
local textwidth_vault = {}
---@type table<integer, integer> bufnr -> iminsert
local iminsert_vault = {}
---@type table<integer, boolean> insert 中の無効化で 'iminsert' の復元を保留しているバッファ
local iminsert_pending = {}
---@type table<integer, string> winid -> virtualedit
local virtualedit_vault = {}

local group = vim.api.nvim_create_augroup("skkelua-option-vault", { clear = true })

-- bufnr は再利用されるため、消えたバッファの保存内容は破棄する
vim.api.nvim_create_autocmd("BufWipeout", {
	group = group,
	callback = function(ev)
		textwidth_vault[ev.buf] = nil
		iminsert_vault[ev.buf] = nil
		iminsert_pending[ev.buf] = nil
	end,
})

local function termcode(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

---@return boolean
local function in_insert()
	return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

-- :lmap が有効か (Neovim 内部の State の MODE_LANGMAP フラグ) の追跡。
-- State は insert モードに入るたびにそのバッファの 'iminsert' から計算され、
-- insert 中は i_CTRL-^ でしか切り替わらない。State はグローバルで
-- 'iminsert' はバッファローカルなので、insert 中に別バッファの window へ
-- 移ると (辞書登録プロンプトなど) 'iminsert' の値だけでは判断できない
local langmap_on = false
-- set_iminsert が送った CTRL-^ がまだ処理されていないか
-- (guard.lua はユーザーの CTRL-^ を破棄するため、自前のものと区別する)
local ctrl_hat_pending = false

vim.api.nvim_create_autocmd("InsertEnter", {
	group = group,
	callback = function()
		-- InsertEnter の時点ではまだ insert ではなく、この後 'iminsert' から
		-- State が計算される (persistent mode などがこの autocmd の中で
		-- 'iminsert' を 1 にした場合は set_iminsert 側で追跡を更新する)
		langmap_on = vim.bo.iminsert == 1
		ctrl_hat_pending = false
	end,
})

--- guard.lua 用: 自前で送った CTRL-^ を待っていれば true を返して消費する
---@return boolean
function M._take_pending_ctrl_hat()
	local pending = ctrl_hat_pending
	ctrl_hat_pending = false
	return pending
end

--- 'iminsert' を 1 にして :lmap (init.lua の map() 参照) が効くようにする。
---
--- insert 中にオプションを書き換えても State は変わらないため、State が
--- 無効なまま insert 中に有効化された場合は i_CTRL-^ を送って 'iminsert' と
--- State を一緒に切り替える。insert 中は 'iminsert' をここ以外で変えない
--- (restore() が insert 中の復元を保留するのもこのため)。
--- CTRL-^ は 'iminsert' のグローバル値も書き換えて新規バッファへ伝播させる
--- ため、直後に元へ戻す
---@param bufnr integer
local function set_iminsert(bufnr)
	if vim.bo[bufnr].iminsert == 1 then
		return
	end
	if not in_insert() or langmap_on then
		-- insert 外 (InsertEnter 含む) なら insert に入る時に State が計算される。
		-- insert 中でも State が既に有効なら値を合わせるだけでよい
		vim.bo[bufnr].iminsert = 1
		langmap_on = true
		return
	end
	langmap_on = true
	ctrl_hat_pending = true
	local global = vim.api.nvim_get_option_value("iminsert", { scope = "global" })
	local restore_global = ("<Cmd>lua vim.api.nvim_set_option_value('iminsert', %d, { scope = 'global' })<CR>"):format(
		global
	)
	vim.api.nvim_feedkeys("\30" .. termcode(restore_global), "ni", false)
end

--- 保留していた 'iminsert' の復元を行う (insert を抜けたタイミングで呼ぶ)
local function restore_pending_iminsert()
	for bufnr in pairs(iminsert_pending) do
		iminsert_pending[bufnr] = nil
		if iminsert_vault[bufnr] ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
			vim.bo[bufnr].iminsert = iminsert_vault[bufnr]
		end
		iminsert_vault[bufnr] = nil
	end
end

-- insert 中に無効化された場合の 'iminsert' の復元は、State の計算がやり直される
-- normal モードへ戻ったところで行う (set_iminsert 参照)
vim.api.nvim_create_autocmd("ModeChanged", {
	group = group,
	pattern = "*:n",
	callback = restore_pending_iminsert,
})

function M.save_and_set()
	-- cmdline 関係ないオプションだけなので cmdline では飛ばす
	if vim.fn.mode() == "c" then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	if textwidth_vault[bufnr] == nil then
		textwidth_vault[bufnr] = vim.bo[bufnr].textwidth
	end
	if iminsert_vault[bufnr] == nil then
		iminsert_vault[bufnr] = vim.bo[bufnr].iminsert
	end
	iminsert_pending[bufnr] = nil
	if virtualedit_vault[winid] == nil then
		virtualedit_vault[winid] = vim.wo[winid].virtualedit
	end
	-- 不意に改行が発生してバッファが壊れるため 'textwidth' を無効化
	vim.bo[bufnr].textwidth = 0
	-- insert モードのキーは :lmap で張るため 'iminsert' を 1 にする
	set_iminsert(bufnr)
	-- 末尾で送りあり変換をした際にバッファが壊れるため、一時的に 'virtualedit' を使う
	vim.wo[winid].virtualedit = "onemore"
end

function M.restore()
	if vim.fn.mode() == "c" then
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()
	local winid = vim.api.nvim_get_current_win()
	if textwidth_vault[bufnr] ~= nil then
		vim.bo[bufnr].textwidth = textwidth_vault[bufnr]
		textwidth_vault[bufnr] = nil
	end
	if iminsert_vault[bufnr] ~= nil then
		if in_insert() then
			-- insert 中に 'iminsert' を書き戻すと State と食い違う (set_iminsert
			-- 参照) ため、insert を抜けるまで保留する。skkelua の :lmap は
			-- 消えているので、'iminsert' が 1 のままでも入力には影響しない
			iminsert_pending[bufnr] = true
		else
			vim.bo[bufnr].iminsert = iminsert_vault[bufnr]
			iminsert_vault[bufnr] = nil
		end
	end
	if virtualedit_vault[winid] ~= nil then
		vim.wo[winid].virtualedit = virtualedit_vault[winid]
		virtualedit_vault[winid] = nil
	end
end

--- テスト用: 'iminsert' の復元を保留しているかどうか
---@param bufnr integer
---@return boolean
function M._is_iminsert_pending(bufnr)
	return iminsert_pending[bufnr] == true
end

--- テスト用: :lmap が有効と追跡しているかどうか
---@return boolean
function M._is_langmap_on()
	return langmap_on
end

return M
