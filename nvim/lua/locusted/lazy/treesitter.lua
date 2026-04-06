return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
        require("nvim-treesitter").setup({
            ensure_installed = {
                "vimdoc", "javascript", "typescript", "c", "lua", "rust",
                "python", "bash", "markdown", "markdown_inline",
            },
            auto_install = true,
        })

        -- Enable treesitter highlighting and indent for all supported filetypes
        vim.api.nvim_create_autocmd("FileType", {
            callback = function()
                pcall(vim.treesitter.start)
            end,
        })

        vim.treesitter.language.register("templ", "templ")
        ColorMyPencils()
    end
}
