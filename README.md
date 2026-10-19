# skkelua.nvim

<img width="640" height="355" alt="demo" src="https://github.com/user-attachments/assets/03a07620-4db7-495a-a526-f8b9f406fef7" />

LSP-powered yet another (sometimes bit opinionated) SKK implementation for Neovim written in pure Lua.

Lua で実装した Neovim 用の SKK 日本語入力プラグインです。

## Requirements

- Neovim 0.10+
- 任意の SKK 用辞書ファイル
	- Recommendation: https://github.com/skk-dev/dict

## Installation

変換候補の取得のため、SKK 用の辞書ファイルが必要になります。
[skk-dev/dict](https://github.com/skk-dev/dict) を `$XDG_DATA_HOME/nvim/skkelua/dict` へ配置することを薦めます。
またプラグインマネージャーは Neovim built-in の [vim.pack](https://neovim.io/doc/user/pack/#vim.pack) を推奨します。

```bash
git clone https://github.com/skk-dev/dict $XDG_DATA_HOME/nvim/skkelua/dict
```

```lua
vim.pack.add({ 'https://github.com/kjuq/skkelua.nvim' })
vim.keymap.set({ 'i', 'c', 't' }, '<C-j>', '<Plug>(skkelua-enable)')
require("skkelua").config({
	globalDictionaries = {
		vim.fs.joinpath(vim.fn.stdpath('data'), 'skkelua', 'dict', 'SKK-JISYO.L'),
	},
	completionRankFile = vim.fs.joinpath(vim.fn.stdpath('state'), 'skkelua', 'rank'),
	completion = {
		enabled = true,
		insertOnSelect = true,
		deferOkuri = true, -- TODO: delete `deferOkuri`, make always defer Okuri when completion is enabled
	},
	pureSpace = true,
})
```

```lua
-- lazy.nvim
{
	"kjuq/skkelua.nvim",
	config = function()
		require("skkelua").config({
			globalDictionaries = {
				vim.fs.joinpath(vim.fn.stdpath('data'), 'skkelua', 'dict', 'SKK-JISYO.L'),
				vim.fs.joinpath(vim.fn.stdpath('data'), 'skkelua', 'dict', 'SKK-JISYO.jinmei'),
			},
		})
		vim.keymap.set({ "i", "c", "t" }, "<C-j>", "<Plug>(skkelua-toggle)")
	end,
}
```

## Usage

ユーザー辞書はデフォルトで `$XDG_DATA_HOME/skkelua/jisyo` に保存されます。

日本語入力有効にすると、変換候補が Neovim 組み込みの補完メニューに表示されます。

現在の状態は Lua API で参照できます。

```lua
require("skkelua").is_enabled()         -- 有効かどうか
require("skkelua").mode()               -- "hira" / "kata" / "hankata" / "zenkaku" / "abbrev" / ""
require("skkelua").phase()              -- "input" / "input:okurinasi" / "input:okuriari" / "henkan" / ...
require("skkelua").is_persistent_mode() -- persistent mode が有効かどうか
```

詳細は [doc/skkelua.txt](doc/skkelua.txt) を参照してください。

## Development

```sh
# テスト実行
nvim --clean --headless -l tests/run.lua # or
mise run test

# 特定の spec のみ
nvim --clean --headless -l tests/run.lua henkan

# 普段の設定と切り離して手元で試す
nvim -u tests/minimal_init.lua
```

## License

zlib license

## Credits

- [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton) (Copyright (c) 2021 kuuote, zlib license)
- [delphinus/skkeleton_indicator.nvim](https://github.com/delphinus/skkeleton_indicator.nvim) (Copyright (c) 2021 Yasushi Jinnouchi, zlib license)
