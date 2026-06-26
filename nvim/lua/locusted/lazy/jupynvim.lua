return {
	"sheng-tse/jupynvim",
	build = function(plugin)
		local install = loadfile(plugin.dir .. "/lua/jupynvim/install.lua")()
		install.run(plugin)
		--
		--
	end,
	config = function()
		local jup = require("jupynvim")
		jup.setup({
			log_level = "info",
			image_renderer = "placeholder", -- "placeholder", "kitty", or "chafa"
		})

		-- Auto-enable matplotlib inline plots for ALL python kernels.
		--
		-- jupynvim already injects `%matplotlib inline` on kernel start, but only
		-- when it detects a python kernel: the kernel NAME contains "python" OR
		-- notebook_meta.language == "python" (init.lua:2288). Conda-env kernels
		-- with a custom name (e.g. "mmm_v2") and an empty/non-"python" language
		-- string slip through that check, so `df.plot()` / a bare `ax` never
		-- auto-displays a figure — only an explicit `%matplotlib inline` works.
		-- (Restart also never injects: M.restart_kernel bypasses start_kernel.)
		--
		-- Fix: after start/restart, send the same magic ourselves, unconditionally
		-- for python notebooks, retrying until the (re)started kernel accepts it.
		-- The code is try/except-wrapped and idempotent, so the redundant inject
		-- on python-named kernels is harmless.
		local Notebook = require("jupynvim.notebook")
		local INLINE_CODE =
			"try:\n    get_ipython().run_line_magic('matplotlib', 'inline')\nexcept Exception:\n    pass\n"

		local function inject_inline(nb, attempt)
			attempt = attempt or 1
			if attempt > 60 or nb.kernel_error then
				return
			end -- ~30s cap, bail on start failure
			-- Skip genuinely non-python kernels; empty/missing language (the case
			-- that slips jupynvim's check) is treated as python and proceeds.
			local lang = ((nb.notebook_meta and nb.notebook_meta.language) or ""):lower()
			if lang ~= "" and not lang:find("python") then
				return
			end
			local cl = nb.alias and jup.client_for(nb.alias) or jup.client
			if not (cl and cl.call and nb.session_id) then
				vim.defer_fn(function()
					inject_inline(nb, attempt + 1)
				end, 500)
				return
			end
			cl:call("execute_silent", { session_id = nb.session_id, code = INLINE_CODE }, function(err)
				-- err while the kernel is still (re)starting -> retry shortly.
				if err then
					vim.defer_fn(function()
						inject_inline(nb, attempt + 1)
					end, 500)
				end
			end)
		end

		local function wrap(name)
			local orig = jup[name]
			jup[name] = function(buf, ...)
				orig(buf, ...)
				local nb = Notebook.get(buf or vim.api.nvim_get_current_buf())
				if nb then
					vim.defer_fn(function()
						inject_inline(nb)
					end, 300)
				end
			end
		end
		wrap("start_kernel")
		wrap("restart_kernel")

		-- Keep Copilot working inside notebook cells without crashing.
		--
		-- jupynvim's notebook_lsp.on_attach applies a "detach textDocument,
		-- speak notebookDocument/* instead" treatment to any client that
		-- advertises notebookDocumentSync (notebook_lsp.lua:254). It does this
		-- for `ty`, which chokes parsing the rendered .ipynb buffer as JSON.
		--
		-- Copilot's language server ALSO advertises notebookDocumentSync, so
		-- jupynvim wraps it too: it monkey-patches Copilot's client.request and
		-- short-circuits textDocument/* requests to the notebook URI by calling
		-- the handler as `handler(nil, nil, ctx, nil)` (notebook_lsp.lua:168).
		-- Copilot's handler is a non-standard 2-arg closure that builds
		-- `{ id, error = err, result = result }`; with both nil, Lua drops both
		-- keys and Copilot's vimscript OnResponse reads a missing `.error` key
		-- -> E716 "Key not present in Dictionary: error" on every cell edit.
		--
		-- Unlike `ty`, Copilot doesn't need the notebook protocol or choke on
		-- the buffer text — it just reads the buffer to generate suggestions.
		-- So we exclude Copilot from the treatment: it attaches normally and
		-- works, and jupynvim never wraps its request handler.
		local nlsp = require("jupynvim.notebook_lsp")
		local orig_on_attach = nlsp.on_attach
		nlsp.on_attach = function(buf, nb, client)
			if client and type(client.name) == "string" and client.name:lower():find("copilot") then
				return
			end
			return orig_on_attach(buf, nb, client)
		end

		-- Survive agentic / external edits: reload the .ipynb from disk WITHOUT
		-- killing the live kernel.
		--
		-- jupynvim's only reload path is `:e!` -> BufReadCmd re-fires with
		-- force=true -> M.open's force branch calls the core `close` RPC (kills
		-- the kernel) then a fresh `open` (new session_id = brand-new kernel).
		-- So when Claude Code rewrites the notebook on disk and you reload, the
		-- kernel restarts and all in-memory state is lost (same problem we fixed
		-- for ipynb.nvim).
		--
		-- Fix: reconcile in place. Read the new cells from disk and push them to
		-- the EXISTING session via `replace_cells` (the same RPC `:w` uses — it
		-- swaps cell source/type matched by id, PRESERVES outputs for unchanged
		-- ids, and never touches the kernel). Then re-read the session via
		-- `snapshot` and rebuild the buffer with Notebook.create(buf, path, the
		-- SAME session_id, snap). The kernel, keyed by session_id in the core,
		-- lives on. Hooked in two places:
		--   1) wrap M.open so `:e!` reconciles instead of close+open, and
		--   2) FileChangedShell so a clean buffer auto-reloads with no `:e!`
		--      (a dirty buffer is warned about and never clobbered).
		local Render = require("jupynvim.render")

		-- "Unsaved edits" we must not clobber == unsaved CELL SOURCE the user typed
		-- in the editor. NOT a full-buffer hash: jupynvim renders cell outputs as
		-- real buffer lines, so running any cell changes the buffer text without
		-- being a source edit. So we baseline a signature of the cell sources at
		-- the last open/save/reconcile and compare against it.
		local saved_src_sig = {} -- [buf] = source signature at last open/save/reconcile
		local function source_sig(nb)
			pcall(function()
				nb:sync_from_buffer()
			end)
			local parts = {}
			for _, c in ipairs(nb.cells or {}) do
				parts[#parts + 1] = (c.cell_type or "code") .. "\1" .. (c.source or "")
			end
			return vim.fn.sha256(table.concat(parts, "\2"))
		end

		-- Same signature, computed from the .ipynb on disk (cell type + source).
		-- Used to tell "disk content actually changed" from "mtime bumped but
		-- content is identical" (which is what our own :w does).
		local function disk_source_sig(path)
			local ok_read, raw = pcall(vim.fn.readfile, path)
			if not ok_read then
				return nil
			end
			local ok_dec, disk = pcall(vim.json.decode, table.concat(raw, "\n"))
			if not ok_dec or type(disk) ~= "table" or type(disk.cells) ~= "table" then
				return nil
			end
			local parts = {}
			for _, c in ipairs(disk.cells) do
				local src = c.source
				if type(src) == "table" then
					src = table.concat(src, "")
				end
				parts[#parts + 1] = (c.cell_type or "code") .. "\1" .. (type(src) == "string" and src or "")
			end
			return vim.fn.sha256(table.concat(parts, "\2"))
		end

		local function reconcile_from_disk(nb)
			if not (nb and nb.path and nb.session_id) then
				return false
			end
			local cl = nb.alias and jup.client_for(nb.alias) or jup.client
			if not (cl and cl.call_sync) then
				return false
			end

			local ok_read, raw = pcall(vim.fn.readfile, nb.path)
			if not ok_read then
				return false
			end
			local ok_dec, disk = pcall(vim.json.decode, table.concat(raw, "\n"))
			if not ok_dec or type(disk) ~= "table" or type(disk.cells) ~= "table" then
				return false
			end

			local incoming = {}
			for _, c in ipairs(disk.cells) do
				-- nbformat source is a string OR an array of line strings.
				local src = c.source
				if type(src) == "table" then
					src = table.concat(src, "")
				end
				table.insert(incoming, {
					-- Reuse the nbformat cell id so replace_cells matches by id
					-- and keeps each unchanged cell's outputs / execution_count.
					id = type(c.id) == "string" and c.id or "",
					cell_type = c.cell_type or "code",
					source = type(src) == "string" and src or "",
				})
			end

			local rerr = cl:call_sync("replace_cells", { session_id = nb.session_id, cells = incoming }, 5000)
			if rerr then
				return false
			end
			-- The snapshot RPC returns the snapshot object directly (has .cells),
			-- unlike `open` which wraps it as { session_id, snapshot }.
			local serr, snap = cl:call_sync("snapshot", { session_id = nb.session_id }, 5000)
			if serr or type(snap) ~= "table" or type(snap.cells) ~= "table" then
				return false
			end

			-- Rebuild the Lua notebook from the fresh snapshot, REUSING the live
			-- session_id, then re-render. The core never sees a `close`.
			local new_nb = Notebook.create(nb.buf, nb.path, nb.session_id, snap)
			jup._populate_buffer(new_nb)
			if vim.api.nvim_buf_is_valid(new_nb.buf) then
				vim.bo[new_nb.buf].modified = false
				vim.bo[new_nb.buf].autoread = false
				-- Reset the saved-state baseline so the buffer is recognised as
				-- clean (matching disk) by the unsaved-edits check below — and so
				-- jupynvim's own TextChanged tracking compares against it.
				new_nb.saved_hash =
					vim.fn.sha256(table.concat(vim.api.nvim_buf_get_lines(new_nb.buf, 0, -1, false), "\n"))
				Render.refresh(new_nb, vim.fn.bufwinid(new_nb.buf))
				-- Re-scope treesitter to the code-cell regions — otherwise the
				-- rebuilt buffer loses syntax highlighting (M.open does this at
				-- init.lua:1325 after the parser attaches; create/_populate don't).
				pcall(function()
					jup._sync_treesitter_ranges(new_nb)
				end)
				-- Buffer now matches disk: rebaseline the source signature.
				saved_src_sig[new_nb.buf] = source_sig(new_nb)
			end
			return true
		end

		-- Unsaved in-editor SOURCE edits exist iff the current cell-source
		-- signature differs from the baseline captured at the last open/save/
		-- reconcile. (vim.bo.modified is useless here — jupynvim keeps it
		-- perpetually true so `:w` routes through its BufWriteCmd.)
		local function has_unsaved_edits(nb, buf)
			local base = saved_src_sig[buf]
			if not base or not vim.api.nvim_buf_is_valid(buf) then
				return false -- no baseline yet -> treat as clean
			end
			return source_sig(nb) ~= base
		end

		local orig_open = jup.open
		jup.open = function(path, opts)
			opts = opts or {}
			-- Intercept force-reload (`:e!`) of an already-live notebook: keep
			-- the kernel by reconciling instead of close+open. Fall through to
			-- the original (kernel-restarting) path only if reconcile fails.
			if opts.force and type(path) == "string" and not path:match("^%w+://") then
				local b = vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
				if b > 0 then
					local nb = Notebook.get(b)
					if nb and nb.session_id and not nb.kernel_error then
						local ok, did = pcall(reconcile_from_disk, nb)
						if ok and did then
							return b
						end
					end
				end
			end
			return orig_open(path, opts)
		end

		-- autoread off on notebook buffers: with autoread on, Neovim reloads an
		-- unmodified buffer on checktime REGARDLESS of v:fcs_choice, so the
		-- FileChangedShell suppression below would be bypassed and the
		-- kernel-killing reload would run anyway.
		vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, {
			pattern = "*.ipynb",
			group = vim.api.nvim_create_augroup("JupynvimNoAutoread", { clear = true }),
			callback = function(args)
				if Notebook.get(args.buf) then
					vim.bo[args.buf].autoread = false
				end
			end,
		})

		-- Make external-change detection automatic. Neovim only notices a file
		-- changed on disk when something runs `:checktime`; by default nothing
		-- does, so an agent's edit goes unnoticed until you act (then you `:e!`).
		-- Run checktime on focus/idle/enter for notebook buffers so the change
		-- is picked up on its own -> FileChangedShell fires -> kernel-safe
		-- reconcile runs, no `:e!` needed. (CursorHold fires after 'updatetime'
		-- ms of idle and doesn't depend on terminal focus events.)
		local log = require("jupynvim.log")

		-- Detect external edits ourselves via the file mtime.
		--
		-- Neovim's own change detection (checktime -> FileChangedShell) is a
		-- no-op for jupynvim notebooks: they are buftype=acwrite loaded through a
		-- custom BufReadCmd, so Neovim never records the file's mtime baseline and
		-- has nothing to compare. (Confirmed: checktime fires every second but
		-- FileChangedShell never does.) So we poll the mtime in the autocmds we
		-- already have firing (focus / idle / enter) and reconcile when it moves.
		local uv = vim.uv or vim.loop
		local disk_mtime = {} -- [buf] = "sec.nsec" baseline
		local warned = {} -- [buf] = true once we've warned about unsaved edits

		local function mtime_of(path)
			local st = uv.fs_stat(path)
			if not st or not st.mtime then
				return nil
			end
			return st.mtime.sec .. "." .. st.mtime.nsec
		end

		local function maybe_reload_from_disk(buf)
			local nb = Notebook.get(buf)
			if not (nb and nb.path) then
				return
			end
			local mt = mtime_of(nb.path)
			if not mt then
				return
			end
			local prev = disk_mtime[buf]
			if prev == nil then -- first sight: record both baselines
				disk_mtime[buf] = mt
				if saved_src_sig[buf] == nil then
					saved_src_sig[buf] = source_sig(nb)
				end
				return
			end
			if prev == mt then
				return
			end -- unchanged on disk
			disk_mtime[buf] = mt -- consume this change notification

			-- The mtime moved, but did the CONTENT actually change? Our own :w
			-- (jupynvim writes via BufWriteCmd, which doesn't fire BufWritePost on
			-- acwrite) bumps the mtime without changing content. Only reconcile
			-- when the on-disk source genuinely differs from the buffer — this is
			-- what stops every save from triggering a needless reconcile (which
			-- dropped treesitter highlighting).
			local bsig = source_sig(nb)
			local dsig = disk_source_sig(nb.path)
			if dsig == nil then
				return
			end -- couldn't read disk; bail safe
			if dsig == bsig then -- disk matches buffer (our own save)
				saved_src_sig[buf] = bsig
				return
			end

			-- Disk content differs from the buffer. If the buffer ALSO differs
			-- from the last-saved baseline, you have unsaved source edits -> warn,
			-- don't clobber. Otherwise it's a clean external edit -> reconcile.
			local base = saved_src_sig[buf]
			if base and bsig ~= base then
				if not warned[buf] then
					warned[buf] = true
					vim.schedule(function()
						vim.notify(
							(
								"[jupynvim] %s changed on disk but the buffer has unsaved edits — not reloaded.\n"
								.. ":w to keep your version, or :e! to load from disk (the kernel survives now)."
							):format(vim.fn.fnamemodify(nb.path, ":t")),
							vim.log.levels.WARN
						)
					end)
				end
				return
			end
			warned[buf] = nil
			local ok, did = pcall(reconcile_from_disk, nb)
			log.info(("[reload] external change -> reconcile ok=%s result=%s"):format(tostring(ok), tostring(did)))
		end

		vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
			pattern = "*.ipynb",
			group = vim.api.nvim_create_augroup("JupynvimCheckTime", { clear = true }),
			callback = function(args)
				maybe_reload_from_disk(args.buf)
			end,
		})

		-- After OUR own save (BufWriteCmd writes the file -> mtime moves), refresh
		-- the baseline so the next poll doesn't see it as an external change and
		-- pointlessly reconcile.
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*.ipynb",
			group = vim.api.nvim_create_augroup("JupynvimSaveMtime", { clear = true }),
			callback = function(args)
				local nb = Notebook.get(args.buf)
				if nb then
					disk_mtime[args.buf] = mtime_of(vim.api.nvim_buf_get_name(args.buf))
					saved_src_sig[args.buf] = source_sig(nb)
					warned[args.buf] = nil
				end
			end,
		})

		-- Autosave notebook source on handoff: leaving the nvim pane/window
		-- (FocusLost — tmux forwards pane/window switches as focus events, since
		-- `focus-events on` is set) or leaving the buffer (BufLeave). This keeps
		-- the buffer CLEAN whenever an agent edits the file on disk, so the
		-- unsaved-edits guard never blocks the auto-reconcile on return and you
		-- never need `:e!` (which would discard edits and drop the LSP).
		--
		-- Gated on a real source change vs the last-saved baseline: jupynvim keeps
		-- vim.bo.modified perpetually true, so we compare source_sig instead. This
		-- avoids needlessly bumping mtime / churning cell ids on every pane switch
		-- when nothing actually changed. The existing BufWritePost hook then
		-- rebaselines saved_src_sig/disk_mtime so the save isn't seen as external.
		vim.api.nvim_create_autocmd({ "FocusLost", "BufLeave" }, {
			pattern = "*.ipynb",
			group = vim.api.nvim_create_augroup("JupynvimAutosaveOnLeave", { clear = true }),
			callback = function(args)
				local nb = Notebook.get(args.buf)
				if not nb then
					log.info(("[autosave] %s on buf=%d: no notebook, skip"):format(vim.fn.expand("<amatch>"), args.buf))
					return
				end
				local base = saved_src_sig[args.buf]
				local cur = source_sig(nb)
				log.info(
					("[autosave] event on buf=%d base=%s cur=%s match=%s"):format(
						args.buf,
						tostring(base and base:sub(1, 8)),
						tostring(cur and cur:sub(1, 8)),
						tostring(base == cur)
					)
				)
				if base and cur == base then
					return -- nothing real to save
				end
				-- Save via jupynvim's real save function, NOT `:write`. jupynvim's
				-- BufWriteCmd is buffer-local and isn't triggered by `:write` run
				-- from inside nvim_buf_call (an autocmd-window context), so the
				-- write silently no-ops (mtime never moves) and the edit is lost.
				-- M._save (exposed as jup._save) reads nb.buf directly, syncs from
				-- the buffer, and writes through the core via a synchronous save RPC
				-- — the same path a manual :w takes — so it actually persists.
				local ok, err = pcall(jup._save, nb)
				log.info(("[autosave] jup._save ok=%s err=%s"):format(tostring(ok), tostring(err)))
				-- Rebaseline ourselves. jupynvim saves via BufWriteCmd on an
				-- acwrite buffer, for which BufWritePost does NOT reliably fire, so
				-- the saved_src_sig/disk_mtime baselines would otherwise stay stale.
				-- A stale baseline makes the unsaved-edits guard treat this
				-- now-saved content as "dirty" on return, blocking the auto-reconcile
				-- of the agent's change (forcing a manual :e!). The buffer source
				-- equals disk right after the write, so capture both baselines here.
				saved_src_sig[args.buf] = source_sig(nb)
				disk_mtime[args.buf] = mtime_of(nb.path)
				warned[args.buf] = nil
			end,
		})

		vim.api.nvim_create_autocmd("BufWipeout", {
			pattern = "*.ipynb",
			group = vim.api.nvim_create_augroup("JupynvimMtimeCleanup", { clear = true }),
			callback = function(args)
				disk_mtime[args.buf] = nil
				warned[args.buf] = nil
			end,
		})

		vim.api.nvim_create_autocmd("FileChangedShell", {
			pattern = "*.ipynb",
			group = vim.api.nvim_create_augroup("JupynvimKernelSafeReload", { clear = true }),
			callback = function(args)
				log.info(
					("[reload] FileChangedShell fired file=%s buf=%d reason=%s"):format(
						tostring(args.file),
						args.buf or -1,
						tostring(vim.v.fcs_reason)
					)
				)
				if type(args.file) == "string" and args.file:match("^%w+://") then
					return
				end
				local nb = Notebook.get(args.buf)
				if not nb then
					return
				end -- not a live notebook; let Neovim handle

				-- Suppress the built-in (kernel-killing) reload.
				vim.bo[args.buf].autoread = false
				vim.v.fcs_choice = ""

				if has_unsaved_edits(nb, args.buf) then
					log.info("[reload] skipped: buffer has unsaved edits (source mismatch)")
					vim.schedule(function()
						vim.notify(
							(
								"[jupynvim] %s changed on disk but the buffer has unsaved edits — not reloaded.\n"
								.. ":w to keep your version, or :e! to load from disk (the kernel survives now)."
							):format(vim.fn.fnamemodify(args.file, ":t")),
							vim.log.levels.WARN
						)
					end)
					return
				end

				-- Clean buffer: reconcile from disk, keeping the kernel.
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(args.buf) and Notebook.get(args.buf) then
						local ok, did = pcall(reconcile_from_disk, nb)
						log.info(("[reload] reconcile ok=%s result=%s"):format(tostring(ok), tostring(did)))
					end
				end)
			end,
		})
	end,
}
