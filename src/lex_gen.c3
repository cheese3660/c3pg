<*
    This module contains code for generating a lexer definition
*>
module c3pg::lex_gen;
import std::collections::list;
import regex;

/* Type declarations */

<*
    This represents a terminal declaration in a lexer, this is what eventually gets translated into an enum
*>
struct LexerTerminal
{
    <* The name of the terminal, @drop and @error are special names here *>
    String name;
    <* The name of the mode to push if non-empty*>
    String push_mode;
    <* Is the pattern a regular expression *>
    bool is_pattern_regex;
    <* The pattern to match *>
    String pattern;
}

<*
    This represents a mode in a lexer, it contains all the terminals for the node
*>
struct LexerMode
{
    String mode_name;
    bool is_error_on_eof;
    List { LexerTerminal } terminals;
}

<*
    This represents a full lexer definition
*>
struct LexerDefinition
{
    String lexer_module;
    String language_name;
    List { LexerMode } modes;
}

/* Lexer definition parsing */

/* lexer regexen */

RuntimeRegex mode_declaration_rr;
Regex mode_declaration = &mode_declaration_rr;
RuntimeRegex terminal_declaration_rr;
Regex terminal_declaration = &terminal_declaration_rr;
RuntimeRegex config_declaration_rr;
Regex config_declaration = &config_declaration_rr;

fn void init_regexen() @init
{
    mode_declaration_rr = regex::make_runtime_regex(`^mode\s+(!)?([A-Z][_A-Z0-9]*)\s*:?$`,NONE,mem)!!;
    terminal_declaration_rr = regex::make_runtime_regex(`^(@error|@drop|[A-Z][_A-Z0-9]*)(?:\(([A-Z][_A-Z0-9]*)\))?\s*:=\s*('|\/)(.+)\3$`,MULTILINE,mem)!!;
    config_declaration_rr = regex::make_runtime_regex(`^[a-z]+\s*:\s*([^#]+)?$`, NONE, mem)!!;
}

