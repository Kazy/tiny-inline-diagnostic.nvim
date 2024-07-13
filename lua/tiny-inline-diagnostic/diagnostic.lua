local M = {}
local timers_by_buffer = {}

M.enabled = true

local diagnostic_ns = vim.api.nvim_create_namespace("TinyInlineDiagnostic")
local utils = require("tiny-inline-diagnostic.utils")
local highlights = require("tiny-inline-diagnostic.highlights")
local plugin_handler = require("tiny-inline-diagnostic.plugin")
local chunck_utils = require("tiny-inline-diagnostic.chunck")

--- Function to get diagnostics for the current position in the code.
--- @param diagnostics table - The table of diagnostics to check.
--- @param curline number - The current line number.
--- @param curcol number - The current column number.
--- @return table - A table of diagnostics for the current position.
local function get_current_pos_diags(diagnostics, curline, curcol)
    local current_pos_diags = {}

    for _, diag in ipairs(diagnostics) do
        if diag.lnum == curline and curcol >= diag.col and curcol <= diag.end_col then
            table.insert(current_pos_diags, diag)
        end
    end

    if next(current_pos_diags) == nil then
        if #diagnostics == 0 then
            return current_pos_diags
        end
        table.insert(current_pos_diags, diagnostics[1])
    end

    return current_pos_diags
end

--- @param opts table containing options
--- @param cursorpos table containing cursor position
--- @param index_diag integer representing the diagnostic index
--- @param diag table containing diagnostic data
--- @param buf integer: buffer number.
local function forge_virt_texts_from_diagnostic(opts, cursorpos, index_diag, diag, buf)
    local diag_hi, diag_inv_hi = highlights.get_diagnostic_highlights(diag.severity)
    local curline = cursorpos[1]

    local all_virtual_texts = {}

    local plugin_offset = plugin_handler.handle_plugins(opts)

    local chunks, ret = chunck_utils.get_chunks(opts, diag, plugin_offset, curline, buf)
    local need_to_be_under = ret.need_to_be_under
    local offset = ret.offset
    local offset_win_col = ret.offset_win_col

    local max_chunk_line_length = chunck_utils.get_max_width_from_chunks(chunks)

    for index_chunk = 1, #chunks do
        local message = utils.trim(chunks[index_chunk])

        local to_add = max_chunk_line_length - #message
        message = message .. string.rep(" ", to_add)

        if index_chunk == 1 then
            local chunk_header = chunck_utils.get_header_from_chunk(
                message,
                index_diag,
                #chunks,
                need_to_be_under,
                opts,
                diag_hi,
                diag_inv_hi
            )

            if index_diag == 1 then
                local chunck_arrow = chunck_utils.get_arrow_from_chunk(
                    offset,
                    cursorpos,
                    opts,
                    need_to_be_under
                )

                if type(chunck_arrow[1]) == "table" then
                    table.insert(all_virtual_texts, chunck_arrow)
                else
                    table.insert(chunk_header, 1, chunck_arrow)
                end
            end

            table.insert(all_virtual_texts, chunk_header)
        else
            local chunk_body = chunck_utils.get_body_from_chunk(
                message,
                opts,
                need_to_be_under,
                diag_hi,
                diag_inv_hi,
                index_chunk == #chunks
            )

            table.insert(all_virtual_texts, chunk_body)
        end
    end

    if need_to_be_under then
        table.insert(all_virtual_texts, 1, {
            { " ", "None" },
        })
    end

    return all_virtual_texts, offset_win_col, need_to_be_under
end

local function forge_virt_texts_from_diagnostics(opts, diags, cursor_pos, buf)
    local all_virtual_texts = {}
    local offset_win_col = 0
    local overflow_last_line = false
    local need_to_be_under = false

    for index_diag, diag in ipairs(diags) do
        local virt_texts, diag_offset_win_col, diag_need_to_be_under =
            forge_virt_texts_from_diagnostic(
                opts,
                cursor_pos,
                index_diag,
                diag,
                buf
            )

        if diag_need_to_be_under == true then
            need_to_be_under = true
        end

        -- Remove new line if not needed
        if need_to_be_under and index_diag > 1 then
            table.remove(virt_texts, 1)
        end

        vim.list_extend(all_virtual_texts, virt_texts)
    end
    return all_virtual_texts, offset_win_col, need_to_be_under
