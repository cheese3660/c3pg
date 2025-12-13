<*
    String utility methods
*>
module c3pg::string_utils;

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