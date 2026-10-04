// 'try' in a static's initializer, where there is no caller to pass a failure to.
module TryOutsideFunction;

Result<int, String> Make() => Ok(1);

static int Value = try Make();

int Main() => Value;