end

--- Function to get the diagnostic under the cursor.
--- @param buf number - The buffer number to get the diagnostics for.
--- @return table, number, number - A table of diagnostics for the current position, the current line number, the current col, or nil if there are no diagnostics.
function M.get_diagnostic_under_cursor(buf)
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local curline = cursor_pos[1] - 1
    local curcol = cursor_pos[2]

    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local diagnostics = vim.diagnostic.get(buf, { lnum = curline })

    if #diagnostics == 0 then
        return
    end

    return get_current_pos_diags(diagnostics, curline, curcol), curline, curcol
end

local function apply_diagnostics_virtual_texts(opts, event)
    pcall(vim.api.nvim_buf_clear_namespace, event.buf, diagnostic_ns, 0, -1)

    if not M.enabled then
        return
    end

    plugin_handler.init(opts)

    local diags, curline, curcol = M.get_diagnostic_under_cursor(event.buf)

    local cursorpos = {
        curline,
        curcol,
    }

    if diags == nil or curline == nil then
        return
    end

    local virt_prorioty = opts.options.virt_texts.priority
    local virt_lines, offset, need_to_be_under

    if opts.options.multiple_diag_under_cursor then
        virt_lines, offset, need_to_be_under = forge_virt_texts_from_diagnostics(
            opts,
            diags,
            cursorpos,
            event.buf
        )
    else
        virt_lines, offset, need_to_be_under = forge_virt_texts_from_diagnostic(
            opts,
            cursorpos,
            1,
            diags[1],
            event.buf
        )
    end


    local diag_overflow_last_line = false
    local buf_lines_count = vim.api.nvim_buf_line_count(event.buf)

    local total_lines = #virt_lines
    if total_lines >= buf_lines_count - 1 then
        diag_overflow_last_line = true
    end

    local win_col = vim.fn.virtcol("$")

    if need_to_be_under then
        win_col = 0
    end

    if need_to_be_under then
        vim.api.nvim_buf_set_extmark(event.buf, diagnostic_ns, curline + 1, 0, {
            id = curline + 1000,
            line_hl_group = "CursorLine",
            virt_text_pos = "overlay",
            virt_text_win_col = 0,
            virt_text = virt_lines[2],
            priority = virt_prorioty,
            strict = false,
        })
        table.remove(virt_lines, 2)
        win_col = 0

        if curline < buf_lines_count - 1 then
            curline = curline + 1
        end
    end

    if diag_overflow_last_line then
        local other_virt_lines = {}
        for i, line in ipairs(virt_lines) do
            if i > 1 then
                table.insert(line, 1, { string.rep(" ", win_col + offset), "None" })
                table.insert(other_virt_lines, line)
            end
        end

        vim.api.nvim_buf_set_extmark(event.buf, diagnostic_ns, curline, 0, {
            id = curline + 1,
            line_hl_group = "CursorLine",
            virt_text_pos = "overlay",
            virt_text = virt_lines[1],
            virt_lines = other_virt_lines,
            virt_text_win_col = win_col + offset,
            priority = virt_prorioty,
            strict = false,
        })
    else
        vim.api.nvim_buf_set_extmark(event.buf, diagnostic_ns, curline, 0, {
            id = curline + 1,
            line_hl_group = "CursorLine",
            virt_text_pos = "eol",
            virt_text = virt_lines[1],
            -- virt_text_win_col = win_col + offset,
            priority = virt_prorioty,
            strict = false,
        })

        for i, line in ipairs(virt_lines) do
            if i > 1 then
                vim.api.nvim_buf_set_extmark(event.buf, diagnostic_ns, curline + i - 1, 0, {
                    id = curline + i + 1,
                    virt_text_pos = "overlay",
                    virt_text = line,
                    virt_text_win_col = win_col + offset,
                    priority = virt_prorioty,
                    strict = false,
                })
            end
        end
    end
