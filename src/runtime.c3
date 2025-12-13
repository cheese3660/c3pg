<*
    This is the runtime library that c3pg expects
*>
module c3pg::runtime;
import std::io;

<*
    This is used by both the lexer and parser to log error messages
*>
interface C3PgLogger
{
    <*
        @param span      : "The place the error occured"
        @param message   : "The error message"
        @param filename  : "The file that the error occured in"
        @param file_view : "A view to the entire file data that the error occured in"

        @require span.begin <= file_view.len : "Span is out of bounds of file"
    *>
    fn void log_error(Span span, String message, String filename, String file_view);
}

typedef StdErrLogger @private = char;

StdErrLogger std_err_logger_impl @private;

fn void StdErrLogger.log_error(&self, Span span, String message, String filename, String file_view) @dynamic
{
    // io::eprintn(message);
    // First we want to print the line that the error is on
    usz current_line_start = 0;
    usz line = 1;
    usz column = 1;
    for (usz i = 0; i < span.begin; i++)
    {
        if (file_view[i] == '\n')
        {
            line += 1;
            column = 1;
            current_line_start = i+1;
        }
        else
        {
            column += 1;
        }
    }

    if (span.begin != file_view.len)
    {
        DString file_data;
        DString span_data;
        for (usz j = current_line_start; j < file_view.len && file_view[j] != '\r' && file_view[j] != '\n'; j++)
        {
            if (file_view[j] == '\t')
            {
                file_data.append_chars("    ");
                if (j >= span.begin && j < span.begin + span.length)
                {
                    span_data.append_chars("^^^^");
                }
                else
                {
                    span_data.append_chars("    ");
                }
            }
            else
            {
                file_data.append_char(file_view[j]);
                if (j >= span.begin && j < span.begin + span.length)
                {
                    span_data.append_char('^');
                }
                else
                {
                    span_data.append_char(' ');
                }
            }
        }
        io::eprintn(file_data);
        io::eprintn(span_data);
    }

    io::eprintfn("%s:%s:%s: %s", filename, line, column, message);
}

C3PgLogger std_err = (C3PgLogger)&std_err_logger_impl;

<*
    This defines where nodes are within a file, used for generating error messages eventually
*>
struct Span
{
    usz begin;
    usz length;
}

<*
    @require self.begin < other.begin : "Spans are in the incorrect order"
*>
fn Span Span.add(self, Span other) @operator(+)
{
    // These 2 spans may be disjunct, so we need to get the true difference between them
    usz length_before = other.begin - self.begin;
    return {self.begin, length_before + other.length};
}

struct Coordinate
{
    usz line;
    usz column;
}

fn Coordinate Span.get_begin_in(self, String file)
{
    usz line = 1;
    usz column = 1;
    for (usz i = 0; i < self.begin && i < file.len; i++)
    {
        if (file[i] == '\r')
        {
            continue;
        }
        else if (file[i] == '\n')
        {
            line += 1;
            column = 1;
        }
        else
        {
            column += 1;
        }
    }
    return
    {
        line,
        column
    };
}

faultdef UNEXPECTED_CHARACTER;
faultdef ENDED_IN_ERROR_MODE;
faultdef ERROR_TOKEN;
faultdef UNEXPECTED_TOKEN;
faultdef MODE_STACK_CLEARED;

<* This is used to signify to the runtime that an @drop token was parsed *>
faultdef SINGLE_STEP_DROPPED;


macro String get_terminal_name(terminal_type)
{
    if (terminal_type.pattern.len > 0)
    {
        return terminal_type.pattern.tescape();
    }
    else
    {
        return string::tformat("%s",terminal_type);
    }
}

macro String get_expected_sequence(...)
{
    DString result = (DString){}.tinit($vacount * 32); // Liberally assume 32 characters for token as this is an error state
    $for var $i = 0; $i < $vacount; $i++:
        $if $i != 0:
            result.append_chars(", ");
        $endif
        result.appendf("%s",get_terminal_name($vaarg[$i]).tescape());
    $endfor
    return result.str_view();
}

macro bool is_any_of(check, ...)
{
    $for var $i = 0; $i < $vacount; $i++:
        if (check == $vaarg[$i]) return true;
    $endfor
    return false;
}
