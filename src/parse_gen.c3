<*
    This module contains code for the parser generation side of things
*>
module c3pg::parse_gen;
import c3pg::parser_grammar::lexer;
import c3pg::runtime;
import std::io;
import std::io::file;
import std::collections::list;
import std::collections::set;
import std::collections::map;
import c3pg::codegen;
import c3pg::string_utils;
import libc;

alias StringSet = HashSet { String };

struct SubAlternative
{
    List { Quantified } children;
}

enum PrimaryType
{
    GROUP,
    TERMINAL,
    NONTERMINAL
}

struct Primary
{
    PrimaryType type;
    String field;
    union
    {
        String reference;
        List { SubAlternative } group;
    }
    bool is_many; // This is used later on when generating token names, but is useful
}

fn void Primary.set_multiple(&self)
{
    self.is_many = true;
    if (self.type == GROUP)
    {
        foreach (subalt : self.group)
        {
            foreach (child : subalt.children)
            {
                child.primary.set_multiple();
            }
        }
    }
}

enum Quantification
{
    NONE,
    OPTIONAL,
    AT_LEAST_ONE,
    ANY_AMOUNT
}

struct Quantified
{
    Primary primary;
    Quantification quantification;
}

struct Attribute
{
    String attribute;
    List { String } parameters;
}

struct AlternativeDefinition
{
    List { Quantified } children;
    List { Attribute } attributes;
}

struct NonterminalDefinition
{
    String name;
    List { Attribute } attributes;
    List { AlternativeDefinition } alternatives;
}

struct ParserDefinition
{
    String module_path;
    String lexer_module;
    String language;
    HashMap { String, NonterminalDefinition } nonterminals;
}

fn void ParserLexer.error_here(&self, String message) @noreturn
{
    if (self.logger != null) self.logger.log_error(self.current.span, message, self.file, self.file_data);
    libc::exit(-1);
}

fn void ParserLexer.error_here_unexpected(&self, String expected) @noreturn
{
    self.error_here(string::tformat("Unexpected token '%s', expected: %s;",runtime::get_terminal_name(self.current.type), expected));
}

fn void ParserLexer.expect(&self, ParserTokenT expected, bool consume=false)
{
    if (self.current.type != expected) self.error_here_unexpected(string::tformat("'%s'", runtime::get_terminal_name(expected)));
    if (consume) self.advance()!!;
}

fn void ParserLexer.unexpect(&self, ParserTokenT unexpected)
{
    if (self.current.type == unexpected) self.error_here(string::tformat("Unexpected token '%s'", runtime::get_terminal_name(unexpected)));
}

fn Attribute parse_attribute(ParserLexer* lexer)
{
    Attribute attribute;
    String attr_name = lexer.current.view;
    lexer.expect(ATTRIBUTE, consume: true);
    attribute.attribute = attr_name[1..];

    if (lexer.current.type == OPEN_GROUP)
    {
        do
        {
            lexer.advance()!!;
            attribute.parameters.push(lexer.current.view);
            lexer.expect(NONTERMINAL, consume: true);
        } while (lexer.current.type == COMMA);
        lexer.expect(CLOSE_GROUP, consume: true);
    }

    return attribute;
}

fn Primary parse_terminal(ParserLexer* lexer)
{
    String name = lexer.current.view;
    String field;
    lexer.expect(TERMINAL, consume: true);
    if (lexer.current.type == OPEN_NAME)
    {
        lexer.advance()!!;
        field = lexer.current.view;
        lexer.expect(NONTERMINAL, consume: true);
        lexer.expect(CLOSE_NAME, consume: true);
    }

    return {.type = TERMINAL, .field = field, .reference = name};
}

fn Primary parse_nonterminal(ParserLexer* lexer)
{
    String name = lexer.current.view;
    String field;
    lexer.expect(NONTERMINAL, consume: true);
    if (lexer.current.type == OPEN_NAME)
    {
        lexer.advance()!!;
        field = lexer.current.view;
        lexer.expect(NONTERMINAL, consume: true);
        lexer.expect(CLOSE_NAME, consume: true);
    }

    return {.type = NONTERMINAL, .field = field, .reference = name};
}

fn SubAlternative parse_sub_alternative(ParserLexer* lexer)
{
    SubAlternative result;
    do
    {
        result.children.push(parse_quantified(lexer));
    } while (lexer.current.type != CLOSE_GROUP && lexer.current.type != ALTERNATIVE);
    return result;
}

fn Primary parse_group(ParserLexer* lexer)
{
    lexer.expect(OPEN_GROUP, consume: true);
    List { SubAlternative } alternatives;
    lexer.unexpect(ALTERNATIVE);
    do
    {
        if (lexer.current.type == ALTERNATIVE) lexer.advance()!!;
        alternatives.push(parse_sub_alternative(lexer));
    } while (lexer.current.type == ALTERNATIVE);
    lexer.expect(CLOSE_GROUP, consume: true);
    return {.type = GROUP, .group = alternatives};
}

