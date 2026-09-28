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

/// The status codes RFC 9110 and its companions register, by .NET's names.
///
/// A response may carry a code with no name here; it is still a value of
/// this type, cast from its number, and prints as that number.
public enum HttpStatusCode
{
    Continue = 100,
    SwitchingProtocols = 101,
    Processing = 102,
    EarlyHints = 103,

    OK = 200,
    Created = 201,
    Accepted = 202,
    NonAuthoritativeInformation = 203,
    NoContent = 204,
    ResetContent = 205,
    PartialContent = 206,
    MultiStatus = 207,
    AlreadyReported = 208,
    IMUsed = 226,

    MultipleChoices = 300,
    MovedPermanently = 301,
    Found = 302,
    SeeOther = 303,
    NotModified = 304,
    UseProxy = 305,
    Unused = 306,
    TemporaryRedirect = 307,
    PermanentRedirect = 308,

    BadRequest = 400,
    Unauthorized = 401,
    PaymentRequired = 402,
    Forbidden = 403,
    NotFound = 404,
    MethodNotAllowed = 405,
    NotAcceptable = 406,
    ProxyAuthenticationRequired = 407,
    RequestTimeout = 408,
    Conflict = 409,
    Gone = 410,
    LengthRequired = 411,
    PreconditionFailed = 412,
    RequestEntityTooLarge = 413,
    RequestUriTooLong = 414,
    UnsupportedMediaType = 415,
    RequestedRangeNotSatisfiable = 416,
    ExpectationFailed = 417,
    MisdirectedRequest = 421,
    UnprocessableContent = 422,
    Locked = 423,
    FailedDependency = 424,
    UpgradeRequired = 426,
    PreconditionRequired = 428,
    TooManyRequests = 429,
    RequestHeaderFieldsTooLarge = 431,
    UnavailableForLegalReasons = 451,

    InternalServerError = 500,
    NotImplemented = 501,
    BadGateway = 502,
    ServiceUnavailable = 503,
    GatewayTimeout = 504,
    HttpVersionNotSupported = 505,
    VariantAlsoNegotiates = 506,
    InsufficientStorage = 507,
    LoopDetected = 508,
    NotExtended = 510,
    NetworkAuthenticationRequired = 511,
}

/// The reason phrase RFC 9110 gives `code`, or an empty string for a code it
/// does not name.
internal String DescribeHttpStatusCode(HttpStatusCode code)
{
    switch (code)
    {
        case HttpStatusCode.Continue: return "Continue";
        case HttpStatusCode.SwitchingProtocols: return "Switching Protocols";
        case HttpStatusCode.OK: return "OK";
        case HttpStatusCode.Created: return "Created";
        case HttpStatusCode.Accepted: return "Accepted";
        case HttpStatusCode.NonAuthoritativeInformation: return "Non-Authoritative Information";
        case HttpStatusCode.NoContent: return "No Content";
        case HttpStatusCode.ResetContent: return "Reset Content";
        case HttpStatusCode.PartialContent: return "Partial Content";
        case HttpStatusCode.MultipleChoices: return "Multiple Choices";
        case HttpStatusCode.MovedPermanently: return "Moved Permanently";
        case HttpStatusCode.Found: return "Found";
        case HttpStatusCode.SeeOther: return "See Other";
        case HttpStatusCode.NotModified: return "Not Modified";
        case HttpStatusCode.UseProxy: return "Use Proxy";
        case HttpStatusCode.TemporaryRedirect: return "Temporary Redirect";
        case HttpStatusCode.PermanentRedirect: return "Permanent Redirect";
        case HttpStatusCode.BadRequest: return "Bad Request";
        case HttpStatusCode.Unauthorized: return "Unauthorized";
        case HttpStatusCode.PaymentRequired: return "Payment Required";
        case HttpStatusCode.Forbidden: return "Forbidden";
        case HttpStatusCode.NotFound: return "Not Found";
        case HttpStatusCode.MethodNotAllowed: return "Method Not Allowed";
        case HttpStatusCode.NotAcceptable: return "Not Acceptable";
        case HttpStatusCode.ProxyAuthenticationRequired: return "Proxy Authentication Required";
        case HttpStatusCode.RequestTimeout: return "Request Timeout";
        case HttpStatusCode.Conflict: return "Conflict";
        case HttpStatusCode.Gone: return "Gone";
        case HttpStatusCode.LengthRequired: return "Length Required";
        case HttpStatusCode.PreconditionFailed: return "Precondition Failed";
        case HttpStatusCode.RequestEntityTooLarge: return "Content Too Large";
        case HttpStatusCode.RequestUriTooLong: return "URI Too Long";
        case HttpStatusCode.UnsupportedMediaType: return "Unsupported Media Type";
        case HttpStatusCode.RequestedRangeNotSatisfiable: return "Range Not Satisfiable";
        case HttpStatusCode.ExpectationFailed: return "Expectation Failed";
        case HttpStatusCode.MisdirectedRequest: return "Misdirected Request";
        case HttpStatusCode.UnprocessableContent: return "Unprocessable Content";
        case HttpStatusCode.UpgradeRequired: return "Upgrade Required";
        case HttpStatusCode.PreconditionRequired: return "Precondition Required";
        case HttpStatusCode.TooManyRequests: return "Too Many Requests";
        case HttpStatusCode.RequestHeaderFieldsTooLarge: return "Request Header Fields Too Large";
        case HttpStatusCode.UnavailableForLegalReasons: return "Unavailable For Legal Reasons";
        case HttpStatusCode.InternalServerError: return "Internal Server Error";
        case HttpStatusCode.NotImplemented: return "Not Implemented";
        case HttpStatusCode.BadGateway: return "Bad Gateway";
        case HttpStatusCode.ServiceUnavailable: return "Service Unavailable";
        case HttpStatusCode.GatewayTimeout: return "Gateway Timeout";
        case HttpStatusCode.HttpVersionNotSupported: return "HTTP Version Not Supported";
        case HttpStatusCode.NetworkAuthenticationRequired: return "Network Authentication Required";
    }
    return "";
}
