" Vim syntax file for CLIPS logs
" Language: CLIPS Expert System Logs
" Maintainer: Tim Wendt
" Latest Revision: 2025

if exists("b:current_syntax")
  finish
endif

" CLIPS log patterns
syntax match clipsTimestamp '\[\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2}\.\d\{3}\]'
syntax match clipsLogLevel '\[main\] \[info\]'
syntax match clipsLogLevel '\[main\] \[debug\]'
syntax match clipsLogLevel '\[main\] \[warn\]'
syntax match clipsLogLevel '\[main\] \[error\]'

" Fact operations
syntax match clipsAssertion '==>' 
syntax match clipsRetraction '<=='
syntax match clipsFactId 'f-\d\+'

" CLIPS constructs
syntax match clipsTemplate '(\w\+\s' contains=clipsParens
syntax match clipsSlot '\s\w\+\s\+' 
syntax match clipsParens '[()]'

" Comments and strings
syntax region clipsString start='"' end='"' 
syntax match clipsComment ';.*$'

" Numbers
syntax match clipsNumber '\<\d\+\>'
syntax match clipsFloat '\<\d\+\.\d\+\>'

" Highlighting
highlight default link clipsTimestamp Special
highlight default link clipsLogLevel Type
highlight default link clipsAssertion Statement
highlight default link clipsRetraction Statement
highlight default link clipsFactId Identifier
highlight default link clipsTemplate Function
highlight default link clipsSlot Label
highlight default link clipsParens Delimiter
highlight default link clipsString String
highlight default link clipsComment Comment
highlight default link clipsNumber Number
highlight default link clipsFloat Float

let b:current_syntax = "clips"
