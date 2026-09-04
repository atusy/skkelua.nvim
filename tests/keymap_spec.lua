-- keymap_test.ts の移植

local t = require("tests.helper")

-- Note: skkeleton#handle はバッファと preEdit の一貫性を要求する
-- (不一致だと状態がリセットされる) ため、prevInput を preEdit に追随させる
local function handle_key(key)
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	local vim_status = {
		mode = "",
		prevInput = store.get_context():to_string(),
		completeInfo = {},
		completeType = "",
	}
	skkelua._handle_request("handleKey", { key = { key } }, vim_status)
end

t.test("registerKeyMap", function()
	t.clean_dictionary_config()
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	local lib = store.get_library()
	lib:register_henkan_result("okurinasi", "あ", "亜")
	skkelua.register_keymap("henkan", "x", "")
	skkelua.register_keymap("henkan", "<BS>", "henkanBackward")

	-- fallback to default mapping because "x" was unmapped
	handle_key("A")
	handle_key(" ")
	handle_key("x")
	t.assert_equals("x", store.get_context():to_string())

	store.init_context()

	-- backward state with <BS>
	handle_key("A")
	handle_key(" ")
	handle_key("<bs>")
	t.assert_equals("▽あ", store.get_context():to_string())

	store.init_context()

	-- register a keymap that consists of a single capital letter
	skkelua.register_keymap("henkan", "B", "henkanBackward")
	handle_key("A")
	handle_key(" ")
	handle_key("B")
	t.assert_equals("▽あ", store.get_context():to_string())

	store.init_context()

	-- remove a keymap registered above
	skkelua.register_keymap("henkan", "B", "")
	handle_key("A")
	handle_key(" ")
	handle_key("B")
	t.assert_equals("▽b", store.get_context():to_string())
end)

t.test("send multiple keys into handleKey", function()
	t.clean_dictionary_config()
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	local lib = store.get_library()
	lib:register_henkan_result("okurinasi", "われ", "我")
	lib:register_henkan_result("okuriari", "おもu", "思")

	local vim_status = { mode = "", prevInput = "", completeInfo = {}, completeType = "" }
	skkelua._handle_request("handleKey", { key = { "W", "a", "r", "e" } }, vim_status)
	t.assert_equals("▽われ", store.get_context():to_string())

	store.init_context()

	skkelua._handle_request("handleKey", { key = { "O", "m", "o", "U" } }, vim_status)
	t.assert_equals("▼思う", store.get_context():to_string())
end)

t.test("handle normalizes mixed-case notation", function()
	t.clean_dictionary_config()
	local skkelua = require("skkelua")
	local store = require("skkelua.store")
	local lib = store.get_library()
	lib:register_henkan_result("okurinasi", "あ", "亜")
	lib:register_henkan_result("okurinasi", "あ", "阿")

	-- "<Bar>" は小文字表記のテーブルに当たらず、そのまま挿入されていた
	local ret = skkelua._handle_request("handleKey", { key = { "<Bar>" } }, {
		mode = "",
		prevInput = "",
		completeInfo = {},
		completeType = "",
	})
	t.assert_equals("|", ret.result)

	store.init_context()

	-- keymap の lookup も大文字混じり表記で当たる (<Space> -> henkanForward)
	handle_key("A")
	handle_key(" ")
	local first = store.get_context():to_string()
	handle_key("<Space>")
	local second = store.get_context():to_string()
	t.assert_true(first ~= second, ("first=%s second=%s"):format(first, second))
	t.assert_equals("▼亜", second)
end)
