-- List of favorite files/marks per project
return {
  -- https.//github.com/ThePrimeagen/harpoon
  'RichGuk/harpoon',
  branch = 'harpoon2',
  event = 'VeryLazy',
  dependencies = {
    -- https.//github.com/nvim-lua/plenary.nvim
    'nvim-lua/plenary.nvim',
  },
  opts = {
    menu = {
      width = 120
    }
  },
  config = function()
    local harpoon = require("harpoon")
    harpoon.setup({})
    vim.keymap.set("n", "<leader>ha", function()
      harpoon:list():append()
    end)
    vim.keymap.set("n", "<leader>hc", function()
      harpoon:list():clear()
    end)
    vim.keymap.set("n", "<leader>hh", function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end)
    vim.keymap.set("n", "<leader>1", function()
      harpoon:list():select(1)
    end)
    vim.keymap.set("n", "<leader>v1", function()
      harpoon:list():select(1, { vsplit = true })
    end)
    vim.keymap.set("n", "<leader>2", function()
      harpoon:list():select(2)
    end)
    vim.keymap.set("n", "<leader>v2", function()
      harpoon:list():select(2, { vsplit = true })
    end)
    vim.keymap.set("n", "<leader>3", function()
      harpoon:list():select(3)
    end)
    vim.keymap.set("n", "<leader>v3", function()
      harpoon:list():select(3, { vsplit = true })
    end)
    vim.keymap.set("n", "<leader>4", function()
      harpoon:list():select(4)
    end)
    vim.keymap.set("n", "<leader>v4", function()
      harpoon:list():select(4, { vsplit = true })
    end)
    vim.keymap.set("n", "<leader>5", function()
      harpoon:list():select(5)
    end)
    vim.keymap.set("n", "<leader>v5", function()
      harpoon:list():select(5, { vsplit = true })
    end)
    vim.keymap.set("n", "<leader>6", function()
      harpoon:list():select(6)
    end)
    vim.keymap.set("n", "<leader>v6", function()
      harpoon:list():select(6, { vsplit = true })
    end)
    vim.keymap.set("n", "<C-h>", function()
	if  harpoon:list():get_current_index() == 1 then harpoon:list():select(2)
	elseif  harpoon:list():get_current_index() == 2 then harpoon:list():select(1)
	end
    end)
  end,

}

