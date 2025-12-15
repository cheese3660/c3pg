module c3pg::lexer_generator;
import c3pg::lexer_grammar::parser;
import std::collections::list;
import regex; // We want to validate regexen before we emit the lexer code, easiest way is just to compile them
import c3pg::runtime;

struct LexerTransformer (LexerVisitor)
{
    String filename;
    String fileview;
    LexerDefinition target;
}

fn any? LexerTransformer.visit_named_terminal(
    &self,
    LexerNode* node,
    NamedTerminalContext* node_ctx, 
    any ctx=null
) @dynamic
{
    LexerTerminal* lt_ctx = anycast(ctx, LexerTerminal)!;
    
    lt_ctx.type = NORMAL;
    lt_ctx.name = node_ctx.name.view;
    
    if (node_ctx.next_state.len)
    {
        node_ctx.next_state[0].visit(self, ctx)!;
    }

    // node_ctx.pattern.visit(self, ctx)!;

    return null;
}

fn any? LexerTransformer.visit_drop_terminal(
    &self,
    LexerNode* node,
    DropTerminalContext* node_ctx,
    any ctx = null
) @dynamic
{
    LexerTerminal* lt_ctx = anycast(ctx, LexerTerminal)!;
    lt_ctx.type = DROP;

    if (node_ctx.next_state.len)
    {
        node_ctx.next_state[0].visit(self, ctx)!;
    }

    // node_ctx.pattern.visit(self, ctx)!;
    
    return null;
}

fn any? LexerTransformer.visit_error_terminal(
    &self,
    LexerNode* node,
    ErrorTerminalContext* node_ctx,
    any ctx = null
) @dynamic
{
    LexerTerminal* lt_ctx = anycast(ctx, LexerTerminal)!;
    // TODO: Add error messages
    lt_ctx.type = ERROR;
    // node_ctx.pattern.visit(self, ctx)!;
    if (node_ctx.e)
    {
        node_ctx.e[0].visit(self, &lt_ctx.error)!;
    }
    return null;
}

enum EscapeSequenceState
{
    NORMAL,
    GETTING_ESCAPE_CHARACTER,
    HEX1,
    HEX2,
    UNICODE1,
    UNICODE2,
    UNICODE3,
    UNICODE4,
    UNICODE5,
    UNICODE6
}

faultdef STRING_FAILED_VALIDATION;
faultdef REGEX_FAILED_VALIDATION;

