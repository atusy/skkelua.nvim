-- キー表記の正規化 (notation.lua)

local t = require("tests.helper")

t.test("normalize lowercases notations and resolves raw keys", function()
	local notation = require("skkelua.notation")
	local cases = {
		{ "<Bar>", "<bar>" },
		{ "|", "<bar>" },
		{ "<lt>", "<lt>" },
		{ "<", "<lt>" },
		{ "<C-J>", "<nl>" },
		{ "<Space>", "<space>" },
		{ " ", "<space>" },
		{ "A", "A" },
		{ "<s-a>", "A" },
		{ "a", "a" },
	}
	for _, c in ipairs(cases) do
		t.assert_equals(c[2], notation.normalize(c[1]), ("normalize(%s)"):format(vim.inspect(c[1])))
	end
end)

t.test("every default mapped key normalizes to a lookup-able key", function()
	local skkelua = require("skkelua")
	local notation = require("skkelua.notation")
	for _, key in ipairs(skkelua.get_default_mapped_keys()) do
		local n = notation.normalize(key)
		-- 単一文字か、notation テーブルに存在する小文字表記のどちらか。
		-- <Bar> が "<Bar>" のまま流れて "<bar>" と挿入されていた回帰ガード
		t.assert_true(
			#n == 1 or (notation.notation_to_key[n] ~= nil and n == n:lower()),
			("%s -> %s"):format(vim.inspect(key), vim.inspect(n))
		)
	end
end)
