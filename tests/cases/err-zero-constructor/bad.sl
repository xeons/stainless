// Every constructor writes every field whose type has no zero value, on every
// path. A private helper it calls is followed; a public method is not, since
// an override of it could write nothing. A class with no constructor has only
// its initializers.
module Bad;

public class Form
{
    private String _title;
    private String _caption;

    public Form(bool early)
    {
        InitializeComponent();
        if (early)
            return;
        _caption = "late";
    }

    private void InitializeComponent()
    {
        _title = "form";
    }
}

public class Panel
{
    private String _name;

    public Panel()
    {
        Reset();
    }

    public void Reset()
    {
        _name = "panel";
    }
}

public class Plain
{
    public String Name;
}

int Main() => 0;