fn Primary parse_primary(ParserLexer* lexer)
{
    switch (lexer.current.type)
    {
        case TERMINAL:
            return parse_terminal(lexer);
        case NONTERMINAL:
            return parse_nonterminal(lexer);
        case OPEN_GROUP:
            return parse_group(lexer);
        default:
            lexer.error_here_unexpected("a terminal name, a nonterminal name, or '('");
    }
}

fn Quantified parse_quantified(ParserLexer* lexer)
{
    Primary primary = parse_primary(lexer);
    Quantification quantification = NONE;
    if (lexer.current.type == OPTIONAL) quantification = OPTIONAL;
    if (lexer.current.type == AT_LEAST_ONE) quantification = AT_LEAST_ONE;
    if (lexer.current.type == ANY_AMOUNT) quantification = ANY_AMOUNT;
    if (quantification != NONE) 
    {
        lexer.advance()!!;
        primary.set_multiple();
    }
    return {primary, quantification};
}

fn AlternativeDefinition parse_alternative(ParserLexer* lexer)
{
    AlternativeDefinition result;
    do
    {
        result.children.push(parse_quantified(lexer));
    } while (lexer.current.type != ATTRIBUTE && lexer.current.type != SEMICOLON && lexer.current.type != ALTERNATIVE);

    while (lexer.current.type == ATTRIBUTE)
    {
        result.attributes.push(parse_attribute(lexer));
    }
    return result;
}

fn NonterminalDefinition parse_declaration(ParserLexer* lexer)
{
    NonterminalDefinition result;
    while (lexer.current.type == ATTRIBUTE)
    {
        result.attributes.push(parse_attribute(lexer));
    }
    result.name = lexer.current.view;
    lexer.expect(NONTERMINAL, consume: true);
    lexer.expect(DEFINE, consume: true);
    lexer.unexpect(ALTERNATIVE);
    do
    {
        if (lexer.current.type == ALTERNATIVE) lexer.advance()!!;
        result.alternatives.push(parse_alternative(lexer));
    } while (lexer.current.type == ALTERNATIVE);
    lexer.expect(SEMICOLON, consume: true);
    return result;
}

fn void parse_root(ParserLexer* lexer, ParserDefinition* result)
{
    /* Let's first expect the identifier, and the information beginning*/
    lexer.expect(PARSER_IDENTIFIER, consume: true);
    lexer.expect(BEGIN_INFORMATION, consume: true);

    /* Let's do header parsing first */
    while (lexer.current.type != END_INFORMATION)
    {
        lexer.expect(INFORMATION_IDENT);
        String ident = lexer.current.view;
        bool is_namespaced;
        switch (ident)
        {
            case "module":
                is_namespaced = true;
            case "lexer_module":
                is_namespaced = true;
            case "language":
                is_namespaced = false;
            default:
                lexer.error_here(string::tformat("Unknown information ident: '%s'", ident));
        }
        lexer.advance()!!;
        lexer.expect(INFORMATION_SEPARATOR, consume: true);
        DString combined;
        while (true)
        {
            combined.append_chars(lexer.current.view);
            lexer.expect(INFORMATION_IDENT, consume: true);
            if (lexer.current.type != INFORMATION_NAMESPACE) break;
            if (!is_namespaced) lexer.error_here(string::tformat("Did not expect a namespaced path for '%s'", ident));
            combined.append_chars("::");
            lexer.advance()!!;
        }
        String value = combined.tcopy_str();
        switch (ident)
        {
            case "module":
                result.module_path = value;
            case "lexer_module":
                result.lexer_module = value;
            case "language":
                result.language = value;
        }
    }
    lexer.advance()!!;
    do
    {
        NonterminalDefinition nonterm = parse_declaration(lexer);
        // result.nonterminals.push();
        if (!result.nonterminals.has_key(nonterm.name))
        {
            result.nonterminals.set(nonterm.name, nonterm);
        }
        else
        {
            lexer.error_here(string::tformat("Nonterminal %s was already defined!", nonterm.name));
        }
    } while(lexer.current.type != EOF);
}

fn ParserDefinition parse_parser_definition(String infile)
{
    String data = (String)file::load_temp(infile)!!;

    ParserLexer lexer = lexer::create_parser_lexer(data,tmem,infile,runtime::std_err);
    lexer.advance()!!; // Prime the lexer
    ParserDefinition result;
    parse_root(&lexer, &result);
    return result;
}




struct NonterminalUnionMember
{
    String tname;
    String fname;
    /* This defines the structure and free method for a type */
    Codegen struct_and_free;
}

struct VisitorMethod
{
    String fname;
    String ctx_tname;
    String ename;
}

