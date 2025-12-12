<*
    This module contains code for generating a lexer definition
*>
module c3pg::lex_gen;
import std::collections::list;
import regex;
import std::io;
import std::io::file;
import libc;
import std::collections::map;
import c3pg::string_utils;
import c3pg::codegen;

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
    mode_declaration_rr = regex::make_runtime_regex(`^mode\s+(!)?([A-Z][_A-Z0-9]*)\s*:$`,NONE,mem)!!;
    terminal_declaration_rr = regex::make_runtime_regex(`^(@error|@drop|[A-Z][_A-Z0-9]*)(?:\(([A-Z][_A-Z0-9]*)\))?\s*:=\s*('|\/)(.+)\3$`,MULTILINE,mem)!!;
    config_declaration_rr = regex::make_runtime_regex(`^([a-z]+)\s*:\s*(\S+)$`, NONE, mem)!!;
}

fn String trim_and_process_comments(String line)
{
    if (line.len == 0)
    {
        return line;
    }
    bool in_string;
    bool in_regex;
    bool escaped;
    for (usz i = 0; i < line.len; i++)
    {
        if (escaped)
        {
            escaped = false;
        }
        else if (in_string)
        {
            if (line[i] == '\'') in_string = false;
        }
        else if (in_regex)
        {
            if (line[i] == '/') in_regex = false;
        }
        else if (line[i] == '\'')
        {
            in_string = true;
        }
        else if (line[i] == '/')
        {
            in_regex = true;
        }
        else if (line[i] == '#')
        {
            return line[:i].trim();
        }
    }
    return line.trim();
}

enum LexerState
{
    EXPECTING_LEXER_DEFINITION,
    EXPECTING_DEFINITION_OPEN,
    IN_LEXER_DEFINITION,
    IN_MAIN_BODY
}

fn LexerDefinition parse_lexer(String infile)
{
    LexerDefinition result;
    result.modes.tinit();
    result.modes.push({"DEFAULT", false, {}});
    result.modes[0].terminals.tinit();
    Allocator outer_tmem = tmem;

    String data = (String)file::load_temp(infile)!!;
    Splitter splitter = data.tokenize("\n");

    LexerState state = EXPECTING_LEXER_DEFINITION;
    @pool()
    {
        usz line_number = 1;
        while (try line = splitter.next())
        {
            defer line_number++;
            line = trim_and_process_comments(line);
            if (line.len == 0) continue;
            switch (state)
            {
                case EXPECTING_LEXER_DEFINITION:
                    if (line != "lexer")
                    {
                        io::eprintfn("%s:%s: error: expected 'lexer'", infile, line_number);
                        libc::exit(1);
                    }
                    state = EXPECTING_DEFINITION_OPEN;
                case EXPECTING_DEFINITION_OPEN:
                    if (line != "{")
                    {
                        io::eprintfn("%s:%s: error: expected '{'", infile, line_number);
                        libc::exit(1);
                    }
                    state = IN_LEXER_DEFINITION;
                case IN_LEXER_DEFINITION:
                    if (line == "}")
                    {
                        state = IN_MAIN_BODY;
                    }
                    else if (try match = config_declaration.match_in_view(line, 0, tmem))
                    {
                        switch (match[1].captured)
                        {
                            case "module":
                                result.lexer_module = match[2].captured;
                            case "language":
                                result.language_name = match[2].captured;
                            default:
                                io::eprintfn("%s:%s: error unsupported definition %s", infile, line_number, match[1].captured);
                                libc::exit(1);
                        }
                    }
                    else
                    {
                        io::eprintfn("%s:%s: error: expected '}' or a lexer definition", infile, line_number);
                        libc::exit(1);
                    }
                case IN_MAIN_BODY:
                    if (try match = terminal_declaration.match_in_view(line, 0, tmem))
                    {
                        LexerTerminal terminal = { match[1].captured, match[2].captured, match[3].captured == "/", match[3].captured == "/" ? match[4].captured : match[4].captured.unescape_better(outer_tmem,true)!!};
                        result.modes[^1].terminals.push(terminal);
                    }
                    else if (try match = mode_declaration.match_in_view(line, 0, tmem))
                    {
                        LexerMode mode = { match[2].captured, match[1].valid(), {}};
                        mode.terminals.init(outer_tmem);
                        result.modes.push(mode);
                    }
                    else
                    {
                        io::eprintfn("%s:%s error: expected mode declaration or terminal declaration", infile, line_number);
                        libc::exit(1);
                    }
            }
        }
    };

    return result;
}