end


--- Function to set diagnostic autocmds.
--- This function creates an autocmd for the `LspAttach` event.
--- @param opts table - The table of options, which includes the `clear_on_insert` option and the signs to use for the virtual texts.
function M.set_diagnostic_autocmds(opts)
    local autocmd_ns = vim.api.nvim_create_augroup("TinyInlineDiagnosticAutocmds", { clear = true })

    for _, timer in pairs(timers_by_buffer) do
        if timer then
            timer:close()
        end
    end
    timers_by_buffer = {}

    vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
            local throttled_apply_diagnostics_virtual_texts, timer = utils.throttle(
                function()
                    apply_diagnostics_virtual_texts(opts, event)
                end,
                opts.options.throttle
            )

            if not timers_by_buffer[event.buf] then
                timers_by_buffer[event.buf] = timer
            end

            vim.api.nvim_create_autocmd("User", {
                group = autocmd_ns,
                pattern = "TinyDiagnosticEvent",
                callback = function()
                    apply_diagnostics_virtual_texts(opts, event)
                end
            })

            vim.api.nvim_create_autocmd({ "LspDetach" }, {
                group = autocmd_ns,
                buffer = event.buf,
                callback = function()
                    if timers_by_buffer[event.buf] then
                        timers_by_buffer[event.buf]:close()
                        timers_by_buffer[event.buf] = nil
                    end
                end
            })

            vim.api.nvim_create_autocmd("User", {
                group = autocmd_ns,
                pattern = "TinyDiagnosticEventThrottled",
                callback = function()
                    throttled_apply_diagnostics_virtual_texts()
                end
            })

            vim.api.nvim_create_autocmd("InsertEnter", {
                group = autocmd_ns,
                buffer = event.buf,
                callback = function()
                    if vim.api.nvim_buf_is_valid(event.buf) then
                        pcall(vim.api.nvim_buf_clear_namespace, event.buf, diagnostic_ns, 0, -1)
                    end
                end
            })

            vim.api.nvim_create_autocmd("CursorHold", {
                group = autocmd_ns,
                buffer = event.buf,
                callback = function()
                    if vim.api.nvim_buf_is_valid(event.buf) then
                        vim.api.nvim_exec_autocmds("User", { pattern = "TinyDiagnosticEvent" })
                    end
                end,
                desc = "Show diagnostics on cursor hold",
            })

            vim.api.nvim_create_autocmd({ "VimResized" }, {
                group = autocmd_ns,
                buffer = event.buf,
                callback = function()
                    if vim.api.nvim_buf_is_valid(event.buf) then
                        vim.api.nvim_exec_autocmds("User", { pattern = "TinyDiagnosticEvent" })
                    end
                end,
                desc = "Handle window resize event, force diagnostics update to fit new window width.",
            })

            vim.api.nvim_create_autocmd("CursorMoved", {
                group = autocmd_ns,
                buffer = event.buf,
                callback = function()
                    if vim.api.nvim_buf_is_valid(event.buf) then
                        vim.api.nvim_exec_autocmds("User", { pattern = "TinyDiagnosticEventThrottled" })
                    end
                end,
                desc = "Show diagnostics on cursor move, throttled.",
            })
        end,
        desc = "Apply autocmds for diagnostics on cursor move and window resize events.",
    })
end

function M.enable()
    M.enabled = true
    vim.api.nvim_exec_autocmds("User", { pattern = "TinyDiagnosticEvent" })
end

function M.disable()
    M.enabled = false
    vim.api.nvim_exec_autocmds("User", { pattern = "TinyDiagnosticEvent" })
end

function M.toggle()
    M.enabled = not M.enabled
    vim.api.nvim_exec_autocmds("User", { pattern = "TinyDiagnosticEvent" })
end

return M
