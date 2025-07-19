" CLIPS log file type detection
autocmd BufRead,BufNewFile *.clips setfiletype clips
autocmd BufRead,BufNewFile *.clips-log setfiletype clips
autocmd BufRead,BufNewFile *.log if getline(1) =~ '\[.*\] \[main\] \[info\] ==>' | setfiletype clips | endif