/* Lexer implementation */
fn void generate_lexer(String infile, String outfile)
{
    @pool()
    {
        LexerDefinition lexer = parse_lexer(infile);

        String tname = lexer.language_name.to_tname();
        String token_t_tname = string::tformat("%sTokenT", tname);
        String token_tname = string::tformat("%sToken", tname);
        String mode_tname  = string::tformat("%sMode",  tname);
        String lexer_tname = string::tformat("%sLexer", tname);
        String entry_tname = string::tformat("%sModeEntry", tname);

        // This is the inner body of an enum that will be spat out when fully collated
        
        HashMap {String, String} token_declarations;
        token_declarations.set("EOF", "");

        List { String } modes;
    

        // The first parameter is the regex itself, the second the name
        HashMap {String, uint} regexen;
        uint next_regex = 0;
        

        foreach (mode : lexer.modes)
        {
            foreach (terminal : mode.terminals)
            {
                if (terminal.name != "@drop" && terminal.name != "@error")
                {
                    if (terminal.is_pattern_regex)
                    {
                        token_declarations.set(terminal.name, "");
                    }
                    else if (try pattern = token_declarations.get(terminal.name))
                    {
                        if (pattern != terminal.pattern)
                        {
                            token_declarations.set(terminal.name, "");
                        }
                    }
                    else
                    {
                        token_declarations.set(terminal.name, terminal.pattern);
                    }
                }
            }
        }

        Codegen cg = (Codegen){}.init(tmem);
        
        cg.@doc()
        {
            cg.line("[AUTOMATICALLY GENERATED BY C3PG]");
            cg.line("Lexer implementation for: %s", tname);
        };

        cg.line("module %s;", lexer.lexer_module);
        cg.line();
        cg.line("/* STANDARD IMPORTS */");
        cg.line();
        cg.line("import c3pg::runtime;");
        cg.line("import std::collections::list;");
        cg.line("import regex;");
        cg.line();
        cg.line("/* TOKEN TYPES */");
        cg.@enum("%s : (String pattern)", token_t_tname)
        {
            token_declarations.@each(; String name, String pattern)
            {
                cg.line("%s = %s,", name, pattern.tescape());
            };
        };
        cg.line();
        cg.line("/* LEXER MODES */");
        cg.line();
        cg.@enum("%s : (bool errors_on_eof)", mode_tname)
        {
            foreach (mode : lexer.modes)
            {
                cg.line("%s = %s,", mode.mode_name, mode.is_error_on_eof);
            }
        };
        cg.line();
        cg.line("/* TOKEN TYPE */");
        cg.line();
        cg.@struct("%s", token_tname)
        {
            cg.line("%s type;", token_t_tname);
            cg.line("Span span;");
            cg.line("String view;");
        };
        cg.line();
        cg.line("/* MODE STACK ENTRY */");
        cg.line();
        cg.@struct("%s", entry_tname)
        {
            cg.line("%s mode;", mode_tname);
            cg.line("Span entered_at;");
        };
        cg.line();
        cg.line("/* LEXER CONTEXT */");
        cg.line();
        cg.@struct("%s", lexer_tname)
        {
            cg.line("String file_data;");
            cg.line("usz current_offset;");
            cg.line("String file;");
            cg.line("List { %s } mode_stack;", entry_tname);
            cg.line("%s current;", token_tname);
            cg.line("C3PgLogger logger;");
        };
        cg.line();
        cg.line("/* LEXER FUNCTIONS */");
        cg.line();
        cg.@fn("%s create_%s_lexer(String data, Allocator allocator, String file = `<input>`, C3PgLogger logger = null)", lexer_tname, lexer.language_name)
        {
            cg.line("%s result = {data, 0, file, {}, {}, logger};",lexer_tname);
            cg.line("result.mode_stack.init(allocator);");
            cg.line("result.enter_mode(DEFAULT, {0,1});");
            cg.line("return result;");
        };
        cg.line();
        cg.@fn("void %s.free(&self) @inline", lexer_tname)
        {
            cg.line("self.mode_stack.free();");
        };
        cg.line();
        cg.@fn("void %s.enter_mode(&self, %s mode, Span s) @inline", lexer_tname, mode_tname)
        {
            cg.line("self.mode_stack.push({mode, s});");
        };
        cg.line();
        cg.@fn("void %s.log_at(&self, Span s, String message) @inline @private", lexer_tname)
        {
            cg.line("if (self.logger != null) self.logger.log_error(s,message,self.file,self.file_data);");  
        };
        cg.line();
        cg.@fn("void %s.log_here(&self, String message) @inline @private", lexer_tname)
        {
            cg.line("self.log_at({self.current_offset, 1}, message);");
        };
        cg.line();
        cg.@fn("void? %s.advance(&self)", lexer_tname)
        {
            cg.@pool()
            {
                cg.@while("self.current_offset < self.file_data.len")
                {
                    cg.@if("catch f = self.single_advance()")
                    {
                        cg.@if("f == runtime::SINGLE_STEP_DROPPED")
                        {
                            cg.line("continue;");
                        };
                        cg.line("return f?;");
                    };
                    cg.line("return;");
                };
                cg.line("self.current = {EOF, {self.current_offset, 0}, ``};");
                cg.@if("self.mode_stack[^1].mode.errors_on_eof")
                {
                    cg.line("self.log_at(self.mode_stack[^1].entered_at, string::tformat(`entered error mode '%%s' starting from here`,self.mode_stack[^1].mode));");
                    cg.line("self.log_here(`and ended at EOF here.`);");
                    cg.line("return runtime::ENDED_IN_ERROR_MODE?;");
                };
            };
        };
        cg.line();
        cg.@fn("void? %s.single_advance(&self) @private", lexer_tname)
        {
            cg.@switch("self.mode_stack[^1].mode")
            {
                foreach (mode : lexer.modes)
                {
                    cg.@case("%s", mode.mode_name)
                    {
                        cg.line("return self.advance_%s();", mode.mode_name.to_lower_tcopy());
                    };
                }
            };
        };
        cg.line();
        foreach (mode : lexer.modes)
        {
            cg.@fn("void? %s.advance_%s(&self)", lexer_tname, mode.mode_name.to_lower_tcopy())
            {
                bool needs_is_error;
                bool all_is_error=true;
                bool needs_is_drop;
                bool all_is_drop=true;
                bool needs_is_pop;
                bool all_is_pop=true;
                bool needs_switches_modes;
                bool all_is_switches=true;
                bool needs_type;
                foreach (terminal : mode.terminals)
                {
                    if (terminal.name == "@error")
                    {
                        needs_is_error = true;
                    }
                    else
                    {
                        all_is_error = false;
                    }

                    if (terminal.name == "@drop")
                    {
                        needs_is_drop = true;
                    }
                    else
                    {
                        all_is_drop = false;
                    }

                    if (terminal.name != "@error" && terminal.name != "@drop") needs_type = true;

                    if (terminal.push_mode == "POP")
                    {
                        needs_is_pop = true;
                        all_is_switches = false;
                    }
                    else if (terminal.push_mode.len > 0)
                    {
                        needs_switches_modes = true;
                        all_is_pop = false;
                    }
                    else
                    {
                        all_is_pop = false;
                        all_is_switches = false;
                    }
                }

                cg.line("usz offset = self.current_offset;");
                cg.line("String rest = self.file_data[offset..];");
                cg.line("usz length;");
                if (needs_type) cg.line("%s type;", token_t_tname);
                if (needs_is_error && !all_is_error) cg.line("bool is_error;");
                if (needs_is_drop && !all_is_drop) cg.line("bool is_drop;");
                if (needs_is_pop && !all_is_pop) cg.line("bool is_pop;");
                if (needs_switches_modes && !all_is_switches) cg.line("bool switches_modes;");
                if (needs_switches_modes) cg.line("%s next_mode;", mode_tname);
                cg.line();
                foreach (terminal : mode.terminals)
                {
                    if (terminal.is_pattern_regex)
                    {
                        if (try regex = regexen.get(terminal.pattern))
                        {
                            cg.line("if (try match = regex%d.match_in_view(rest, 0, tmem) && match.end_offset() > length) // /%s/", regex, terminal.pattern);
                        }
                        else
                        {
                            cg.line("if (try match = regex%d.match_in_view(rest, 0, tmem) && match.end_offset() > length) // /%s/", next_regex, terminal.pattern);
                            regexen.set(terminal.pattern, next_regex++);
                        }
                    }
                    else
                    {
                        cg.line("if (%s > length && rest.starts_with(%s))", terminal.pattern.len, terminal.pattern.tescape());
                    }
                    cg.@block()
                    {
                        if (terminal.is_pattern_regex)
                        {
                            cg.line("length = match.end_offset();");
                        }
                        else
                        {
                            cg.line("length = %s;", terminal.pattern.len);
                        }

                        if (needs_is_pop && !all_is_pop)
                        {
                            if (terminal.push_mode == "POP")
                            {
                                cg.line("is_pop = true;");
                            }
                            else
                            {
                                cg.line("is_pop = false;");
                            }
                        }

                        if (needs_switches_modes && !all_is_switches)
                        {
                            if (terminal.push_mode.len > 0 && terminal.push_mode != "POP")
                            {
                                cg.line("switches_modes = true;");
                                cg.line("next_mode = %s;", terminal.push_mode);
                            }
                            else if (terminal.push_mode);
                            {
                                cg.line("switches_modes = false;");   
                            }
                        }

                        if (all_is_error) continue;
                        if (needs_is_error)
                        {
                            if (terminal.name == "@error")
                            {
                                cg.line("is_error = true;");
                                continue;
                            }
                            cg.line("is_error = false;");
                        }

                        if (terminal.name == "@drop")
                        {
                            if (!all_is_drop) cg.line("is_drop = true;");
                            continue;
                        }
                        cg.line("type = %s;",terminal.name);
                    };
                    cg.line();
                }
                cg.line("self.current_offset += length;");
                cg.@if("length == 0")
                {
                    cg.line("self.log_here(string::tformat(`Unexpected character '%%s'!`, rest[0..1].tescape(true)));");
                    cg.line("self.current_offset += 1;");
                    cg.line("return runtime::UNEXPECTED_CHARACTER?;");
                };
                cg.line();
                if (needs_is_pop)
                {
                    if (all_is_pop)
                    {
                        cg.line("self.mode_stack.pop()!!;");
                        cg.@if("self.mode_stack.len() == 0")
                        {
                            cg.line("self.log_at({offset, length}, `token caused mode stack to become empty`);");
                            cg.line("return runtime::MODE_STACK_CLEARED?;");
                        };
                    }
                    else
                    {
                        cg.@if("is_pop")
                        {
                            cg.line("self.mode_stack.pop()!!;");
                            cg.@if("self.mode_stack.len() == 0")
                            {
                                cg.line("self.log_at({offset, length}, `token caused mode stack to become empty`);");
                                cg.line("return runtime::MODE_STACK_CLEARED?;");
                            };
                        };
                    }
                }
                if (needs_switches_modes)
                {
                    if (all_is_switches)
                    {
                        cg.line("self.enter_mode(next_mode, {offset, length});");
                    }
                    else
                    {
                        cg.@if("switches_modes")
                        {
                            cg.line("self.enter_mode(next_mode, {offset, length});");
                        };
                    }
                }
                if (needs_is_error)
                {
                    if (all_is_error)
                    {
                        cg.line("self.log_at({offset, length},`error terminal lexed`);");
                        cg.line("return runtime::ERROR_TOKEN?;");
                        continue;
                    }
                    else
                    {
                        cg.@if("is_error")
                        {
                            cg.line("self.log_at({offset, length},`error terminal lexed`);");
                            cg.line("return runtime::ERROR_TOKEN?;");
                        };
                        if (needs_type || (needs_is_drop && !all_is_drop) || (needs_switches_modes && !all_is_switches) || (needs_is_pop && !all_is_pop)) cg.line();
                    }
                }
                if (needs_is_drop)
                {
                    if (all_is_drop)
                    {
                        cg.line("return runtime::SINGLE_STEP_DROPPED?;");
                        continue;
                    }
                    else
                    {
                        cg.@if("is_drop")
                        {
                            cg.line("return runtime::SINGLE_STEP_DROPPED?;");
                        };
                    }
                }
                if (needs_type)
                {
                    cg.line("self.current = {type, {offset,length}, rest[:length]};");
                }
            };
            cg.line();
        }
        cg.line("/* REGEXEN */");
        cg.line();
        regexen.@each(; String pattern, usz variable)
        {
            cg.line("RuntimeRegex regex%s; // /%s/", variable, pattern);
        };
        cg.line();
        cg.line("/* INITIALIZATION OF REGEXEN */");
        cg.line();
        cg.@fn("void init_regexen() @private @init")
        {
            regexen.@each(; String pattern, usz variable)
            {
                cg.line("regex%s = regex::make_runtime_regex(`%s`,NONE,mem)!!;", variable, pattern);
            };
        };

        File f = file::open(outfile,"w")!!;
        f.write((char[])cg.build())!!;
        f.flush()!!;
        f.close()!!;
    };
}