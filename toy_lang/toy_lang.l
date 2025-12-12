#--------------------------------------#
# LLVM Kaleidescope inspired grammar   #
#                                      #
#--------------------------------------#

# Interface declaration block, must start the grammar
# The { and } both need to be on separate lines, and the open brace must immediately follow the grammar type specification
lexer
{
    module: toy_lang::lexer
    language: Kaleidescope
}

# Keywords
FN_DEF      := 'def'
IF          := 'if'
THEN        := 'then'
ELSE        := 'else'
EXERN       := 'extern'
LPAREN      := '('
RPAREN      := ')'
PLUS        := '+'
MINUS       := '-'
MULTIPLY    := '*'
DIVIDE      := '/'
COMMA       := ','

# Tokens can use regular expressions
NUMBER      := /[+-]?\d*\.?\d+/
IDENT       := /[a-zA-Z_][a-zA-Z0-9_]*/ # Token priority is longest match then top to bottom within a mode

@drop(COMMENT) := '#' # Tokens can be named @drop to skip them
                       # Tokens can also have a parentheses after their name to choose the mode to push onto the mode stack
                       # Modes are implemented as a stack to allow for stuff like nested comment parsing

@drop := \s+

mode COMMENT:
@drop(POP) := '\n' # POP pops a mode off the mode stack, and then goes back to that mode 
@drop := /./

# Some other things
#
# You can declare error nodes with
# @error := ...
#
# And you can declare a mode as an error if it's still in that mode at the end of the stream
# 
# declared as such:
# mode !COMMENT:
#
# but still refered to as COMMENT when going to the mode
#
# This can also be useful for like making a string thing