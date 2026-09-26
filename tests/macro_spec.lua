-- マクロ (q) の録画・再生
--
-- insert モードのキーは :lmap で張られ、マクロには打鍵でなく変換結果が
-- 記録される (init.lua の map() 参照)

local t = require("tests.helper")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "tx")
end

local function with_buffer(fn)
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	vim.fn.setreg("q", "")
	local ok, err = pcall(fn)
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	if not ok then
		error(err, 0)
	end
end

local function setup_library()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字")
end

local function tc(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

-- 「iJKanji <CR><Esc>」を録画したときに残る内容。
-- 打鍵 (K a n j i Space CR Esc) は含まれず、pre-edit の描き換えと確定文字列だけ。
-- <Esc> (無効化) の直前には、skkelua のマッピングを消す内部用の <Cmd> が入る
local RECORDED = "iJ▽k\b\b▽かn\b\b\b▽かんj\b\b\b\b▽かんじ\b\b\b\b▼漢字\b\b\b漢字\r"
	.. tc("<Cmd>")
	.. "lua local ok, m = pcall(require, 'skkelua') if ok then m._restore_pending_maps() end"
	.. tc("<CR>")
	.. "\27"

t.test("recording keeps the converted text instead of the typed keys", function()
	setup_library()
	with_buffer(function()
		feed("qqiJKanji <CR><Esc>q")
		t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
		t.assert_equals(RECORDED, vim.fn.getreg("q"))
	end)
end)

t.test("replay inserts the same text while skkelua is disabled", function()
	setup_library()
	with_buffer(function()
		feed("qqiJKanji <CR><Esc>q")
		-- 録画後は <Esc> で無効化されている。2 行目 (空行) で再生する
		feed("@q")
		t.assert_equals({ "漢字", "漢字", "" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("replay does not re-run the conversion while skkelua is enabled", function()
	setup_library()
	local skkelua = require("skkelua")
	with_buffer(function()
		-- persistent mode で insert に入るたび有効化し、再生中も有効な状態にする
		skkelua.enable_persistent_mode()
		local enabled_at_insert = {}
		local au = vim.api.nvim_create_autocmd("InsertEnter", {
			buffer = 0,
			callback = function()
				enabled_at_insert[#enabled_at_insert + 1] = skkelua.is_enabled()
			end,
		})
		local ok, err = pcall(function()
			feed("qqiKanji <CR><Esc>q")
			t.assert_equals({ "漢字", "" }, vim.fn.getline(1, "$"))
			-- 再生されるキーは打鍵ではないので :lmap は掛からず、
			-- 記録された文字列がそのまま入る
			feed("@q")
			t.assert_equals({ "漢字", "漢字", "" }, vim.fn.getline(1, "$"))
			t.assert_equals({ true, true }, enabled_at_insert)
		end)
		vim.api.nvim_del_autocmd(au)
		skkelua.disable_persistent_mode()
		if not ok then
			error(err, 0)
		end
	end)
end)

t.test("toggle key handled by skkelua is recorded as a command", function()
	setup_library()
	with_buffer(function()
		vim.cmd("imap <buffer> <C-j> <Plug>(skkelua-toggle)")
		-- 変換中の <C-j> は skkelua の :lmap に捕まり (kakutei)、ユーザーの
		-- <Plug> マッピングと同じ <Cmd> として記録される
		feed("qqi<C-j>Kanji <C-j><C-o>q")
		local reg = vim.fn.getreg("q")
		t.assert_true(reg:find([[handle("toggle", { key = "<nl>" })]], 1, true) ~= nil, reg)
		-- <Cmd> の後ろに、その toggle (変換中なので確定) が feedkeys した確定文字列が続く
		t.assert_true(reg:find("▼漢字", 1, true) ~= nil, reg)
		t.assert_true(vim.endswith(reg, "\b\b\b漢字"), reg)
		t.assert_true(reg:find("Kanji", 1, true) == nil, reg)
		t.assert_equals({ "漢字" }, vim.fn.getline(1, "$"))
		-- 再生: 先頭の <C-j> (ユーザーのマッピング) で有効化され、記録された
		-- <Cmd> で切り替えが再現され、文字列はそのまま入る
		feed("o<Esc>@q")
		t.assert_equals({ "漢字", "漢字" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("keys typed as command arguments during <C-o> are not converted", function()
	with_buffer(function()
		vim.fn.setline(1, "xxx a yyy")
		-- 'iminsert' = 1 の間は f の引数にも :lmap が掛かるが、insert 以外では
		-- キーをそのまま通すので f は "a" を探す
		feed("0iJ<C-o>fa")
		t.assert_equals({ "xxx a yyy" }, vim.fn.getline(1, "$"))
		t.assert_true(vim.fn.col(".") > 1, ("col = %d"):format(vim.fn.col(".")))
	end)
end)

t.test("iminsert is set while enabled and restored on disable", function()
	with_buffer(function()
		vim.bo.iminsert = 0
		feed("iJ")
		t.assert_equals(1, vim.bo.iminsert)
		require("skkelua").disable_impl()
		t.assert_equals(0, vim.bo.iminsert)
	end)
end)

t.test("cmdline recording keeps only the typed keys", function()
	with_buffer(function()
		vim.cmd("cnoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
		-- cmdline は通常のマッピングなので打鍵が記録される。feedkeys の出力は
		-- 録画中は 't' 無しで送り、二重に記録されないようにする
		-- Note: pre-edit 中の <C-c> は guard.lua が破棄するため直接入力で抜ける
		feed("qq:Jka<C-c>q")
		t.assert_equals(":Jka\3", vim.fn.getreg("q"))
	end)
end)

--- insertOnSelect と同じ形の skkelua 候補を complete() で出すマッピング (<C-t>) を張る。
--- items が空なら pum は開かない (再生時の「補完が無い」状況の模擬)
---@param items string[]
local function with_fake_completion(items)
	-- insertOnSelect と同じく noselect (<C-n> で最初の候補を選択挿入する)
	vim.opt_local.completeopt = "menuone,noselect"
	_G._skkelua_test_items = items
	_G._skkelua_test_complete = function()
		local list = {}
		for _, word in ipairs(_G._skkelua_test_items) do
			list[#list + 1] = {
				word = word,
				user_data = {
					nvim = {
						lsp = {
							completion_item = {
								data = { skkelua = true, midasi = "かんじ", word = word, type = "okurinasi", okuri = "", text = word },
							},
						},
					},
				},
			}
		end
		vim.fn.complete(vim.fn.col(".") - vim.fn.strlen("▽かんじ"), list)
	end
	vim.cmd([[inoremap <buffer> <C-t> <Cmd>lua require('_G')._skkelua_test_complete()<CR>]])
end

t.test("confirming a completion candidate is recorded as skkelua's own output", function()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "感じ")
	with_buffer(function()
		with_fake_completion({ "漢字", "感じ" })
		-- <C-n> で候補 (漢字) を選択挿入し、<C-y> で確定する
		feed("qqiJKanji<C-t><C-n><C-y><Esc>q")
		t.assert_equals({ "漢字" }, vim.fn.getline(1, "$"))
		t.assert_equals("漢字", lib:get_henkan_result("okurinasi", "かんじ")[1])
		local reg = vim.fn.getreg("q")
		-- native の <C-y> (\25) ではなく、pre-edit の削除 + 候補が記録される
		t.assert_true(reg:find("\25", 1, true) == nil, reg)
		t.assert_true(reg:find("▽かんじ", 1, true) ~= nil, reg)
		t.assert_true(reg:find("\b\b\b\b漢字", 1, true) ~= nil, reg)
		-- 再生 (1): 補完が同じように開く場合は pum を閉じてから置き換える
		feed("o<Esc>@q")
		t.assert_equals({ "漢字", "漢字" }, vim.fn.getline(1, "$"))
		-- 再生 (2): 補完が開かない場合 (候補が無い・応答が間に合わない) でも同じ文字列が入る
		_G._skkelua_test_items = {}
		feed("o<Esc>@q")
		t.assert_equals({ "漢字", "漢字", "漢字" }, vim.fn.getline(1, "$"))
		_G._skkelua_test_complete = nil
		_G._skkelua_test_items = nil
	end)
end)

t.test("pureSpace after an insertOnSelect selection is recorded as commit + space", function()
	local config = require("skkelua.config").config
	config.completion.insertOnSelect = true
	config.pureSpace = true
	with_buffer(function()
		with_fake_completion({ "漢字" })
		feed("qqiJKanji<C-t><C-n> <Esc>q")
		t.assert_equals({ "漢字 " }, vim.fn.getline(1, "$"))
		_G._skkelua_test_items = {}
		feed("o<Esc>@q")
		t.assert_equals({ "漢字 ", "漢字 " }, vim.fn.getline(1, "$"))
		_G._skkelua_test_complete = nil
		_G._skkelua_test_items = nil
	end)
end)