/* This is what gets finally used in the parser context */
struct ParserContext
{
    ParserDefinition *definition;
    String parser_tname;
    String node_type_tname;
    String node_tname;
    String token_tname;
    String child_tname;
    List { NonterminalUnionMember } nonterminal_union_members;
    List { String } nonterminal_enum_names;
    List { Codegen } parse_methods; // These are the methods used by the parser
    List { VisitorMethod } visitor_methods;
    HashMap { String, StringSet} already_known_starting_terminals;
}


fn void Primary.collate(&self, HashMap { String, bool} *nts, HashMap { String, bool} *named_nts, HashMap { String, bool } * named_tokens)
{
    if (self.type == NONTERMINAL)
    {
        if (nts.has_key(self.reference))
        {
            nts.set(self.reference, true);
        }
        else
        {
            nts.set(self.reference, self.is_many);
        }

        if (self.field.len)
        {
            if (named_nts.has_key(self.field))
            {
                named_nts.set(self.field, true);
            }
            else
            {
                named_nts.set(self.field, self.is_many);
            }
        }
    }
    else if (self.type == TERMINAL)
    {
        if (self.field.len)
        {
            if (named_tokens.has_key(self.field))
            {
                named_tokens.set(self.field, true);
            }
            else
            {
                named_tokens.set(self.field, self.is_many);
            }
        }
    }
    else
    {
        foreach (child : self.group)
        {
            foreach (grandchild : child.children)
            {
                grandchild.primary.collate(nts, named_nts, named_tokens);
            }
        }
    }
}

fn void ParserContext.get_terminals(&self, SubAlternative* def, List {String}* visiting_stack, StringSet* target)
{
    bool had_any;
    foreach (child : def.children)
    {
        switch (child.primary.type)
        {
            case TERMINAL:
                target.add(child.primary.reference);
            case NONTERMINAL:
                self.get_starting_terminals(child.primary.reference, visiting_stack, target);
            case GROUP:
                foreach (&ch : child.primary.group)
                {
                    self.get_terminals(ch, visiting_stack, target);
                }
        }
        if (child.quantification == NONE || child.quantification == AT_LEAST_ONE)
        {
            had_any = true;
            break;
        }
    }

    if (!had_any)
    {
        io::eprintfn("Warning: subalternative group has alternative that can match nothing (in %s)", (*visiting_stack)[^1]);
        libc::exit(-1);
    }
}

fn StringSet ParserContext.analyze_subalt_top_level(&self, SubAlternative* def)
{
    StringSet result;
    List { String } visiting_stack;
    visiting_stack.push("<production>");
    self.get_terminals(def, &visiting_stack, &result);
    return result;
}

fn void ParserContext.get_starting_terminals_alt(&self, AlternativeDefinition* def, List {String}* visiting_stack, StringSet* target)
{
    bool had_any;
    foreach (child : def.children)
    {
        switch (child.primary.type)
        {
            case TERMINAL:
                target.add(child.primary.reference);
            case NONTERMINAL:
                self.get_starting_terminals(child.primary.reference, visiting_stack, target);
            case GROUP:
                foreach (&ch : child.primary.group)
                {
                    self.get_terminals(ch, visiting_stack, target);
                }
        }
        if (child.quantification == NONE || child.quantification == AT_LEAST_ONE)
        {
            had_any = true;
            break;
        }
    }

    if (!had_any) {
        io::eprintfn("Warning: production has alternative that can match nothing: %s", (*visiting_stack)[^1]);
        libc::exit(-1);
    }
}

fn void ParserContext.get_starting_terminals(&self, String nonterminal_definition, List {String}* visiting_stack, StringSet* target)
{
    foreach (visited : visiting_stack)
    {
        if (nonterminal_definition == visited)
        {
            io::eprintfn("Error: left recursive production: %s", visited);
            libc::exit(-1);
        }
    }
    visiting_stack.push(nonterminal_definition);
    defer visiting_stack.pop()!!;
    if (try known = self.already_known_starting_terminals.get(nonterminal_definition))
    {
        target.add_all_from(&known);
        return;
    }
    StringSet result;
    NonterminalDefinition? def = self.definition.nonterminals.get(nonterminal_definition);
    if (catch def)
    {
        io::eprintfn("Nonterminal %s does not exist, referenced in production: %s", nonterminal_definition, (*visiting_stack)[^2]);
        libc::exit(-1);
        return;
    }
    foreach (&alternative : def.alternatives)
    {
        self.get_starting_terminals_alt(alternative, visiting_stack, &result);
    }
    self.already_known_starting_terminals.set(nonterminal_definition, result);
    target.add_all_from(&result);
}

fn StringSet ParserContext.analyze_alt_top_level(&self, AlternativeDefinition* def, String start)
{
    StringSet result;
    List { String } visiting_stack;
    visiting_stack.push(start);
    self.get_starting_terminals_alt(def, &visiting_stack, &result);
    return result;
}