import std::io;
fn any? LexerTransformer.visit_string(
    &self,
    LexerNode* node,
    StringContext* node_ctx,
    any ctx = null
) @dynamic
{
    String* target;
    if (ctx.type == LexerTerminal)
    {
        LexerTerminal* lt_ctx = anycast(ctx, LexerTerminal)!!;
        lt_ctx.is_pattern_regex = false;
        target = &lt_ctx.pattern;
    }
    else if (ctx.type == String)
    {
        target = anycast(ctx, String)!!;
    }
    
    /* Let's do some escape sequence validation, though we can likely do that in the lexer once we introduce error messages */
    DString being_built;
    being_built.tinit(node_ctx.contents.len);
    
    EscapeSequenceState state;
    Span escape_sequence_span;
    Char32 built_character;

    foreach (lt : node_ctx.contents)
    {
        // Char32 ch = lt.view[0];
        usz sz = lt.view.len;
        Char32? ch = conv::utf8_to_char32(&lt.view[0],&sz);
        
        if (catch ch)
        {
            runtime::std_err.log_error(lt.span, "Invalid utf8 character!", self.filename, self.fileview);
            return STRING_FAILED_VALIDATION?;
        }

        switch (state)
        {
            case NORMAL:
                if (ch == '\\')
                {
                    state = GETTING_ESCAPE_CHARACTER;
                    escape_sequence_span = lt.span;
                    built_character = 0;
                }
                else
                {
                    being_built.append_char32(ch);
                }
            case GETTING_ESCAPE_CHARACTER:
                escape_sequence_span += lt.span;
                switch (ch)
                {
                    case 'b':
                        being_built.append_char('\b');
                        state = NORMAL;
                    case 'f':
                        being_built.append_char('\f');
                        state = NORMAL;
                    case 'n':
                        being_built.append_char('\n');
                        state = NORMAL;
                    case 'r':
                        being_built.append_char('\r');
                        state = NORMAL;
                    case 't':
                        being_built.append_char('\t');
                        state = NORMAL;
                    case 'v':
                        being_built.append_char('\v');
                        state = NORMAL;
                    case '0':
                        being_built.append_char('\0');
                        state = NORMAL;
                    case 'x':
                        state = HEX1;
                    case 'u':
                        state = UNICODE1;
                    default:
                        being_built.append_char32(ch);
                        state = NORMAL;
                }
            case HEX1:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    runtime::std_err.log_error(escape_sequence_span,"Invalid hex escape!", self.filename, self.fileview);
                    return STRING_FAILED_VALIDATION?;
                }
                built_character = ascii::HEX_VALUE[ch_c] << 4;
                state = HEX2;
            case HEX2:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    runtime::std_err.log_error(escape_sequence_span,"Invalid hex escape!", self.filename, self.fileview);
                    return STRING_FAILED_VALIDATION?;
                }
                being_built.append_char(ascii::HEX_VALUE[ch_c] | (char)(built_character));
                state = NORMAL;
            case UNICODE1:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    runtime::std_err.log_error(escape_sequence_span,"Invalid unicode escape!", self.filename, self.fileview);
                    return STRING_FAILED_VALIDATION?;
                }
                built_character = ascii::HEX_VALUE[ch_c];
                state = UNICODE2;
            case UNICODE2:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    being_built.append_char32(built_character);
                    state = NORMAL;
                }
                built_character <<= 4;
                built_character |= ascii::HEX_VALUE[ch_c];
                state = UNICODE3;
            case UNICODE3:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    being_built.append_char32(built_character);
                    state = NORMAL;
                }
                built_character <<= 4;
                built_character |= ascii::HEX_VALUE[ch_c];
                state = UNICODE4;
            case UNICODE4:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    being_built.append_char32(built_character);
                    state = NORMAL;
                }
                built_character <<= 4;
                built_character |= ascii::HEX_VALUE[ch_c];
                state = UNICODE5;
            case UNICODE5:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    being_built.append_char32(built_character);
                    state = NORMAL;
                }
                built_character <<= 4;
                built_character |= ascii::HEX_VALUE[ch_c];
                state = UNICODE6;
            case UNICODE6:
                escape_sequence_span += lt.span;
                char ch_c = (char)ch;
                if (ch >= 128 || !ch_c.is_xdigit())
                {
                    being_built.append_char32(built_character);
                    state = NORMAL;
                }
                built_character <<= 4;
                built_character |= ascii::HEX_VALUE[ch_c];
                being_built.append_char32(built_character);
                state = NORMAL;
        }
    }
    if (state == GETTING_ESCAPE_CHARACTER)
    {
        runtime::std_err.log_error(escape_sequence_span,"Invalid escape sequence introduction!",self.filename,self.fileview);
        return STRING_FAILED_VALIDATION?;
    }
    else if (state == HEX1 || state == HEX2)
    {
        runtime::std_err.log_error(escape_sequence_span,"Invalid hex escape!", self.filename, self.fileview);
        return STRING_FAILED_VALIDATION?;
    }
    else if (state == UNICODE1)
    {
        runtime::std_err.log_error(escape_sequence_span,"Invalid unicode escape!", self.filename, self.fileview);
        return STRING_FAILED_VALIDATION?;
    }
    else if (state != NORMAL)
    {
        being_built.append_char32(built_character);
    }
    *target = being_built.str_view();
    return null;
}

