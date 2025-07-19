" clips-analyzer.nvim - CLIPS Log Analyzer for Neovim
" Maintainer: Tim Wendt
" Version: 1.0.0

if exists('g:loaded_clips_analyzer')
  finish
endif
let g:loaded_clips_analyzer = 1

" Save user's cpoptions
let s:save_cpo = &cpo
set cpo&vim

" Define commands
command! ClipsSearch lua require('clips-analyzer').create_search_window()
command! ClipsDetails lua require('clips-analyzer').show_fact_details_from_log()
command! ClipsAnalyze lua require('clips-analyzer').create_search_window()

" Default key mappings (can be disabled by setting g:clips_analyzer_no_mappings = 1)
if !exists('g:clips_analyzer_no_mappings') || !g:clips_analyzer_no_mappings
  " Map gd to show fact details when on a fact line
  autocmd FileType clips nnoremap <buffer> gd :ClipsDetails<CR>
  
  " Map <leader>cs to open search window
  nnoremap <leader>cs :ClipsSearch<CR>
  
  " Map <leader>ca to open analyzer
  nnoremap <leader>ca :ClipsAnalyze<CR>
endif

" Auto-detect CLIPS log files
autocmd BufRead,BufNewFile *.clips,*.log,*.clips-log setfiletype clips

" Restore user's cpoptions
let &cpo = s:save_cpo
unlet s:save_cpo