fn void ParserContext.generate_passthrough_information(&self, Codegen* cg, AlternativeDefinition* alt)
{
    if (alt.children[^1].primary.type != NONTERMINAL)
    {
        cg.line("%s* result;", self.node_tname);
    }
    bool had_nt = false;
    foreach (quant : alt.children)
    {
        if (quant.primary.field.len)
        {
            io::eprintfn("Primaries in a @nowrap cannot have names!");
            libc::exit(-1);
        }

        if (quant.primary.type == GROUP)
        {
            io::eprintfn("Cannot @nowrap alternatives with groups in them!");
            libc::exit(-1);
        }

        if (quant.primary.type == TERMINAL)
        {
            switch (quant.quantification)
            {
                case NONE:
                    cg.line("self.expect({}, %sT.%s)!;", self.token_tname, quant.primary.reference);
                case OPTIONAL:
                    cg.@if("self.peek_is(%sT.%s)", self.token_tname, quant.primary.reference)
                    {
                        cg.line("self.next({})!");
                    };
                case AT_LEAST_ONE:
                    cg.@do_while("self.peek_is(%sT.%s)", self.token_tname, quant.primary.reference)
                    {
                        cg.line("self.expect({}, %sT.%s)!;", self.token_tname, quant.primary.reference);
                    };
                case ANY_AMOUNT:
                    cg.@while("self.peek_is(%sT.%s)", self.token_tname, quant.primary.reference)
                    {
                        cg.line("self.next({})!");
                    };
            }
        }
        else if (quant.primary.type == NONTERMINAL)
        {
            if (had_nt)
            {
                io::eprintf("Cannot have multiple nonterminals in a @nowrap!");
                libc::exit(-1);
            }
            had_nt = true;
            if (quant.quantification != NONE)
            {
                io::eprintfn("The nonterminal in a @nowrap cannot be quantified!");
                libc::exit(-1);
            }
            if (alt.children[^1].primary.type != NONTERMINAL)
            {
                cg.line("result = self.parse_%s();", quant.primary.reference);
            }
            else
            {
                cg.line("return self.parse_%s();", quant.primary.reference);
            }
        }
    }
    if (!had_nt)
    {
        io::eprintfn("Cannot have no nonterminals in a @nowrap!");
        libc::exit(-1);
    }
    if (alt.children[^1].primary.type != NONTERMINAL)
    {
        cg.line("return result;");
    }
}

fn void ParserContext.generate_primary_information(&self, Codegen* cg, Primary* primary, HashMap { String, bool } *collated_nts, HashMap { String, bool } *collated_named_nts, HashMap { String, bool } *collated_named_tokens)
{
    switch (primary.type)
    {
        case GROUP:
            // At least with this one there is no fields needing to be dealt with
            if (primary.group.len() == 1)
            {
                foreach (&quant : primary.group[0].children)
                {
                    self.generate_quantified_information(cg, quant, collated_nts, collated_named_nts, collated_named_tokens);
                }
            }
            else
            {

                StringSet check;
                usz total_len;
                foreach (i, &alt : primary.group)
                {
                    StringSet to_push = self.analyze_subalt_top_level(alt);
                    check.add_all_from(&to_push);
                    total_len += to_push.len();
                    if (check.len() != total_len)
                    {
                        io::eprintfn("Error: alternative %s in <production> is not LL1 decidable from the others", i+1);
                        libc::exit(-1);
                    }
                    if (i == 0)
                    {
                        cg.@if("self.peek_is(%s)", to_push.collate(", ", "%sT.%s", self.token_tname))
                        {
                            foreach (&quant : alt.children)
                            {
                                self.generate_quantified_information(cg, quant, collated_nts, collated_named_nts, collated_named_tokens);
                            }
                        };
                    }
                    else
                    {
                        cg.@else_if("self.peek_is(%s)", to_push.collate(", ", "%sT.%s", self.token_tname))
                        {
                            foreach (&quant : alt.children)
                            {
                                self.generate_quantified_information(cg, quant, collated_nts, collated_named_nts, collated_named_tokens);
                            }
                        };
                    }
                }
                cg.@else()
                {
                    cg.line("self.log_unexpected(runtime::get_expected_sequence(%s));", check.collate(", ", "%sT.%s", self.token_tname));
                    cg.line("return runtime::UNEXPECTED_TOKEN?;");
                };
            }
        case TERMINAL:
            cg.line("c.push({.is_terminal = true, .terminal = self.peek()});");
            if (primary.field.len)
            {
                if (collated_named_tokens.get(primary.field)!!)
                {
                    cg.line("%s.push(c[^1].terminal);", primary.field);
                }
                else
                {
                    cg.line("%s = c[^1].terminal;", primary.field);
                }
            }
            cg.line("s = self.expect(s,%sT.%s)!;", self.token_tname, primary.reference);
        case NONTERMINAL:
            cg.line("c.push({.is_terminal = false, .nonterminal = self.parse_%s()!});", primary.reference);
            if (primary.field.len)
            {
                if (collated_named_tokens.get(primary.field)!!)
                {
                    cg.line("%s.push(c[^1].nonterminal);", primary.field);
                }
                else
                {
                    cg.line("%s = c[^1].nonterminal;", primary.field);
                }
            }
            if (collated_nts.get(primary.reference)!!)
            {
                cg.line("%s.push(c[^1].nonterminal);", primary.reference);
            }
            else
            {
                cg.line("%s = c[^1].nonterminal;", primary.reference);
            }
            cg.line("s += c[^1].nonterminal.span;");

    }
}

