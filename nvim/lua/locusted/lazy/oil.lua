return {
	"stevearc/oil.nvim",
	config = function()
		require("oil").setup({
			default_file_explorer = true,
			columns = {},
			view_options = {
				show_hidden = true,
			},
			win_options = {
				signcolumn = "yes",
				cursorcolumn = false,
				foldcolumn = "0",
				spell = false,
				list = false,
				conceallevel = 3,
				concealcursor = "nvic",
			},
		})
		vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
		vim.keymap.set("n", "<leader>pv", "<CMD>Oil<CR>", { desc = "Open parent directory" })
	end,
}