fn any? LexerTransformer.visit_regex(
    &self,
    LexerNode* node,
    RegexContext* node_ctx,
    any ctx = null
) @dynamic
{
    LexerTerminal* lt_ctx = anycast(ctx, LexerTerminal)!;
    lt_ctx.is_pattern_regex = true;
    DString built;
    built.tinit(node_ctx.contents.len);
    foreach (lt : node_ctx.contents)
    {
        built.append_chars(lt.view);
    }
    @pool()
    {
        if (catch error = regex::make_runtime_regex(built.str_view(), NONE, tmem))
        {
            switch (error)
            {
                case regex::INVALID_ESCAPE_SEQUENCE:
                    runtime::std_err.log_error(node.span, "Invalid escape sequence in regex!", self.filename, self.fileview);
                case regex::UNTERMINATED_CHARACTER_GROUP:
                    runtime::std_err.log_error(node.span, "Unterminated character group in regex!", self.filename, self.fileview);
                case regex::UNEXPECTED_CHARACTER:
                    runtime::std_err.log_error(node.span, "Unexpected character in regex!", self.filename, self.fileview);
                case regex::UNFILLED_RANGE_QUANTIFIER:
                    runtime::std_err.log_error(node.span, "Unexpected character in regex!", self.filename, self.fileview);
                case regex::UNEXPECTED_END_OF_INPUT:
                    runtime::std_err.log_error(node.span, "Unexpected end of input in regex!", self.filename, self.fileview);
                case regex::INVALID_RANGE_QUANTIFIER:
                    runtime::std_err.log_error(node.span, "Invalid range quantifier in regex!", self.filename, self.fileview);
                case regex::UNEXPECTED_TOKEN:
                    runtime::std_err.log_error(node.span, "Unexpected token in regex!", self.filename, self.fileview);
                case regex::UNTERMINATED_SUBEXPRESSION:
                    runtime::std_err.log_error(node.span, "Unterminated subexpression in regex!", self.filename, self.fileview);
                case regex::INVALID_CAPTURE_GROUP_ID:
                    runtime::std_err.log_error(node.span, "Invalid capture group ID in regex!", self.filename, self.fileview);
                case regex::EXTRANEOUS_PARENTHESES:
                    runtime::std_err.log_error(node.span, "Extraneous parentheses in regex!", self.filename, self.fileview);
                default:
                    runtime::std_err.log_error(node.span, "Unknown error in regex!", self.filename, self.fileview);
            }
            return REGEX_FAILED_VALIDATION?;
        }
    };
    lt_ctx.pattern = built.str_view();
    return null;
}

fn any? LexerTransformer.visit_next_state(
    &self,
    LexerNode* node,
    NextStateContext* node_ctx,
    any ctx = null
) @dynamic
{
    LexerTerminal* lt_ctx = anycast(ctx, LexerTerminal)!;
    lt_ctx.push_mode = node_ctx.name.view;
    return null;
}

fn any? LexerTransformer.visit_root(
    &self,
    LexerNode* node,
    RootContext* node_ctx,
    any ctx = null
) @dynamic
{
    self.target.modes.push({"DEFAULT", false, {}});
    return node.visit_children(self, &self.target.modes[0]);
}

faultdef INVALID_INFO_FIELD;

struct NamespacedCtx
{
    String* field;
    bool allows_path;
}

fn any? LexerTransformer.visit_lexer_info(&self, LexerNode* node, LexerInfoContext* node_ctx, any ctx=null) @dynamic
{
    String name = node_ctx.name.view;
    switch (name)
    {
        case "module":
            NamespacedCtx nctx = {&self.target.lexer_module, true};
            return node.visit_children(self, &nctx);
        case "language":
            NamespacedCtx nctx = {&self.target.language_name, false};
            return node.visit_children(self, &nctx);
        default:
            runtime::std_err.log_error(node_ctx.name.span, "Unknown info field type!", self.filename, self.fileview);
            return INVALID_INFO_FIELD?;
    }
}

fn any? LexerTransformer.visit_namespaced_info(&self, LexerNode* node, NamespacedInfoContext* node_ctx, any ctx=null) @dynamic
{
    NamespacedCtx* nctx = anycast(ctx, NamespacedCtx)!;
    DString built;
    if (node_ctx.children.len > 1 && !nctx.allows_path)
    {
        runtime::std_err.log_error(node.span, "Field does not take a namespaced path!", self.filename, self.fileview);
        return INVALID_INFO_FIELD?;
    }
    foreach (i, child : node_ctx.children)
    {
        if (i > 0)
        {
            built.append_chars("::");
        }
        built.append_chars(child.view);
    }
    *(nctx.field) = built.str_view();
    return null;
}


fn any? LexerTransformer.visit_terminal(&self, LexerNode* node, TerminalContext* node_ctx, any ctx = null) @dynamic
{
    LexerMode* mode = anycast(ctx, LexerMode)!;
    mode.terminals.push({});
    return node.visit_children(self, &mode.terminals[^1]);
}

fn any? LexerTransformer.visit_mode(&self, LexerNode* node, ModeContext* node_ctx, any ctx = null) @dynamic
{
    self.target.modes.push({node_ctx.name.view, node_ctx.err.len != 0, {}});
    return node.visit_children(self, &self.target.modes[^1]);
}