Minimal 3rd party libraries are used
It's ok to use system libraries are OK, granted they're common and ubiquitous libraries
You can use OS/desktop/compositor-available APIs, but you have to write the glue code yourself
All code is relevant to requirements of the project
Focus on quality, stability and correctness
No source code file should be larger than 1000 lines of code, refactor as needed (use cloc --by-file src to verify)
Modularize your code like a professional software developer
When applicable, our implementation should conform with idiomatic use of the language we use
Write small/short developer/debugging tools/binaries as needed, document them, and leave them for future use.
