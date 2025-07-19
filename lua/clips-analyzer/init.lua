local M = {}

-- Import the UI module
local ui = require('clips-analyzer.ui')

-- Export main functions
M.create_search_window = ui.create_search_window
M.show_fact_details_from_log = ui.show_fact_details_from_log
M.show_fact_details = ui.show_fact_details_from_log  -- Alias for convenience
M.show_fact_timeline = ui.show_fact_timeline

-- Version information
M.version = "1.0.0"

-- Setup function for configuration
function M.setup(opts)
  opts = opts or {}
  
  -- Configuration options can be added here in the future
  -- For now, the plugin works with sensible defaults
end

return M
