<*
    String utility methods
*>
module c3pg::string_utils;

<*
 Unescape a quoted string by parsing escape sequences.

 @param allocator : "The allocator to use for the result"
 @param s : "The quoted string to unescape"
 @param allow_unquoted : "Set to true to unescape strings not surrounded by quotes, defaults to false"
 @return "The unescaped string without quotes, safe to convert to ZString"
 @return? string::UNTERMINATED_STRING, string::INVALID_ESCAPE_SEQUENCE, string::INVALID_HEX_ESCAPE, string::INVALID_UNICODE_ESCAPE
*>
fn String? String.unescape_better(String s, Allocator allocator, bool allow_unquoted = false)
{
	if (s.len >= 2 && s[0] == '"' && s[^1] == '"')
	{
		// Remove quotes.
		s = s[1:^2];
	}
	else if (!allow_unquoted) return string::UNTERMINATED_STRING?;

    // Handle empty string case
    if (!s.len)
    {
        return "".copy(allocator);
    }

    DString result = dstring::new_with_capacity(allocator, s.len);

	usz len = s.len;
	for (usz i = 0; i < len; i++)
	{
		char c = s[i];
        if (c != '\\')
        {
            result.append_char(c);
            continue;
        }

        // Handle escape sequence
        if (i + 1 >= len) return string::INVALID_ESCAPE_SEQUENCE?;

        char escape_char = s[++i];
        switch (escape_char)
        {
            case '"':  result.append_char('"');
            case '\\': result.append_char('\\');
            case '/':  result.append_char('/');
            case 'b':  result.append_char('\b');
            case 'f':  result.append_char('\f');
            case 'n':  result.append_char('\n');
            case 'r':  result.append_char('\r');
            case 't':  result.append_char('\t');
            case 'v':  result.append_char('\v');
            case '0':  result.append_char('\0');
            case 'x':
                // Hex escape \xHH
                if (i + 2 >= len) return string::INVALID_HEX_ESCAPE?;
                char h1 = s[++i];
                char h2 = s[++i];
                if (!h1.is_xdigit() || !h2.is_xdigit()) return string::INVALID_HEX_ESCAPE?;
                uint val = h1 > '9' ? (h1 | 32) - 'a' + 10 : h1 - '0';
                val = val << 4;
                val += h2 > '9' ? (h2 | 32) - 'a' + 10 : h2 - '0';
                result.append_char((char)val);
            case 'u':
                // Unicode escape \uHHHH
                if (i + 4 >= len) return string::INVALID_UNICODE_ESCAPE?;
                uint val;
                for (int j = 0; j < 4; j++)
                {
                    char hex_char = s[++i];
                    if (!hex_char.is_xdigit()) return string::INVALID_UNICODE_ESCAPE?;
                    val = val << 4 + (hex_char > '9' ? (hex_char | 32) - 'a' + 10 : hex_char - '0');
                }
                result.append_char32(val);
            case 'U':
                // Unicode escape \UHHHHHHHH
                if (i + 8 >= len) return string::INVALID_UNICODE_ESCAPE?;
                uint val;
                for (int j = 0; j < 8; j++)
                {
                    char hex_char = s[++i];
                    if (!hex_char.is_xdigit()) return string::INVALID_UNICODE_ESCAPE?;
                    val = val << 4 + (hex_char > '9' ? (hex_char | 32) - 'a' + 10 : hex_char - '0');
                }
                result.append_char32(val);
            default:
                result.append_char32(escape_char);
        }
    }

    return result.copy_str(allocator);
}

<*
 Unescape a quoted string using the temp allocator.

 @param s : "The quoted string to unescape"
 @param allow_unquoted : "Set to true to unescape strings not surrounded by quotes, defaults to false"
 @return "The unescaped string without quotes"
 @return? string::UNTERMINATED_STRING, string::INVALID_ESCAPE_SEQUENCE, string::INVALID_HEX_ESCAPE, string::INVALID_UNICODE_ESCAPE
*>
fn String? String.tunescape_better(String s, bool allow_unquoted = false) => s.unescape_better(tmem, allow_unquoted);

fn String String.to_tname(self)
{
    DString s;
    bool capitalize_next = true;
    foreach (ch : self)
    {
        if (ch == '_')
        {
            if (capitalize_next)
            {
                s.append_char('_');
            }
            else {
                capitalize_next = true;
            }
        }
        else if (capitalize_next)
        {
            s.append_char(ch.to_upper());
            capitalize_next = false;
        }
        else
        {
            s.append_char(ch.to_lower());
        }
    }
    return s.str_view();
}

fn String String.to_fname(self)
{
    return self.to_lower_tcopy();
}

fn String String.to_ename(self)
{
    return self.to_upper_tcopy();
}