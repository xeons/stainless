// Stainless - an experimental general-purpose language.
// Copyright (C) 2026 Brandon Scott
//
// This file is part of the Stainless runtime library. It is free
// software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any
// later version.
//
// It is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// As an additional permission under section 7 of that License, compiling
// a program with Stainless does not by itself place that program under
// the GNU General Public License. See LICENSE.RUNTIME.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

module Standard.Net.Http;

/// One request in flight: its deadline, where its failure is reported, and
/// what the connection learned that decides whether it may be retried.
internal sealed class HttpExchange
{
    internal HttpDeadline Deadline;
    internal HttpFailure Failure;

    /// The most bytes a response head may take.
    internal nuint MaxHeaderBytes;

    /// Whether the failure came before a byte of the response arrived, on a
    /// connection that had carried a request already.
    internal bool IsRetryable = false;

    /// Whether the server said it never processed the request — a GOAWAY
    /// below its stream, or REFUSED_STREAM — so that any method may be sent
    /// again (RFC 9113 §8.7).
    internal bool IsUnprocessed = false;

    /// Whether a body with `Expect: 100-continue` is sent without waiting,
    /// after a wait on an earlier connection met a socket readable with no
    /// response on it.
    internal bool SkipsContinueWait = false;

    internal HttpExchange(HttpDeadline deadline, HttpFailure failure, nuint maxHeaderBytes)
    {
        Deadline = deadline;
        Failure = failure;
        MaxHeaderBytes = maxHeaderBytes;
    }
}
