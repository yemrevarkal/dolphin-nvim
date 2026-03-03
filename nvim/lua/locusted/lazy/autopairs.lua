return {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
        require("nvim-autopairs").setup({
            check_ts = true,
        })
        -- integrate with cmp so confirming a completion also adds pairs
        local cmp_autopairs = require("nvim-autopairs.completion.cmp")
        local cmp = require("cmp")
        cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
}
