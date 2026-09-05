// SPDX-License-Identifier: 0BSD
module Bad;
import Standard.Convert;

public enum Other { None, Bad }

// `try` passes a failure on unchanged, so the two error types have to agree.
// Converting one to the other is a decision about what the failure means, and
// making it silently is what this refuses.
Result<long, Other> Read(String text) {
    return Ok(try Convert.ToLong(text));
}

int Main() { return 0; }
