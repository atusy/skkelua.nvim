local t = require("tests.helper")

local function setup_input(keys)
	local skk = require("skkelua")
	skk._handle_request("enable", {}, { mode = "", prevInput = "", completeInfo = {}, completeType = "" })
	for _, key in ipairs(keys or { "K", "a", "n", "j", "i" }) do
		skk._handle_request("handleKey", { key = { key } }, {
			mode = "",
			prevInput = skk.get_pre_edit(),
			completeInfo = {},
			completeType = "",
		})
	end
	return skk
end

t.test("external completion uses explicit byte position without changing UI", function()
	local skk = setup_input()
	require("skkelua.store").get_library():register_henkan_result("okurinasi", "かんじ", "漢字;annotation")
	local before = vim.bo.completeopt
	local line = "😀 " .. skk.get_pre_edit() .. " suffix"
	local list = require("skkelua.completion").get({ line = line, row = 3, col = #("😀 " .. skk.get_pre_edit()) })
	t.assert_equals("漢字", list.items[1].label)
	t.assert_equals("漢字", list.items[1].textEdit.newText)
	t.assert_equals(1, list.items[1].insertTextFormat)
	t.assert_equals({ line = 3, character = #"😀 " }, list.items[1].textEdit.range.start)
	t.assert_equals(before, vim.bo.completeopt)
	t.assert_equals(0, #require("skkelua.completion").get({ line = "stale", row = 0, col = 5 }).items)
end)

t.test("external acceptance learns original dictionary metadata", function()
	local skk = setup_input()
	local lib = require("skkelua.store").get_library()
	lib:register_henkan_result("okurinasi", "かんじ", "漢字;annotation")
	local completion = require("skkelua.completion")
	local item = completion.get({ line = skk.get_pre_edit(), row = 0, col = #skk.get_pre_edit() }).items[1]
	t.assert_equals(true, completion.accept(item))
	t.assert_equals("漢字;annotation", require("skkelua.store").get_context().lastCandidate.candidate)
	t.assert_equals(false, completion.accept({ label = "unrelated" }))
end)

t.test("external server returns candidates from the request document", function()
	local skk = setup_input()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, vim.fn.tempname())
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { skk.get_pre_edit() })
	local server = require("skkelua.lsp").new_server()({ on_exit = function() end })
	local result
	local ok, id = server.request("textDocument/completion", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = 0, character = #skk.get_pre_edit() },
	}, function(err, value)
		t.assert_equals(nil, err)
		result = value
	end)
	t.assert_equals(true, ok)
	t.assert_true(type(id) == "number")
	t.assert_true(vim.wait(1000, function()
		return result ~= nil
	end))
	t.assert_equals(true, result.items[#result.items].data.register)
	server.terminate()
	vim.api.nvim_buf_delete(buf, { force = true })
end)

t.test("external LSP works with a real client without enabling native UI", function()
	local skk = setup_input()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, vim.fn.tempname())
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { skk.get_pre_edit() })
	local before = vim.bo[buf].completeopt
	local id = vim.lsp.start({ name = "skkelua", cmd = require("skkelua.lsp").new_server() }, {
		bufnr = buf,
		reuse_client = function()
			return false
		end,
	})
	local client = vim.lsp.get_client_by_id(id)
	t.assert_true(vim.wait(1000, function()
		return client.initialized
	end))
	local result
	local ok, request_id = client:request("textDocument/completion", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = 0, character = #skk.get_pre_edit() },
	}, function(err, value)
		t.assert_equals(nil, err)
		result = value
	end, buf)
	t.assert_equals(true, ok)
	t.assert_true(vim.wait(1000, function()
		return result ~= nil
	end))
	t.assert_equals(nil, client.requests[request_id])
	t.assert_equals(before, vim.bo[buf].completeopt)
	t.assert_equals(true, result.items[#result.items].data.register)
	client:stop(true)
	vim.api.nvim_buf_delete(buf, { force = true })
end)

t.test("adapter routes selected insertion and restoration trigger", function()
	vim.cmd.enew({ bang = true })
	local buf = vim.api.nvim_get_current_buf()
	local completion = require("skkelua.completion")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "prefix 漢字 tail" })
	vim.api.nvim_win_set_cursor(0, { 1, #"prefix 漢字" })
	local calls = 0
	completion.set_adapter({
		state = function()
			return {
				visible = true,
				selected = { word = "漢字", item = { data = { skkelua = true, word = "漢字" } } },
			}
		end,
		confirm = function()
			return "\25"
		end,
		trigger = function()
			calls = calls + 1
		end,
	})
	local word, data = require("skkelua.lsp").selected_word()
	t.assert_equals("漢字", word)
	t.assert_equals("漢字", data.word)
	t.assert_equals(true, completion.visible())
	require("skkelua.lsp").trigger()
	t.assert_equals(1, calls)
	completion.set_adapter(nil)
	t.assert_equals(nil, completion.state())
	vim.api.nvim_buf_delete(buf, { force = true })
end)

t.test("virtual document provider supplies cmdline byte ranges", function()
	local skk = setup_input()
	local line = "検索 " .. skk.get_pre_edit()
	local server = require("skkelua.lsp").new_server(function(params)
		if params.textDocument.uri ~= "test:cmdline" then
			return nil
		end
		return { line = line, row = 0, col = #line }
	end)({ on_exit = function() end })
	local results = {}
	for _, uri in ipairs({ "test:cmdline", "test:other" }) do
		server.request("textDocument/completion", { textDocument = { uri = uri } }, function(err, result)
			t.assert_equals(nil, err)
			results[uri] = result
		end)
	end
	t.assert_true(vim.wait(1000, function()
		return results["test:other"] ~= nil
	end))
	t.assert_equals(#"検索 ", results["test:cmdline"].items[1].textEdit.range.start.character)
	t.assert_equals(0, #results["test:other"].items)
	server.terminate()
end)

t.test("abbrev external items are literal text and raw acceptance does not learn", function()
	local skk = setup_input({ "/", "$", "x" })
	local completion = require("skkelua.completion")
	local list = completion.get({ line = skk.get_pre_edit(), row = 0, col = #skk.get_pre_edit() })
	t.assert_equals(" $x", list.items[1].label)
	t.assert_equals(" $x", list.items[1].textEdit.newText)
	t.assert_equals(1, list.items[1].insertTextFormat)
	local before = vim.deepcopy(require("skkelua.store").get_context().lastCandidate)
	t.assert_equals(true, completion.accept(list.items[1]))
	t.assert_equals(before, require("skkelua.store").get_context().lastCandidate)
end)

t.test("detaching builtin completion preserves an external client", function()
	t.assert_true(vim.wait(1000, function()
		return #vim.lsp.get_clients({ name = "skkelua", _uninitialized = true }) == 0
	end))
	local lsp = require("skkelua.lsp")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	local external_id = vim.lsp.start({ name = "skkelua", cmd = lsp.new_server() }, { bufnr = buf })
	local external = vim.lsp.get_client_by_id(external_id)
	t.assert_true(vim.wait(1000, function()
		return external.initialized
	end))
	require("skkelua").config({ completion = { enabled = true } })
	lsp.attach()
	local builtin
	t.assert_true(vim.wait(1000, function()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
			if client.config.skkelua_builtin_completion then
				builtin = client
				return true
			end
		end
		return false
	end))
	local get_clients = vim.lsp.get_clients
	vim.lsp.get_clients = function(opts)
		local clients = get_clients(opts)
		-- Client iteration order is unspecified; cover external-first selection.
		table.sort(clients, function(a, b)
			return a.id < b.id
		end)
		return clients
	end
	local enable = vim.lsp.completion.enable
	local disabled = {}
	vim.lsp.completion.enable = function(on, id, ...)
		if not on then
			disabled[#disabled + 1] = id
		end
		return enable(on, id, ...)
	end
	local ok, err = pcall(function()
		lsp.detach()
		t.assert_equals({ builtin.id }, disabled)
		t.assert_true(not external:is_stopped())
		t.assert_true(vim.lsp.buf_is_attached(buf, external_id))
		lsp.attach()
		disabled = {}
		require("skkelua").config({ completion = { enabled = false } })
		lsp.detach()
		t.assert_equals({ builtin.id }, disabled)
		t.assert_equals(vim.go.completeopt, vim.bo[buf].completeopt)
	end)
	vim.lsp.completion.enable = enable
	vim.lsp.get_clients = get_clients
	external:stop(true)
	builtin:stop(true)
	vim.api.nvim_buf_delete(buf, { force = true })
	if not ok then
		error(err)
	end
end)

t.test("cancelled native completion clears tracking without invoking its callback", function()
	t.assert_true(vim.wait(1000, function()
		return #vim.lsp.get_clients({ name = "skkelua", _uninitialized = true }) == 0
	end))
	setup_input()
	local lsp = require("skkelua.lsp")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "漢字 " })
	vim.api.nvim_win_set_cursor(0, { 1, #"漢字" })
	local state_reads = 0
	require("skkelua.completion").set_adapter({
		state = function()
			state_reads = state_reads + 1
			return { visible = true, selected = { word = "漢字", item = { data = { skkelua = true } } } }
		end,
		confirm = function()
			return ""
		end,
	})
	require("skkelua").config({ completion = { enabled = true } })
	lsp.attach()
	local client
	t.assert_true(vim.wait(1000, function()
		client = vim.lsp.get_clients({ bufnr = buf })[1]
		return client ~= nil
	end))
	local called = false
	local ok, id = client:request("textDocument/completion", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = 0, character = #"漢字" },
	}, function()
		called = true
	end, buf)
	t.assert_equals(true, ok)
	local success, err = pcall(function()
		t.assert_true(vim.wait(1000, function()
			return state_reads > 0
		end))
		t.assert_true(client.requests[id] ~= nil)
		client:cancel_request(id)
		t.assert_true(vim.wait(1000, function()
			return client.requests[id] == nil
		end))
		t.assert_equals(false, called)
	end)
	require("skkelua.completion").set_adapter(nil)
	client:stop(true)
	vim.api.nvim_buf_delete(buf, { force = true })
	if not success then
		error(err)
	end
end)
