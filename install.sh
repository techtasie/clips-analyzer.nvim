#!/bin/bash

# clips-analyzer.nvim Installation Guide
# =====================================

echo "clips-analyzer.nvim - CLIPS Log Analyzer for Neovim"
echo "===================================================="
echo
echo "This plugin provides powerful analysis tools for CLIPS expert system logs."
echo
echo "INSTALLATION:"
echo "============"
echo
echo "1. Using vim-plug (add to your init.vim or init.lua):"
echo "   Plug 'timwendt/clips-analyzer.nvim'"
echo
echo "2. Using packer.nvim:"
echo "   use 'timwendt/clips-analyzer.nvim'"
echo
echo "3. Using lazy.nvim:"
echo "   {"
echo "     'timwendt/clips-analyzer.nvim',"
echo "     config = function()"
echo "       require('clips-analyzer').setup()"
echo "     end"
echo "   }"
echo
echo "QUICK START:"
echo "============"
echo "1. Open a CLIPS log file"
echo "2. Run :ClipsSearch"
echo "3. Try these searches:"
echo "   - template:task"
echo "   - fact:{template:pddl-action-precondition, state:!PRECONDITION-SAT}"
echo "   - :[task,goal,action]"
echo
echo "KEY FEATURES:"
echo "============="
echo "✓ Advanced search syntax with fact history queries"
echo "✓ Multi-fact selection and relationship analysis"
echo "✓ Timeline visualization of fact lifecycles"
echo "✓ Fast parsing of large CLIPS logs"
echo "✓ Syntax highlighting for CLIPS files"
echo
echo "For detailed documentation, see :help clips-analyzer"
echo

# Check if we're in the right directory
if [ -f "README.md" ] && [ -d "lua/clips-analyzer" ]; then
    echo "✓ Plugin structure verified"
    echo
    echo "Directory structure:"
    find . -type f -name "*.lua" -o -name "*.vim" -o -name "*.txt" | grep -E '\.(lua|vim|txt)$' | sort | sed 's/^/  /'
else
    echo "⚠ Run this script from the clips-analyzer.nvim directory"
fi
