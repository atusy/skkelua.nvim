-- ペースト前の undo 区切り
--
-- ターミナルの bracketed paste や GUI からの貼り付けは vim.paste() を通り、
-- insert モードでは nvim_put() でバッファへ直接挿入される。この挿入は
-- 進行中の insert の undo ブロックに合流するため、日本語入力の途中で
-- 貼り付けると undo 一回でそれまでの入力ごと消えてしまう。
-- そこで skkelua の有効な insert モード中は、貼り付けの直前で undo を
-- 区切り、貼り付け以降を独立した undo 単位にする。
--
-- 区切りには 'undolevels' の再設定を使う (:h undo-blocks)。<C-g>u は
-- キーとして処理されるため vim.paste() の中から同期的には使えない。
-- 同じ値を書き戻すだけなので設定値そのものは変わらない (buffer-local の
-- 「グローバルを使う」状態も維持される)

local M = {}

---@type fun(lines: string[], phase: -1|1|2|3): boolean?
local original
---@type fun(lines: string[], phase: -1|1|2|3): boolean?
local wrapper

--- 貼り付けの直前に undo を区切るべきかどうか
---@param phase integer
---@return boolean
function M._should_break(phase)
	-- ストリーミング貼り付け (phase 1,2,3) では最初のチャンクだけ区切る
	if phase >= 2 then
		return false
	end
	if not require("skkelua.config").config.setUndoPointOnPaste then
		return false
	end
	if not require("skkelua.store").status.enabled then
		return false
	end
	return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

--- 現在の undo ブロックを閉じる
function M.break_undo()
	vim.bo.undolevels = vim.bo.undolevels
end

--- vim.paste をラップする (再入可。既にラップ済みなら何もしない)
function M.attach()
	if vim.paste == wrapper then
		return
	end
	original = vim.paste
	wrapper = function(lines, phase)
		if M._should_break(phase) then
			M.break_undo()
		end
		return original(lines, phase)
	end
	vim.paste = wrapper
end

--- ラップを外す (他のプラグインが後から差し替えている場合は触らない)
function M.detach()
	if wrapper and vim.paste == wrapper then
		vim.paste = original
	end
	wrapper = nil
	original = nil
end

return M
