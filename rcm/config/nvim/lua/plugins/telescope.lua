return {
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = { 'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
      {
        "nvim-telescope/telescope-frecency.nvim",
        version = "*",
        config = function()
          require("telescope").load_extension "frecency"
        end,
      },
      {
        "debugloop/telescope-undo.nvim",
        config = function()
          require("telescope").load_extension "undo"
        end,
      },
    },
    lazy = true,
    cmd = "Telescope",
    opts = {
      defaults = {
        mappings = {
          i = {
            ["<C-p>"] = require('telescope.actions').cycle_history_prev,
            ["<C-n>"] = require('telescope.actions').cycle_history_next,
            ["<C-k>"] = require('telescope.actions').move_selection_previous,
            ["<C-j>"] = require('telescope.actions').move_selection_next,
          },
        }
      },
      extensions = {
        frecency = {
          auto_validate = false
        }
      }
    }
  },
}
