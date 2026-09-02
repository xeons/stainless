module Bad;

// There are no forward declarations, because order never matters.
int Later();

int Main() { return Later(); }
