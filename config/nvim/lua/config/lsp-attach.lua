vim.api.nvim_create_augroup('LspFormat', { clear = true })
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local opts = { noremap = true, silent = true }
    local buffer = args.buf

    vim.keymap.set('n', 'gh', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)
    vim.keymap.set("n", "<leader>vd", '<cmd>lua vim.diagnostic.open_float()<cr>', opts)
    vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)
    vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)
    vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)
    vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)
    vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', opts)
    vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)
    vim.keymap.set('n', '<leader>rn', '<cmd>lua vim.lsp.buf.rename()<cr>', opts)
    vim.keymap.set({ 'n', 'v' }, '<leader>ca', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)

    -- Typesript files
    if vim.bo.filetype == 'typescript' or vim.bo.filetype == 'typescriptreact' then
      vim.keymap.set('n', '<leader>rf', '<cmd>lua vim.lsp.buf.formatting()<cr>', opts)
    end

    -- Format the current buffer on save
    vim.api.nvim_create_autocmd('BufWritePre', {
      buffer = args.buf,
      group = 'LspFormat',
      callback = function()
        local conform_fmt = require('conform').list_formatters_to_run(buffer)

        -- Skip lsp format if we have a conform formatter
        if #conform_fmt <= 0 then
          local clients = vim.lsp.get_clients({ bufnr = buffer })
          for _, client in ipairs(clients) do
            if client.supports_method('textDocument/formatting') then
              vim.lsp.buf.format({ bufnr = buffer })
              break -- Stop after first formatting client
            end
          end
        end
      end,
    })
  end,
})
