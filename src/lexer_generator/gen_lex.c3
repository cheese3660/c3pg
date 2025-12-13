<*
    This module contains an updated version of the lexer generator module, using the lexer and parser provided by C3Pg
*>
module c3pg::lexer_generator;
import c3pg::lexer_grammar::lexer;
import c3pg::lexer_grammar::parser;
import c3pg::runtime;
import std::io::file;


fn void generate(String infile, String outfile)
{
    @pool()
    {
        String data = (String)file::load_temp(infile)!!;
        LexerLexer lexer = lexer::create_lexer_lexer(data,tmem,infile,runtime::std_err);
        LexerParser parser = parser::create_lexer_parser(&lexer,tmem,runtime::std_err);
        LexerNode* root = parser.parse_root()!!;
        LexerTransformer transformer = { infile, data, {}};
        root.visit(&transformer)!!;
        io::printn(transformer.target);
    };
}