module c3pg::lexer_generator;
import std::collections::list;

enum TerminalType
{
    NORMAL,
    DROP,
    ERROR
}

<*
    This represents a terminal declaration in a lexer, this is what eventually gets translated into an enum
*>
struct LexerTerminal
{
    TerminalType type;
    union {
        <* The name of the terminal*>
        String name;
        <* The error message provided for the terminal *>
        String error;
    }
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
