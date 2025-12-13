module c3pg;
import std::io;
import regex;
import c3pg::lex_gen;
import c3pg::parse_gen;
import c3pg::lexer_generator;
import libc;

fn void print_usage() @noreturn
{
    io::eprintn("Usage: c3pg <in> <out>");
    io::eprintn("");
    io::eprintn("    <in>            The input file, is determined to be either a '[l]exer' file or '[g]rammar' by the last character of its extension");
    io::eprintn("    <out>           The output file, must be a '.c3' file");
    io::eprintn("");
    io::eprintn("    special command: if <in> is create-lib then the runtime-library that this generator accepts is dumped into a c3 file");
    libc::exit(1);
}

fn int main(String[] args)
{
    if (args.len != 3) print_usage();
    String in = args[1];
    String out = args[2];
    
    if (!out.ends_with(".c3"))
    {
        io::eprintn("Invalid file extension on the output file, it must be a '.c3' file!");
        return 2;
    }

    if (in == "create-lib")
    {
        // We dump the expected runtime library into the output
        io::eprintn("create-lib is not yet implemented!");
        return 0;
    }

    switch (in[^1])
    {
        case 'l':
            // We generate a lexer from this file!
            lexer_generator::generate(in,out);
            // lex_gen::generate_lexer(in,out);
            return 0;
        case 'g':
            parse_gen::generate_parser(in,out);
            return 0;
        default:
            io::eprintn("Cannot determine whether this is a [l]exer file or a [g]rammar file from the final character of the filename!");
            return 3;
    }
}

