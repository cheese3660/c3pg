<*
    This module contains macros for generating C3 code, and a context to keep indentation sane
*>
module c3pg::codegen;

struct Codegen
{
    DString built_code;
    ushort indentation;
}

fn Codegen Codegen.init(&self, Allocator allocator=tmem)
{
    self.built_code.init(allocator);
    return *self;
}

macro void Codegen.line(&self,String $line="", ...)
{
    $if $line.len != 0:
        self.built_code.append_repeat('\t', self.indentation);
        self.built_code.appendf($line, $vasplat);
    $endif
    self.built_code.append_chars("\n");
}

macro void Codegen.@doc(&self; @body)
{
    self.line("<*");
    self.indentation += 1;
    defer
    {
        self.indentation -= 1;
        self.line("*>");
    }
    @body();
}


macro void Codegen.@block(&self; @body)
{
    self.line("{");
    self.indentation += 1;
    defer
    {
        self.indentation -= 1;
        self.line("}");
    }
    @body();
}

macro void Codegen.@macro_block(&self, String $invocation="",...; @body)
{
    self.line($invocation, $vasplat);
    self.line("{");
    self.indentation += 1;
    defer
    {
        self.indentation -= 1;
        self.line("};");
    }
    @body();
}

macro void Codegen.@pool(&self; @body)
{
    self.@macro_block("@pool()")
    {
        @body();
    };
}

macro void Codegen.@fn(&self, String $signature="", ...; @body)
{
    self.line("fn " +++ $signature, $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@macro(&self, String $signature="", ...; @body)
{
    self.line("macro " +++ $signature, $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@enum(&self, String $signature = "", ...; @body)
{
    self.line("enum " +++ $signature, $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@struct(&self, String $signature = "", ...; @body)
{
    $if $signature.len > 0:
        self.line("struct " +++ $signature, $vasplat);
    $else
        self.line("struct");
    $endif
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@union(&self, String $signature = "", ...; @body)
{
    $if $signature.len > 0:
        self.line("union " +++ $signature, $vasplat);
    $else
        self.line("union");
    $endif
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@interface(&self, String $signature = "", ...; @body)
{
    self.line("interface " +++ $signature, $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.ifn(&self, String $signature = "", ...)
{
    self.line("fn " +++ $signature +++ ";", $vasplat);
}

macro void Codegen.@if(&self, String $condition, ...; @body)
{
    self.line("if (" +++ $condition +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@for(&self, String $decls, ...; @body)
{
    self.line("for (" +++ $decls +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@foreach(&self, String $decls, ...; @body)
{
    self.line("foreach (" +++ $decls +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@foreach_r(&self, String $decls, ...; @body)
{
    self.line("foreach_r (" +++ $decls +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@else(&self; @body)
{
    self.line("else");
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@else_if(&self, String $condition, ...; @body)
{
    self.line("else if (" +++ $condition +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@while(&self, String $condition, ...; @body)
{
    self.line("while (" +++ $condition +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@do_while(&self, String $condition, ...; @body)
{
    self.line("do");
    self.line("{");
    self.indentation += 1;
    defer
    {
        self.indentation -= 1;
        self.line("} while (" +++ $condition +++ ");", $vasplat);
    }
    @body();
}

macro void Codegen.@switch(&self, String $condition, ...; @body)
{
    self.line("switch (" +++ $condition +++ ")", $vasplat);
    self.@block()
    {
        @body();
    };
}

macro void Codegen.@case(&self, String $selector, ...; @body)
{
    self.line("case " +++ $selector +++ ":", $vasplat);
    self.indentation += 1;
    defer self.indentation -= 1;
    @body();
}

macro void Codegen.@default(&self; @body)
{   
    self.line("default:");
    self.indentation += 1;
    defer self.indentation -= 1;
    @body();
}

macro void Codegen.insert(&self, child)
{
    @pool()
    {
        Splitter splitter = child.build().tokenize_all("\n");
        while (try line = splitter.next())
        {
            self.line("%s", line);
        }
    };
}

fn String Codegen.build(&self, Allocator allocator=tmem) => self.built_code.copy_str(allocator);