fn String ParserContext.get_primary_expected(&self, Primary* primary)
{
    switch (primary.type)
    {
        case GROUP:
            StringSet target = {};
            List { String } visited;
            visited.push("<inside production>");
            foreach (&ch : primary.group)
            {
                self.get_terminals(ch, &visited, &target);
            }
            return target.collate(", ", "%sT.%s", self.token_tname);
        case TERMINAL:
            return primary.reference;
        case NONTERMINAL:
            StringSet target = {};
            List { String } visited;
            visited.push("<inside production>");
            self.get_starting_terminals(primary.reference, &visited, &target);
            return target.collate(", ", "%sT.%s", self.token_tname);
    }
}

fn void ParserContext.generate_quantified_information(&self, Codegen* cg, Quantified* quant, HashMap { String, bool } *collated_nts, HashMap { String, bool } *collated_named_nts, HashMap { String, bool } *collated_named_tokens)
{
    switch (quant.quantification)
    {
        case NONE:
            self.generate_primary_information(cg,&quant.primary,collated_nts, collated_named_nts, collated_named_tokens);
        case ANY_AMOUNT:
            String expected = self.get_primary_expected(&quant.primary);
            cg.@while("self.peek_is(%s)", expected)
            {
                self.generate_primary_information(cg,&quant.primary,collated_nts, collated_named_nts, collated_named_tokens);
            };
        case AT_LEAST_ONE:
            String expected = self.get_primary_expected(&quant.primary);
            cg.@do_while("self.peek_is(%s)", expected)
            {
                self.generate_primary_information(cg,&quant.primary,collated_nts, collated_named_nts, collated_named_tokens);
            };
        case OPTIONAL:
            String expected = self.get_primary_expected(&quant.primary);
            cg.@if("self.peek_is(%s)", expected)
            {
                self.generate_primary_information(cg,&quant.primary,collated_nts, collated_named_nts, collated_named_tokens);
            };
    }
}

fn void ParserContext.generate_alternative_information(&self, Codegen* cg, NonterminalDefinition* def, AlternativeDefinition* alt, HashMap { String, bool } *collated_nts, HashMap { String, bool } *collated_named_nts, HashMap { String, bool } *collated_named_tokens)
{
    foreach (attr : alt.attributes)
    {
        if (attr.attribute == "nowrap")
        {
            self.generate_passthrough_information(cg, alt);
            return;
        }
    }

    cg.@pool()
    {
        // Use 1 character variable names to prevent interfering with user variables
        cg.line("/* setup returned fields and returned information */");
        cg.line("Span s = {usz.max,usz.max};");
        cg.line("List { %s } c;", self.child_tname);
        collated_nts.@each(; String name, bool is_many)
        {
            if (is_many)
            {
                cg.line("List { %s* } %s;", self.node_tname, name);
            }
            else
            {
                cg.line("%s* %s;", self.node_tname, name);
            }
        };

        collated_named_nts.@each(; String name, bool is_many)
        {
            if (is_many)
            {
                cg.line("List { %s* } %s;", self.node_tname, name);
            }
            else
            {
                cg.line("%s* %s;", self.node_tname, name);
            }
        };

        collated_named_tokens.@each(; String name, bool is_many)
        {
            if (is_many)
            {
                cg.line("List { %s } %s;", self.token_tname, name);
            }
            else
            {
                cg.line("%s %s;", self.token_tname, name);
            }
        };
        cg.line();
        cg.line("/* make sure that the tree doesn't get leaked on a failed parse */");
        cg.line("defer catch");
        cg.@block()
        {
            cg.@foreach("n : c")
            {
                cg.@if("!n.is_terminal")
                {
                    cg.line("n.nonterminal.free(self.allocator);");
                };
            };
        };
        cg.line();
        cg.line("/* attempt to parse the node */");
        foreach (&quant : alt.children)
        {
            self.generate_quantified_information(cg, quant, collated_nts, collated_named_nts, collated_named_tokens);
        }
        cg.line();
        cg.line("/* construct the parsed node from the returned fields and information */");
        cg.line("%s* r = allocator::new(self.allocator, %s);",self.node_tname, self.node_tname);
        cg.line("r.type = %s;", def.name.to_ename());
        cg.line("r.span = s;");
        cg.line("r.children = c.to_array(self.allocator);");
        collated_nts.@each(; String name, bool is_many)
        {
            if (is_many)
            {
                cg.line("r.%s.%s = %s.to_array(self.allocator);", def.name, name, name);
            }
            else
            {
                cg.line("r.%s.%s = %s;", def.name, name, name);
            }
        };

        collated_named_nts.@each(; String name, bool is_many)
        {
            if (is_many)
            {
                cg.line("r.%s.%s = %s.to_array(self.allocator);", def.name, name, name);
            }
            else
            {
                cg.line("r.%s.%s = %s;", def.name, name, name);
            }
        };

        collated_named_tokens.@each(; String name, bool is_many)
        {
            if (is_many)
            {
                cg.line("r.%s.%s = %s.to_array(self.allocator);", def.name, name, name);
            }
            else
            {
                cg.line("r.%s.%s = %s;", def.name, name, name);
            }
        };
        cg.line("return r;");
    };
}

