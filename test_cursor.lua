-- Test the cursor-based fact ID detection
-- This file tests if the enhanced gd mapping works correctly

local ui = require('clips-analyzer.ui')

-- Test function to verify cursor detection
local function test_cursor_detection()
  print("Testing cursor-based fact ID detection...")
  
  -- Set up a test line in a buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "==> f-123 (test-fact)",
    "Another line with fact f-456 in the middle",
    "Just a number: 789",
    "No facts here"
  })
  
  -- Test each line
  for i = 1, 4 do
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_cursor(0, {i, 0})
    
    -- Position cursor at different places on the line
    local line = vim.api.nvim_buf_get_lines(buf, i-1, i, false)[1]
    print("Line " .. i .. ": " .. line)
    
    -- Test would go here - in real usage, gd would be pressed
  end
  
  vim.api.nvim_buf_delete(buf, {force = true})
  print("Test complete!")
end

return {
  test_cursor_detection = test_cursor_detection
}
