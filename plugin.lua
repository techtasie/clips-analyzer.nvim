return {
  "clips-analyzer.nvim",
  name = "CLIPS Log Analyzer",
  description = "Interactive TUI for analyzing CLIPS log files with fact tracking and timeline visualization",
  author = "Your Name",
  version = "1.0.0",
  
  -- Plugin metadata
  keywords = { "clips", "log", "analyzer", "tui", "expert-system" },
  license = "MIT",
  
  -- Dependencies
  dependencies = {},
  
  -- Neovim version requirement
  requires = ">=0.8.0",
  
  -- Main module
  main = "clips-analyzer",
  
  -- File patterns for auto-detection
  filetypes = { "clips", "clp" },
  patterns = { "*clips*log*", "*clips*.txt", "*.clips", "*.clp" },
  
  -- Commands provided by the plugin
  commands = {
    "ClipsSearch",
    "ClipsFactDetails"
  },
  
  -- Default configuration
  config = {
    mappings = {
      search = '<leader>cs'
    },
    ui = {
      border = 'rounded',
      transparency = 0,
      max_results = 1000
    },
    parser = {
      case_sensitive = false,
      include_fire_events = true
    }
  }
}
