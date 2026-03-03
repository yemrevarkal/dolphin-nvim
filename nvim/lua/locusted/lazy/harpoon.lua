-- List of favorite files/marks per project
return {
	-- https.//github.com/ThePrimeagen/harpoon
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	event = "VeryLazy",
	dependencies = {
		-- https.//github.com/nvim-lua/plenary.nvim
		"nvim-lua/plenary.nvim",
	},
	opts = {
		menu = {
			width = 120,
		},
	},
	config = function()
		local harpoon = require("harpoon")
		harpoon.setup({})

		-- Toggle groups: two independent groups for <C-h> and <C-j>
		local store_path = vim.fn.stdpath("data") .. "/harpoon_toggle_groups.json"
		local cwd = vim.fn.getcwd()
		local group1 = {}
		local group2 = {}

		local function load_groups()
			local f = io.open(store_path, "r")
			if not f then return end
			local ok, data = pcall(vim.json.decode, f:read("*a"))
			f:close()
			if ok and data[cwd] then
				group1 = data[cwd].group1 or {}
				group2 = data[cwd].group2 or {}
			end
		end

		local function save_groups()
			local data = {}
			local f = io.open(store_path, "r")
			if f then
				local ok, existing = pcall(vim.json.decode, f:read("*a"))
				f:close()
				if ok then
					data = existing
				end
			end
			data[cwd] = { group1 = group1, group2 = group2 }
			f = io.open(store_path, "w")
			if f then
				f:write(vim.json.encode(data))
				f:close()
			end
		end

		load_groups()
		local ns1 = vim.api.nvim_create_namespace("harpoon_toggle_1")
		local ns2 = vim.api.nvim_create_namespace("harpoon_toggle_2")

		local function find_in(group, idx)
			for i, v in ipairs(group) do
				if v == idx then
					return i
				end
			end
			return nil
		end

		local function toggle_in(group, idx)
			local pos = find_in(group, idx)
			if pos then
				table.remove(group, pos)
			else
				table.insert(group, idx)
				table.sort(group)
			end
		end

		local function update_marks(buf)
			vim.api.nvim_buf_clear_namespace(buf, ns1, 0, -1)
			vim.api.nvim_buf_clear_namespace(buf, ns2, 0, -1)
			for _, idx in ipairs(group1) do
				pcall(vim.api.nvim_buf_set_extmark, buf, ns1, idx - 1, 0, {
					virt_text = { { " ●", "DiagnosticInfo" } },
					virt_text_pos = "eol",
				})
			end
			for _, idx in ipairs(group2) do
				pcall(vim.api.nvim_buf_set_extmark, buf, ns2, idx - 1, 0, {
					virt_text = { { " ◆", "DiagnosticWarn" } },
					virt_text_pos = "eol",
				})
			end
		end

		local function cycle_group(group)
			if #group == 0 then
				return
			end
			local list = harpoon:list()
			local idx = list:get_current_index()
			local pos = nil
			if idx then
				for i, v in ipairs(group) do
					if v == idx then
						pos = i
						break
					end
				end
			end
			local next_pos = pos and (pos % #group) + 1 or 1
			list:select(group[next_pos])
		end

		vim.keymap.set("n", "<leader>ha", function()
			harpoon:list():append()
		end)
		vim.keymap.set("n", "<leader>hc", function()
			harpoon:list():clear()
			group1 = {}
			group2 = {}
			save_groups()
		end)
		vim.keymap.set("n", "<leader>hh", function()
			harpoon.ui:toggle_quick_menu(harpoon:list())
			vim.schedule(function()
				local buf = vim.api.nvim_get_current_buf()
				update_marks(buf)
				vim.keymap.set("n", "<Tab>", function()
					local line = vim.api.nvim_win_get_cursor(0)[1]
					toggle_in(group1, line)
					update_marks(buf)
					save_groups()
				end, { buffer = buf })
				vim.keymap.set("n", "<S-Tab>", function()
					local line = vim.api.nvim_win_get_cursor(0)[1]
					toggle_in(group2, line)
					update_marks(buf)
					save_groups()
				end, { buffer = buf })
			end)
		end)

		vim.keymap.set("n", "<C-h>", function()
			cycle_group(group1)
		end)
		vim.keymap.set("n", "<C-j>", function()
			cycle_group(group2)
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
		vim.keymap.set("n", "<leader>j", function()
			local list = harpoon:list()
			local len = list:length()
			if len == 0 then
				return
			end
			local idx = list:get_current_index()
			local next_idx = idx and (idx % len) + 1 or 1
			list:select(next_idx)
		end)
		vim.keymap.set("n", "<leader>k", function()
			local list = harpoon:list()
			local len = list:length()
			if len == 0 then
				return
			end
			local idx = list:get_current_index()
			local prev_idx = idx and ((idx - 2) % len) + 1 or len
			list:select(prev_idx)
		end)
	end,
}