macro String StringSet.collate(self, String $separator, String $format = "%s", ... )
{
    DString result;
    bool comma = false;
    self.@each(; String value)
    {
        if (comma) result.append_chars($separator);
        comma = true;
        result.appendf($format,$vasplat,value);
    };
    return result.str_view();
}

fn void ParserContext.generate_nonterminal_information(&self, NonterminalDefinition* def)
{
    HashMap { String, bool } collated_nts;
    HashMap { String, bool } collated_named_nts;
    HashMap { String, bool } collated_named_tokens;
    bool add_to_enames = false;
    String visitor_union_tname;
    foreach (alt : def.alternatives)
    {
        bool should_continue;
        foreach (attr : alt.attributes)
        {
            if (attr.attribute == "nowrap")
            {
                should_continue = true;
                break;
            }
        }
        if (should_continue) continue;
        add_to_enames = true;
        foreach (quant : alt.children)
        {
            quant.primary.collate(&collated_nts, &collated_named_nts, &collated_named_tokens);
        }
    }
    if (collated_nts.len() > 0 || collated_named_nts.len() > 0 || collated_named_tokens.len() > 0)
    {
        /* Let's print its union membership card */
        NonterminalUnionMember membership_card;
        Codegen cg = (Codegen){}.init(tmem);
        String tname = string::tformat("%sContext", def.name.to_tname());
        String fname = def.name;
        visitor_union_tname = tname;
        // The bool is if there are 'many' of them 
        
        cg.@struct("%s", tname)
        {
            // Let's do everything on the temporary allocator here
            collated_nts.@each(; String name, bool is_many)
            {
                if (is_many)
                {
                    cg.line("%s*[] %s;", self.node_tname, name);
                }
                else
                {
                    cg.line("%s* %s;", self.node_tname, name);
                }
            };

            collated_named_nts.@each(; String name, bool is_many)
            {
                if (is_many)
                {
                    cg.line("%s*[] %s;", self.node_tname, name);
                }
                else
                {
                    cg.line("%s* %s;", self.node_tname, name);
                }
            };

            collated_named_tokens.@each(; String name, bool is_many)
            {
                if (is_many)
                {
                    cg.line("%s[] %s;", self.token_tname, name);
                }
                else
                {
                    cg.line("%s %s;", self.token_tname, name);
                }
            };
        };

        cg.line();

        cg.@fn("void %s.free(&self, Allocator a) @inline", tname)
        {
            collated_nts.@each(; String name, bool is_many)
            {
                if (is_many)
                {
                    cg.line("allocator::free(a, self.%s);", name);
                }
            };
            collated_named_nts.@each(; String name, bool is_many)
            {
                if (is_many)
                {
                    cg.line("allocator::free(a, self.%s);", name);
                }
            };
            collated_named_tokens.@each(; String name, bool is_many)
            {
                if (is_many)
                {
                    cg.line("allocator::free(a, self.%s);", name);
                }
            };
        };
        membership_card.tname = tname;
        membership_card.fname = fname;
        membership_card.struct_and_free = cg;
        self.nonterminal_union_members.push(membership_card);
    }
    String ename;
    if (add_to_enames)
    {
        ename = def.name.to_ename();
        self.nonterminal_enum_names.push(ename);

        self.visitor_methods.push({def.name, visitor_union_tname, ename});
    }

    Codegen cg = (Codegen){}.init(tmem);
    cg.@fn("%s*? %s.parse_%s(&self)", self.node_tname, self.parser_tname, def.name)
    {
        if (def.alternatives.len() == 1)
        {
            self.generate_alternative_information(&cg, def, &def.alternatives[0], &collated_nts, &collated_named_nts, &collated_named_tokens);
        }
        else
        {
            StringSet check;
            usz total_len;
            foreach (i, &alt : def.alternatives)
            {
                StringSet to_push = self.analyze_alt_top_level(alt, def.name);
                check.add_all_from(&to_push);
                total_len += to_push.len();
                if (check.len() != total_len)
                {
                    io::eprintfn("Error: alternative %s of %s is not LL1 decidable from the others", i+1,def.name);
                    libc::exit(-1);
                }
                cg.@if("self.peek_is(%s)", to_push.collate(", ", "%sT.%s", self.token_tname))
                {
                    self.generate_alternative_information(&cg, def, alt, &collated_nts, &collated_named_nts, &collated_named_tokens);
                };
            }
            cg.line("self.log_unexpected(runtime::get_expected_sequence(%s));", check.collate(", ", "%sT.%s", self.token_tname));
            cg.line("return runtime::UNEXPECTED_TOKEN?;");
        }
    };
    self.parse_methods.push(cg);
}

