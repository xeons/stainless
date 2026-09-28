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

import Standard.Collections;
import Standard.IO;
import Standard.Text;

/// Several bodies in one, each with its own fields, between boundaries:
/// RFC 2046's `multipart`.
///
///     var parts = new MultipartContent("mixed");
///     parts.Add(new StringContent("first"));
///     parts.Add(new ByteArrayContent(image));
///
/// The length is known when every part's is, and the whole can be sent again
/// when every part can.
public class MultipartContent : HttpContent
{
    private String _boundary;
    private List<HttpContent> _parts = new List<HttpContent>();

    /// `multipart/mixed`, with a random boundary.
    public MultipartContent() : this("mixed", CreateHttpBoundary()) { }

    /// `multipart/` + `subtype`, with a random boundary.
    public MultipartContent(String subtype) : this(subtype, CreateHttpBoundary()) { }

    /// `multipart/` + `subtype`, divided by `boundary`, which MUST NOT occur
    /// in any part and MUST be 1 to 70 characters.
    public MultipartContent(String subtype, String boundary)
    {
        _boundary = boundary;
        var type = new MediaTypeHeaderValue("multipart/" + subtype);
        type.SetParameter("boundary", boundary);
        Headers.ContentType = type;
    }

    /// The boundary between parts.
    public String Boundary => _boundary;

    /// The parts, in order.
    public List<HttpContent> Parts => _parts;

    /// Adds a part after the others.
    public void Add(HttpContent content) => _parts.Add(content);

    protected override HttpError SerializeToStream(IStream stream)
    {
        bool first = true;
        foreach (var part in _parts)
        {
            if (!WriteHttpText(stream, CreatePartHead(part, first)))
                return HttpError.ContentFailure;
            first = false;
            HttpError written = part.WriteHttpContent(stream);
            if (written != HttpError.None)
                return written;
        }
        if (!WriteHttpText(stream, CreateClosingDelimiter(first)))
            return HttpError.ContentFailure;
        return HttpError.None;
    }

    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        long total = 0;
        bool first = true;
        foreach (var part in _parts)
        {
            if (!part.TryComputeHttpContentLength(out long partLength))
                return false;
            total += (long)CreatePartHead(part, first).ByteLength() + partLength;
            first = false;
        }
        total += (long)CreateClosingDelimiter(first).ByteLength();
        length = total;
        return true;
    }

    protected override bool CanReplayContent
    {
        get
        {
            foreach (var part in _parts)
            {
                if (!part.IsHttpContentReplayable)
                    return false;
            }
            return true;
        }
    }

    protected override bool TryRewindContent()
    {
        foreach (var part in _parts)
        {
            if (!part.RewindHttpContent())
                return false;
        }
        return true;
    }

    /// Disposes every part.
    public override void Dispose()
    {
        foreach (var part in _parts)
            part.Dispose();
    }

    /// The delimiter and fields that open `part`.
    private String CreatePartHead(HttpContent part, bool first)
    {
        var text = new StringBuilder();
        if (!first)
            text.Append("\r\n");
        text.Append("--");
        text.Append(_boundary);
        text.Append("\r\n");
        text.Append(part.Headers.ToString());
        text.Append("\r\n");
        return text.ToText();
    }

    private String CreateClosingDelimiter(bool empty) =>
        (empty ? "--" : "\r\n--") + _boundary + "--\r\n";
}

/// A boundary unlikely to occur in any body: 32 random hexadecimal digits.
internal String CreateHttpBoundary() => Guid.NewGuid().ToString("N");

internal bool WriteHttpText(IStream stream, String text)
{
    var bytes = text.ToBytes();
    return WriteAllHttpBytes(stream, bytes, 0u, bytes.Length);
}
