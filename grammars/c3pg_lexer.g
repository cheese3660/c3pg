# This file defines the parser grammar that will make up c3pg lexer definitions
parser
{
    module: c3pg::lexer_grammar::parser
    lexer_module: c3pg::lexer_grammar::lexer
    language: lexer
}


# Define the root node so that it is a lexer_definition, then a list of terminal declarations, then a list of modes
root := lexer_definition terminal+ mode* EOF;

lexer_definition := LEXER_IDENTIFIER BEGIN_INFORMATION lexer_info* END_INFORMATION;

lexer_info := INFORMATION_IDENT{name} INFORMATION_SEPARATOR namespaced_info;

namespaced_info := INFORMATION_IDENT{children} (INFORMATION_NAMESPACE INFORMATION_IDENT{children})*;  # When the {...} is here, the generator should be smart enough to know that there can be multiple

terminal := named_terminal @nowrap
         |  drop_terminal @nowrap
         |  error_terminal @nowrap
         ;

named_terminal := IDENT{name} next_state? DEFINITION pattern;

drop_terminal  := DROP next_state? DEFINITION pattern;

error_terminal := ERROR;


terminal_ident  := IDENT{name}
                |  DROP
                |  ERROR
                ;

next_state      := LPAREN IDENT{name} RPAREN;   # Putting {...} after a terminal will make it available in the union as a token or a list of tokens, it will be null if there is no given node
                                                # Putting it after a non-terminal will make it available in the union as a node or a list of nodes (it goes after the * or + or ?), rather than just a list of that type

pattern         := string @nowrap
                |  regex  @nowrap
                ;

string          := STRING_BEGIN CHARACTER{contents}+ STRING_END;
regex           := REGEX_BEGIN  CHARACTER{contents}+ REGEX_END;

mode            := mode_definition terminal+;

mode_definition := MODE MODE_ERRORS? IDENT MODE_BEGIN;