fn void generate_parser(String infile, String outfile)
{
    @pool()
    {
        ParserDefinition p = parse_parser_definition(infile);
        ParserContext ctx;
        String cased_language_name = p.language.to_tname();
        ctx.parser_tname = string::tformat("%sParser", cased_language_name);
        ctx.node_type_tname = string::tformat("%sNodeT", cased_language_name);
        ctx.node_tname = string::tformat("%sNode", cased_language_name);
        ctx.token_tname = string::tformat("%sToken", cased_language_name);
        ctx.child_tname = string::tformat("%sNodeChild", cased_language_name);
        ctx.definition = &p;
        ctx.nonterminal_union_members.tinit();
        ctx.nonterminal_enum_names.tinit();
        ctx.visitor_methods.tinit();
        p.nonterminals.@each(; String name, NonterminalDefinition def)
        {
            ctx.generate_nonterminal_information(&def);
        };

        Codegen cg = (Codegen){}.init(tmem);
        // Let's start by adding the header
        cg.@doc()
        {
            cg.line("[AUTOMATICALLY GENERATED BY C3PG]");
            cg.line("Parser implementation for: %s", cased_language_name);
        };

        cg.line("module %s;", p.module_path);
        cg.line();
        cg.line("/* STANDARD IMPORTS */");
        cg.line();
        cg.line("import c3pg::runtime;");
        cg.line("import std::collections::list;");
        cg.line();
        cg.line("/* LEXER IMPORT */");
        cg.line();
        cg.line("import %s;", p.lexer_module);
        cg.line();
        cg.line("/* NODE CHILD TYPE */");
        cg.line();
        cg.@struct("%s", ctx.child_tname)
        {
            cg.line("bool is_terminal;");
            cg.@union()
            {
                cg.line("%s terminal;", ctx.token_tname);
                cg.line("%s* nonterminal;", ctx.node_tname);
            };
        };
        cg.line();
        cg.line("/* NODE CONTEXTS */");
        cg.line();
        foreach (communist : ctx.nonterminal_union_members)
        {
            cg.insert(communist.struct_and_free);
        }
        cg.line("/* NODE TYPES */");
        cg.line();
        cg.@enum("%s", ctx.node_type_tname)
        {
            foreach (ename : ctx.nonterminal_enum_names)
            {
                cg.line("%s,", ename);
            }
        };
        cg.line();
        cg.line("/* NODE TYPE */");
        cg.line();
        cg.@struct("%s", ctx.node_tname)
        {
            cg.line("%s type;", ctx.node_type_tname);
            cg.line("Span span;");
            cg.line("%s[] children;", ctx.child_tname);
            cg.@union()
            {
                foreach (communist : ctx.nonterminal_union_members)
                {
                    cg.line("%s %s;", communist.tname, communist.fname);
                }
            };
        };
        cg.line();
        cg.@fn("void %s.free(&self, Allocator a)", ctx.node_tname)
        {
            cg.@foreach("child : self.children")
            {
                cg.@if("!child.is_terminal")
                {
                    cg.line("child.nonterminal.free(a);");
                };
            };
            cg.line("allocator::free(a, self.children);");
            cg.@switch("self.type")
            {
                foreach (communist : ctx.nonterminal_union_members)
                {
                    cg.@case("%s", communist.fname.to_ename())
                    {
                        cg.line("self.%s.free(a);", communist.fname);
                    };
                }
                cg.@default() {};
            }; 
            cg.line("allocator::free(a, self);");
        };
        cg.line();
        cg.line("/* PARSER CONTEXT */");
        cg.line();
        cg.@struct("%s", ctx.parser_tname)
        {
            cg.line("%sLexer* lexer;", cased_language_name);
            cg.line("Allocator allocator;");
            cg.line("C3PgLogger logger;");
            cg.line("bool primed;");
        };
        cg.line();
        cg.line("/* PARSER FUNCTIONS */");
        cg.line();
        cg.@fn("%s create_%s_parser(%sLexer* lexer, Allocator allocator = mem, C3PgLogger logger = null)", ctx.parser_tname, p.language, cased_language_name)
        {
            cg.line("return {lexer, allocator, logger, false};");
        };
        cg.line();
        cg.@fn("%s %s.peek(&self) @inline @private", ctx.token_tname, ctx.parser_tname)
        {
            cg.line("return self.lexer.current;");
        };
        cg.line();
        cg.@fn("%sT %s.peek_t(&self) @inline @private", ctx.token_tname, ctx.parser_tname)
        {
            cg.line("return self.peek().type;");
        };
        cg.line();
        cg.@fn("Span? %s.next(&self, Span current) @inline @private", ctx.parser_tname)
        {
            cg.line("Span result = self.peek().span;");
            cg.line("if (current.begin != usz.max) result = current + result;");
            cg.line("self.lexer.advance()!;");
            cg.line("return result;");
        };
        cg.line();
        cg.@fn("void %s.log_at(&self, Span s, String message) @inline @private", ctx.parser_tname)
        {
            cg.line("if (self.logger != null) self.logger.log_error(s,message,self.lexer.file,self.lexer.file_data);");  
        };
        cg.line();
        cg.@fn("void %s.log_current(&self, String message) @inline @private", ctx.parser_tname)
        {
            cg.line("self.log_at(self.lexer.current.span, message);");
        };
        cg.line();
        cg.@fn("void %s.log_unexpected(&self, String expected) @inline @private", ctx.parser_tname)
        {
            cg.line("self.log_current(string::tformat(`Unexpected token \"%%s\", expected %%s;`, runtime::get_terminal_name(self.peek_t()), expected));");
        };
        cg.line();
        cg.@macro("bool %s.peek_is(&self, ...) @private", ctx.parser_tname)
        {
            cg.line("var current = self.peek_t();");
            cg.line("return runtime::is_any_of(current, $vasplat);");
        };
        cg.line();
        cg.@macro("Span? %s.expect(&self, Span current_span, ...) @private", ctx.parser_tname, ctx.token_tname)
        {
            cg.@if("self.peek_is($vasplat)")
            {
                cg.line("return self.next(current_span);");
            };
            cg.line("self.log_unexpected(runtime::get_expected_sequence($vasplat));");
            cg.line("return runtime::UNEXPECTED_TOKEN?;");
        };
        cg.line();
        foreach (parse_method : ctx.parse_methods)
        {
            cg.insert(parse_method);
            cg.line();
        }
        cg.line("/* VISITOR METHODS */");
        cg.line();
        cg.@interface("%sVisitor", cased_language_name)
        {
            foreach (visitor_method : ctx.visitor_methods)
            {
                if (visitor_method.ctx_tname.len)
                {
                    cg.ifn("any? visit_%s(%s* node, %s* node_ctx, any ctx=null) @optional", visitor_method.fname, ctx.node_tname, visitor_method.ctx_tname);
                }
                else
                {
                    cg.ifn("any? visit_%s(%s* node, any ctx=null) @optional", visitor_method.fname, ctx.node_tname);
                }
            };
        };
        cg.line();
        cg.@fn("any? %s.visit(&self, %sVisitor visitor, any ctx=null)", ctx.node_tname, cased_language_name)
        {
            cg.@switch("self.type")
            {
                foreach (visitor_method : ctx.visitor_methods)
                {
                    cg.@case("%s", visitor_method.ename)
                    {
                        if (visitor_method.ctx_tname.len)
                        {
                            cg.line("return &visitor.visit_%s ? visitor.visit_%s(self, &self.%s, ctx) : self.visit_children(visitor, ctx);", visitor_method.fname, visitor_method.fname, visitor_method.fname);
                        }
                        else
                        {
                            cg.line("return &visitor.visit_%s ? visitor.visit_%s(self, ctx) : self.visit_children(visitor, ctx);", visitor_method.fname, visitor_method.fname);
                        }
                    };
                }
            };
        };
        cg.line();
        cg.@fn("any? %s.visit_children(&self, %sVisitor visitor, any ctx=null)", ctx.node_tname, cased_language_name)
        {
            cg.line("any result = null;");
            cg.@foreach("child : self.children")
            {
                cg.@if("!child.is_terminal")
                {
                    cg.line("result = child.nonterminal.visit(visitor, ctx)!;");
                };
            };
            cg.line("return result;");
        };
        File f = file::open(outfile,"w")!!;
        f.write((char[])cg.build())!!;
        f.flush()!!;
        f.close()!!;
    };
}