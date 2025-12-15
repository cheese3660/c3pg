# This file defines the tokens that the make up the grammar for the c3pg_lexer, as after the initial implementation, these will be used to implement the generator
lexer
{
    module: c3pg::lexer_grammar::lexer
    language: lexer
}

LEXER_IDENTIFIER                := 'lexer'                  # The lexer of course starts with its identifier
BEGIN_INFORMATION(INFORMATION)  := '{'                      # Then it has the begin information token

@drop(COMMENT)  := '#'   # Comments are allowed here
@drop           := /\s+/ # We want to drop whitespace in the default mode

mode !INFORMATION: 
INFORMATION_IDENT       := /[a-z][a-zA-Z0-9_]*/     # Then it has the information identifier
INFORMATION_SEPARATOR   := ':'                      # Information is separated by a ':'
INFORMATION_NAMESPACE   := '::'                     # Modules use '::' in their namespace, this implements that
END_INFORMATION(BODY)   := '}'                      # Finally we end all information in the body

@drop(COMMENT)  := '#'   # Comments are allowed here
@drop           := /\s+/ # We want to drop whitespace in the default mode

mode BODY:
IDENT                   := /[A-Z][A-Z0-9_]*/        # Identifiers can only be uppercase for terminals
DEFINITION              := ':='                     # Definitions are done with ':='
MODE                    := 'mode'                   # This begins a new mode
MODE_BEGIN              := ':'
MODE_ERRORS             := '!'
DROP                    := '@drop'
ERROR                   := '@error'
LPAREN                  := '('
RPAREN                  := ')'
REGEX_BEGIN(REGEX)      := '/'
STRING_BEGIN(STRING)    := '\''

@drop(COMMENT)  := '#'      # Comments are allowed here
@drop           := /\s+/    # Same as in the default mode, we want to drop whitespace here as well

mode !REGEX:
CHARACTER(ESCAPE)               := '\\'
REGEX_END(POP)                  := '/'
CHARACTER                       := /./  # Multiple definitions can be done for the same terminal

@error(POP) !'Unterminated regex!' := '\n'

mode !STRING:
CHARACTER(ESCAPE)               := '\\' # Even across modes
STRING_END(POP)                 := '\''
CHARACTER                       := /./

@error(POP) !'Unterminated string!' := '\n'

mode !ESCAPE:
CHARACTER(POP)                  := /./

mode COMMENT:
@drop(POP)      := '\n'     # Comments end on a newline 
@drop           := /.+/     # Otherwise drop all characters in them, + is allowed because . will not match on a newline, as single line mode will not be set