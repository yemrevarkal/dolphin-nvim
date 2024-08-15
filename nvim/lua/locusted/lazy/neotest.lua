return {
    {
        "nvim-neotest/neotest",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "antoinemadec/FixCursorHold.nvim",
            "nvim-treesitter/nvim-treesitter",
            "marilari88/neotest-vitest",
            "nvim-neotest/neotest-plenary",
	    "nvim-neotest/neotest-python",
	    "nvim-neotest/nvim-nio",
	    "rouge8/neotest-rust",
        },
        config = function()
            local neotest = require("neotest")
            neotest.setup({
                adapters = {
                    require("neotest-vitest"),
		    require("neotest-plenary"),
		    require("neotest-rust"),
		    require("neotest-python")({
			dap = { justMyCode = false },
		    }),
		}
            })

            vim.keymap.set("n", "<leader>tc", function()
                neotest.run.run()
            end)
        end,
    },
}
