-- 'iminsert' (:lmap の有効・無効) の管理 (option.lua) のテスト
--
-- insert モードのキーは :lmap で張る (init.lua の map() 参照) ため、
-- skkelua が有効な間は 'iminsert' が 1 で、内部の State (MODE_LANGMAP) も
-- 有効でなければならない

local t = require("tests.helper")

local function feed(keys)
	vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "tx")
end

local function with_buffer(fn)
	vim.cmd.enew({ bang = true })
	vim.cmd("inoremap <buffer> J <Cmd>lua require('skkelua').handle('enable', {})<CR>")
	local ok, err = pcall(fn)
	vim.cmd("stopinsert")
	vim.cmd.bwipeout({ bang = true })
	if not ok then
		error(err, 0)
	end
end

t.test("enabling in the middle of insert turns :lmap on", function()
	with_buffer(function()
		-- insert に入った時点では 'iminsert' が 0 なので State も無効。
		-- 有効化で CTRL-^ が送られ、続くキーが :lmap で処理される
		feed("iJka")
		t.assert_equals({ "か" }, vim.fn.getline(1, "$"))
		t.assert_equals(1, vim.bo.iminsert)
		-- グローバル値 (新規バッファへ伝播する) は変えない
		t.assert_equals(0, vim.api.nvim_get_option_value("iminsert", { scope = "global" }))
	end)
end)

t.test("enabling before insert turns :lmap on without CTRL-^", function()
	with_buffer(function()
		-- normal モードで有効化 -> 'iminsert' だけ変えて insert に入る
		require("skkelua").handle("enable", {})
		t.assert_equals(1, vim.bo.iminsert)
		feed("ika")
		t.assert_equals({ "か" }, vim.fn.getline(1, "$"))
	end)
end)

t.test("disabling during insert defers the iminsert restore", function()
	with_buffer(function()
		local option = require("skkelua.option")
		local buf = vim.api.nvim_get_current_buf()
		local observed
		vim.keymap.set("i", "<F6>", function()
			observed = {
				iminsert = vim.bo.iminsert,
				pending = option._is_iminsert_pending(buf),
				enabled = require("skkelua").is_enabled(),
			}
		end, { buffer = true })
		-- l で無効化しても insert 中は 'iminsert' を戻さず、続く入力は素通し
		feed("iJkalka<F6>")
		t.assert_equals({ "かka" }, vim.fn.getline(1, "$"))
		t.assert_equals({ iminsert = 1, pending = true, enabled = false }, observed)
		-- insert を抜けたところで復元される (feedkeys の 'x' が insert を抜ける)
		t.assert_equals(0, vim.bo.iminsert)
		t.assert_true(not option._is_iminsert_pending(buf))
	end)
end)

t.test("re-enabling during the same insert session works without CTRL-^", function()
	with_buffer(function()
		local option = require("skkelua.option")
		local buf = vim.api.nvim_get_current_buf()
		local observed
		vim.keymap.set("i", "<F6>", function()
			observed = { iminsert = vim.bo.iminsert, pending = option._is_iminsert_pending(buf) }
		end, { buffer = true })
		-- 無効化で保留した 'iminsert' = 1 のまま再有効化する
		-- (State は有効のままなので値を合わせるだけでよい)
		feed("iJkalkaJki<F6>")
		t.assert_equals({ "かkaき" }, vim.fn.getline(1, "$"))
		t.assert_equals({ iminsert = 1, pending = false }, observed)
	end)
end)

t.test("enabling in another buffer during the same insert session works", function()
	-- 辞書登録プロンプトのように、insert のまま別バッファの window へ移って
	-- 有効化する。State は有効なまま持ち越されるので CTRL-^ を送ってはいけない
	with_buffer(function()
		local float_buf
		vim.keymap.set("i", "<F5>", function()
			float_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_open_win(float_buf, true, {
				relative = "editor",
				row = 1,
				col = 1,
				width = 20,
				height = 1,
				style = "minimal",
			})
			require("skkelua").handle("enable", {})
		end, { buffer = true })
		local buf = vim.api.nvim_get_current_buf()
		feed("iJka<F5>ki")
		t.assert_equals({ "か" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		t.assert_equals({ "き" }, vim.api.nvim_buf_get_lines(float_buf, 0, -1, false))
		t.assert_equals(1, vim.bo[float_buf].iminsert)
		vim.api.nvim_buf_delete(float_buf, { force = true })
	end)
end)

t.test("CTRL-^ is discarded while enabled", function()
	with_buffer(function()
		-- 素の Neovim では :lmap を切って以降の入力を素通しにするキー
		feed("iJka<C-^>ki")
		t.assert_equals({ "かき" }, vim.fn.getline(1, "$"))
		t.assert_equals(1, vim.bo.iminsert)
	end)
end)
