lexer
{
    module: c3pg::parser_grammar::lexer
    language: parser
}

PARSER_IDENTIFIER               := 'parser'
BEGIN_INFORMATION(INFORMATION)  := '{'

@drop(COMMENT)  := '#'
@drop           := /\s+/

mode !INFORMATION:
INFORMATION_IDENT       := /[a-z][a-zA-Z0-9_]*/     # Then it has the information identifier
INFORMATION_SEPARATOR   := ':'                      # Information is separated by a ':'
INFORMATION_NAMESPACE   := '::'                     # Modules use '::' in their namespace, this implements that
END_INFORMATION(BODY)   := '}'                      # Finally we end all information in the body

@drop(COMMENT)  := '#'
@drop           := /\s+/

mode BODY:


TERMINAL        := /[A-Z][A-Z0-9_]*/                # Terminals are always uppercase
NONTERMINAL     := /[a-z][a-z0-9_]*/                # Nonterminals are always lowercase
ATTRIBUTE       := /@[a-z_]+/
DEFINE          := ':='
SEMICOLON       := ';'
ALTERNATIVE     := '|'
OPEN_NAME       := '{'
CLOSE_NAME      := '}'
OPEN_GROUP      := '('
CLOSE_GROUP     := ')'
OPTIONAL        := '?'
AT_LEAST_ONE    := '+'
ANY_AMOUNT      := '*'
COMMA           := ','


@drop(COMMENT)  := '#'
@drop           := /\s+/

mode COMMENT:
@drop(POP)      := '\n'     # Comments end on a newline 
@drop           := /.+/     # Otherwise drop all characters in them, + is allowed because . will not match on a newline, as single line mode will not be set