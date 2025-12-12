# This file defines the parser grammar that will make up c3pg parser definitions
parser
{
    module: c3pg::parser_grammar::parser
    lexer_module: c3pg::parser_grammar::lexer
    language: parser
}

root := parser_definition declaration+ EOF;

parser_definition := PARSER_IDENTIFIER BEGIN_INFORMATION parser_info* END_INFORMATION;

parser_info := INFORMATION_IDENT{name} INFORMATION_SEPARATOR namespaced_info;

namespaced_info := INFORMATION_IDENT{root} (INFORMATION_NAMESPACE INFORMATION_IDENT{children})*;

declaration := attribute* NONTERMINAL{name} DEFINE alternative_set SEMICOLON;

attribute := ATTRIBUTE{attribute} attribute_parameter_set?;

attribute_parameter_set := OPEN_GROUP (NONTERMINAL{param} COMMA)* CLOSE_GROUP;

alternative_set := alternative (ALTERNATIVE alternative)*;

alternative := quantified+ attribute*;

quantified := primary (OPTIONAL{opt}|AT_LEAST_ONE{alo}|ANY_AMOUNT{any})?;

primary     := group                    @nowrap # This causes the parser to not wrap the expression in a 'primary' node
            |  terminal_reference       @nowrap # If done on all alternatives, no new node type is created 
            |  nonterminal_reference    @nowrap # It can only be done on alternatives that reference one nonterminal
            ;

group       := OPEN_GROUP sub_alternative_set CLOSE_GROUP;

terminal_reference := TERMINAL{term} name?;

nonterminal_reference := NONTERMINAL{nonterm} name?;

name := OPEN_NAME NONTERMINAL{name} CLOSE_NAME;

sub_alternative_set := sub_alternative (ALTERNATIVE sub_alternative)*;

sub_alternative := quantified+;