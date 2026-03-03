return {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    config = function()
        require("conform").setup({
            formatters_by_ft = {
                python = { "black", "isort" },
                rust = { "rustfmt" },
                lua = { "stylua" },
                javascript = { "prettier" },
                typescript = { "prettier" },
                c = { "clang-format" },
                cpp = { "clang-format" },
                cuda = { "clang-format" },
            },
            format_on_save = {
                timeout_ms = 500,
                lsp_format = "fallback",
            },
        })
    end,
}
