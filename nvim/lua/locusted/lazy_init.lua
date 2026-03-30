local function get_python_path()
    if vim.env.CONDA_PREFIX then
        local conda_python = vim.env.CONDA_PREFIX .. "/bin/python"
        if vim.fn.executable(conda_python) == 1 then
            return conda_python
        end
    end
    if vim.env.VIRTUAL_ENV then
        local venv_python = vim.env.VIRTUAL_ENV .. "/bin/python"
        if vim.fn.executable(venv_python) == 1 then
            return venv_python
        end
    end
    return vim.fn.exepath("python3") or "python3"
end

vim.g.python3_host_prog = get_python_path()

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    spec = "locusted.lazy",
    change_detection = { notify = false }
})
