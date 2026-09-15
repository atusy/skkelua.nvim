-- ペースト前の undo 区切り (paste.lua) のテスト
--
-- Note: bracketed paste は headless では発生させられないため、insert 中に
--       vim.paste() を呼ぶバッファローカルマッピングで貼り付けを模擬する

local t = require("tests.helper")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "tx")
end

local function with_buffer(fn)
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	vim.keymap.set("i", "<F5>", function()
		vim.paste({ "PASTE" }, -1)
	end, { buffer = true })
	local ok, err = pcall(fn)
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	if not ok then
		error(err, 0)
	end
end

--- undo を繰り返して 1 行目の遷移を返す
---@return string[]
local function undo_trail()
	local trail = {}
	for _ = 1, 10 do
		local before = vim.fn.undotree().seq_cur
		vim.cmd("silent! undo")
		if vim.fn.undotree().seq_cur == before then
			break
		end
		trail[#trail + 1] = vim.fn.getline(1)
	end
	return trail
end

t.test("paste during kana input starts a new undo block", function()
	with_buffer(function()
		feed("iJaiu<F5>eo")
		t.assert_equals("あいうPASTEえお", vim.fn.getline(1))
		-- 貼り付け以降だけが先に消え、その前の入力は残る
		t.assert_equals({ "あいう", "" }, undo_trail())
	end)
end)

t.test("paste keeps the insert undo block when setUndoPointOnPaste is false", function()
	require("skkelua.config").config.setUndoPointOnPaste = false
	with_buffer(function()
		feed("iJaiu<F5>eo")
		t.assert_equals("あいうPASTEえお", vim.fn.getline(1))
		t.assert_equals({ "" }, undo_trail())
	end)
end)

t.test("paste is untouched while skkelua is disabled", function()
	-- 一度 enable してラップは入っているが、無効化中は Neovim 標準のまま
	with_buffer(function()
		feed("iJ<Esc>")
		t.assert_true(not require("skkelua").is_enabled())
		feed("iabc<F5>d")
		t.assert_equals("abcPASTEd", vim.fn.getline(1))
		t.assert_equals({ "" }, undo_trail())
	end)
end)

t.test("streamed paste breaks undo only at the first chunk", function()
	local paste = require("skkelua.paste")
	with_buffer(function()
		-- 判定は insert モード中に行われるため、マッピングの中で観測する
		local results
		vim.keymap.set("i", "<F6>", function()
			results = {
				paste._should_break(1),
				paste._should_break(-1),
				paste._should_break(2),
				paste._should_break(3),
			}
		end, { buffer = true })
		feed("iJ<F6>")
		t.assert_equals({ true, true, false, false }, results)
	end)
end)

t.test("attach is idempotent and detach restores vim.paste", function()
	local paste = require("skkelua.paste")
	paste.detach()
	local orig = vim.paste
	paste.attach()
	local wrapped = vim.paste
	t.assert_true(wrapped ~= orig)
	paste.attach()
	t.assert_equals(wrapped, vim.paste)
	paste.detach()
	t.assert_equals(orig, vim.paste)
	-- 他のプラグインが後から差し替えていたら触らない
	paste.attach()
	local other = function() end
	vim.paste = other
	paste.detach()
	t.assert_equals(other, vim.paste)
	vim.paste = orig
end)
