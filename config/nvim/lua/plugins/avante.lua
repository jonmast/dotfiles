return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false,
    opts = {
      provider = "copilot",
      providers = {
        copilot = {
          model = "gpt-4.1"
        },
      },
      system_prompt = function()
        local hub = require("mcphub").get_hub_instance()
        if not hub then
          return "No active MCP servers"
        end
        return hub:get_active_servers_prompt()
      end,
      -- The custom_tools type supports both a list and a function that returns a list. Using a function here prevents requiring mcphub before it's loaded
      custom_tools = function()
        return {
          require("mcphub.extensions.avante").mcp_tool(),
        }
      end,
    },
    build = "make",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      'Davidyz/VectorCode',
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      {
        -- Make sure to set this up properly if you have lazy=true
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
          file_types = { "markdown", "Avante" },
          code = {
            border = "thin"
          }
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
  {
    "ravitemer/mcphub.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    cmd = "MCPHub",
    build = "npm install -g mcp-hub@latest; asdf reshim",
    config = true,
    lazy = true,
  },
  { "nvim-tree/nvim-web-devicons", lazy = true },
  { "zbirenbaum/copilot.lua",      lazy = true },
}
