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

module Standard.Security.Cryptography.X509Certificates;

import Standard.Security.Cryptography;

#if MACOS

// Every Mac has both, so they are linked rather than loaded by name; only a
// program that compiles this module gets them.
#pragma comment(framework, "Security")
#pragma comment(framework, "CoreFoundation")

extern "C"
{
    int SecTrustSettingsCopyCertificates(int domain, void** certificates);
    int SecTrustSettingsCopyTrustSettings(void* certificate, int domain, void** settings);
    void* SecCertificateCopyData(void* certificate);
    long CFArrayGetCount(void* array);
    void* CFArrayGetValueAtIndex(void* array, long index);
    long CFDataGetLength(void* data);
    byte* CFDataGetBytePtr(void* data);
    void CFRelease(void* value);
    void* CFDictionaryGetValue(void* dictionary, void* key);
    byte CFNumberGetValue(void* number, long type, void* value);
    void* CFStringCreateWithCString(void* allocator, byte* text, uint encoding);
}

/// `kSecTrustSettingsDomainUser` and `kSecTrustSettingsDomainAdmin`.
internal const int TrustDomainUser = 0;
internal const int TrustDomainAdmin = 1;

/// `kSecTrustSettingsResult`'s values.
internal const int TrustResultRoot = 1;
internal const int TrustResultAsRoot = 2;
internal const int TrustResultDeny = 3;
internal const int TrustResultUnspecified = 4;

/// `kCFNumberSInt32Type`.
internal const long NumberSInt32 = 3;

/// `kCFStringEncodingUTF8`.
internal const uint StringEncodingUtf8 = 0x08000100u;

/// The trust settings an administrator and a user have made, read through
/// Security.framework.
internal sealed class TrustSettings
{
    private void* _resultKey;

    internal TrustSettings()
    {
        // The header's key is a macro, CFSTR("kSecTrustSettingsResult"), and
        // not a symbol, so the string is made here; a dictionary compares
        // keys by value.
        _resultKey = CFStringCreateWithCString(
            null, "kSecTrustSettingsResult".ToPointer(), StringEncodingUtf8);
    }

    ~TrustSettings()
    {
        if (_resultKey != null)
            CFRelease(_resultKey);
    }

    /// Whether the key could be made, without which nothing can be read.
    internal bool Ready => _resultKey != null;

    /// What an administrator, and for the current user the user, has said:
    /// a certificate either marked trusted is added to `certificates`, and
    /// one either marked to deny is taken out of it.
    internal void Apply(bool currentUser, X509Certificate2Collection certificates)
    {
        var denied = new X509Certificate2Collection();

        ReadDomain(TrustDomainAdmin, certificates, denied);
        if (currentUser)
            ReadDomain(TrustDomainUser, certificates, denied);

        foreach (X509Certificate2 refused in denied)
            certificates.Remove(refused);
    }

    /// Every certificate one domain has settings for, sorted by what they say.
    private void ReadDomain(int domain, X509Certificate2Collection trusted,
                            X509Certificate2Collection denied)
    {
        void* list = null;
        if (SecTrustSettingsCopyCertificates(domain, &list) != 0 || list == null)
            return;

        long count = CFArrayGetCount(list);
        for (long i = 0; i < count; i++)
        {
            void* certificate = CFArrayGetValueAtIndex(list, i);
            var parsed = Parse(certificate);
            if (!parsed.Ok)
                continue;

            int result = Result(certificate, domain);
            if (result == TrustResultRoot || result == TrustResultAsRoot)
                trusted.Add(parsed.Value);
            else if (result == TrustResultDeny)
                denied.Add(parsed.Value);
        }
        CFRelease(list);
    }

    /// What one domain's settings say of a certificate. An empty list of
    /// settings is trust as a root, and so is a setting with no result; a
    /// deny anywhere in the list wins.
    private int Result(void* certificate, int domain)
    {
        void* settings = null;
        if (SecTrustSettingsCopyTrustSettings(certificate, domain, &settings) != 0 || settings == null)
            return TrustResultUnspecified;

        long count = CFArrayGetCount(settings);
        int result = count == 0 ? TrustResultRoot : TrustResultUnspecified;
        for (long i = 0; i < count; i++)
        {
            int said = TrustResultRoot;
            void* value = CFDictionaryGetValue(CFArrayGetValueAtIndex(settings, i), _resultKey);
            if (value != null)
                CFNumberGetValue(value, NumberSInt32, (void*)&said);

            if (said == TrustResultDeny)
            {
                result = TrustResultDeny;
                break;
            }
            if (said == TrustResultRoot || said == TrustResultAsRoot)
                result = said;
        }
        CFRelease(settings);
        return result;
    }

    private static Result<X509Certificate2, CryptoError> Parse(void* certificate)
    {
        void* data = SecCertificateCopyData(certificate);
        if (data == null)
            return Fail(CryptoError.Encoding);

        long length = CFDataGetLength(data);
        byte* bytes = CFDataGetBytePtr(data);
        var encoded = new byte[(nuint)length];
        for (nuint i = 0u; i < encoded.Length; i++)
            encoded[i] = bytes[i];
        CFRelease(data);
        return X509Certificate2.FromDer(encoded);
    }
}

#endif
