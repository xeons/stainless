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

import Standard.Collections;
import Standard.Env;
import Standard.File;
import Standard.Directory;
import Standard.Security.Cryptography;

/// The platform's certificates: .NET's `X509Store`, read-only.
///
/// ```csharp
/// var roots = X509Store.Open(StoreName.Root);
/// Console.WriteLine($"{roots.Certificates.Count} trusted roots");
/// ```
///
/// **On Windows** the system stores are read through crypt32 — `ROOT` for
/// `Root` and `CA` for `CertificateAuthority` — which is loaded by name the
/// first time a store is opened, so a program that never opens one does not
/// link it. A certificate in the current user's or the machine's
/// `Disallowed` store is left out of both.
///
/// **On macOS** `Root` is Apple's TLS roots, from `/etc/ssl/cert.pem` as
/// below, with the trust settings applied over them, read through
/// Security.framework, which is linked: every certificate an
/// administrator -- and for `CurrentUser`, the user -- has marked trusted is
/// added, and every one either has marked to deny is left out. A setting
/// limited to one policy is read as though it applied to all. The system's own
/// trust settings are not read for its roots, because they also trust Apple's
/// S/MIME and time-stamping roots, which the bundle leaves out. Nothing is
/// applied when `SSL_CERT_FILE` or `SSL_CERT_DIR` is set.
///
/// **Elsewhere** `Root` is the PEM bundle `SSL_CERT_FILE` names,
/// or else the first of the usual places that exists —
/// `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`,
/// `/etc/ssl/ca-bundle.pem`, `/etc/pki/tls/cacert.pem`, `/etc/ssl/cert.pem`
/// — together with every file in the directories `SSL_CERT_DIR` lists; and
/// `CertificateAuthority` is empty.
///
/// **Each store is read once per process**, the first time it is opened from
/// any thread, and shared after that. A certificate that does not parse is
/// passed over, and one found twice is kept once. A store that cannot be read
/// at all is empty, which a chain reports as `UntrustedRoot` or
/// `PartialChain` rather than as a failure of its own.
public sealed class X509Store
{
    private static Lazy<X509Certificate2Collection> s_userRoot =
        new Lazy<X509Certificate2Collection>(
            () => LoadSystemCertificates(StoreName.Root, StoreLocation.CurrentUser));
    private static Lazy<X509Certificate2Collection> s_userAuthorities =
        new Lazy<X509Certificate2Collection>(
            () => LoadSystemCertificates(StoreName.CertificateAuthority, StoreLocation.CurrentUser));
    private static Lazy<X509Certificate2Collection> s_machineRoot =
        new Lazy<X509Certificate2Collection>(
            () => LoadSystemCertificates(StoreName.Root, StoreLocation.LocalMachine));
    private static Lazy<X509Certificate2Collection> s_machineAuthorities =
        new Lazy<X509Certificate2Collection>(
            () => LoadSystemCertificates(StoreName.CertificateAuthority,
                                         StoreLocation.LocalMachine));

    private StoreName _name;
    private StoreLocation _location;
    private X509Certificate2Collection _certificates;

    private X509Store(StoreName name, StoreLocation location,
                      X509Certificate2Collection certificates)
    {
        _name = name;
        _location = location;
        _certificates = certificates;
    }

    /// The store `name` at `location`, read the first time it is asked for.
    ///
    /// @param name      which store
    /// @param location  whose; only Windows tells the two apart
    public static X509Store Open(StoreName name,
                                 StoreLocation location = StoreLocation.CurrentUser)
    {
        X509Certificate2Collection shared;
        if (location == StoreLocation.CurrentUser)
        {
            shared = name == StoreName.Root ? s_userRoot.Value : s_userAuthorities.Value;
        }
        else
        {
            shared = name == StoreName.Root ? s_machineRoot.Value : s_machineAuthorities.Value;
        }

        var copied = new X509Certificate2Collection();
        copied.AddRange(shared);
        return new X509Store(name, location, copied);
    }

    /// Which store this is.
    public StoreName Name => _name;

    /// Whose store this is.
    public StoreLocation Location => _location;

    /// Its certificates: a copy, which the caller MAY change.
    public X509Certificate2Collection Certificates => _certificates;

    private static X509Certificate2Collection LoadSystemCertificates(StoreName name,
                                                                     StoreLocation location)
    {
        var certificates = new X509Certificate2Collection();
#if WINDOWS
        var crypt32 = new Crypt32();
        if (!crypt32.Ready)
            return certificates;
        crypt32.ReadSystemStore(name == StoreName.Root ? "ROOT" : "CA",
                                location == StoreLocation.LocalMachine, certificates);

        // What either Disallowed store holds is distrusted wherever else it is.
        var disallowed = new X509Certificate2Collection();
        crypt32.ReadSystemStore("Disallowed", false, disallowed);
        crypt32.ReadSystemStore("Disallowed", true, disallowed);
        foreach (X509Certificate2 refused in disallowed)
            certificates.Remove(refused);
#elif MACOS
        if (name == StoreName.Root)
        {
            ReadCertificateBundles(certificates);

            bool named = GetEnvironmentVariable("SSL_CERT_FILE") != null ||
                         GetEnvironmentVariable("SSL_CERT_DIR") != null;
            var settings = new TrustSettings();
            if (!named && settings.Ready)
                settings.Apply(location == StoreLocation.CurrentUser, certificates);
        }
#else
        if (name == StoreName.Root)
            ReadCertificateBundles(certificates);
#endif
        return certificates;
    }

#if !WINDOWS
    private static void ReadCertificateBundles(X509Certificate2Collection certificates)
    {
        String? named = GetEnvironmentVariable("SSL_CERT_FILE");
        if (named != null)
        {
            ReadCertificateFile(named, certificates);
        }
        else
        {
            String[] candidates = [
                "/etc/ssl/certs/ca-certificates.crt",
                "/etc/pki/tls/certs/ca-bundle.crt",
                "/etc/ssl/ca-bundle.pem",
                "/etc/pki/tls/cacert.pem",
                "/etc/ssl/cert.pem",
            ];
            foreach (String candidate in candidates)
            {
                if (File.Exists(candidate))
                {
                    ReadCertificateFile(candidate, certificates);
                    break;
                }
            }
        }

        String? directories = GetEnvironmentVariable("SSL_CERT_DIR");
        if (directories == null)
            return;
        foreach (String directory in directories.Split(':'))
        {
            if (directory.IsEmpty)
                continue;
            var files = Directory.GetFiles(directory);
            if (!files.Ok)
                continue;
            foreach (String path in files.Value)
                ReadCertificateFile(path, certificates);
        }
    }

    private static void ReadCertificateFile(String path, X509Certificate2Collection certificates)
    {
        var text = File.ReadAllText(path);
        if (text.Ok)
            certificates.ImportFromPemSkippingFailures(text.Value);
    }
#endif
}

#if WINDOWS

/// `CERT_CONTEXT`, of which only the encoded certificate is read.
internal struct CertContext
{
    internal uint EncodingType;
    internal byte* Encoded;
    internal uint EncodedLength;
    internal void* Info;
    internal void* Store;
}

internal delegate __stdcall void* CertOpenStoreFn(byte* provider, uint encodingType,
                                                  nuint cryptProvider, uint flags,
                                                  void* parameter);
internal delegate __stdcall CertContext* CertEnumCertificatesInStoreFn(void* store,
                                                                      CertContext* previous);
internal delegate __stdcall int CertCloseStoreFn(void* store, uint flags);

extern "C" __stdcall
{
    void* LoadLibraryA(byte* name);
    void* GetProcAddress(void* library, byte* name);
}

/// `CERT_STORE_PROV_SYSTEM_A`: a system store named in ANSI.
internal const nuint CertStoreProviderSystemA = 9u;
/// `CERT_SYSTEM_STORE_CURRENT_USER`.
internal const uint CertSystemStoreCurrentUser = 0x10000u;
/// `CERT_SYSTEM_STORE_LOCAL_MACHINE`.
internal const uint CertSystemStoreLocalMachine = 0x20000u;
/// `CERT_STORE_READONLY_FLAG`.
internal const uint CertStoreReadOnly = 0x8000u;
/// `CERT_STORE_OPEN_EXISTING_FLAG`.
internal const uint CertStoreOpenExisting = 0x4000u;
/// `X509_ASN_ENCODING`.
internal const uint X509AsnEncoding = 0x1u;

/// crypt32's three store functions, resolved by name.
///
/// **Loaded rather than linked**, as `Standard.Drawing` loads GDI+: an import
/// here would put crypt32 in every program that reaches this module. Frozen
/// after construction, so it is safe from any thread.
internal threadsafe sealed class Crypt32
{
    private CertOpenStoreFn _open;
    private CertEnumCertificatesInStoreFn _enumerate;
    private CertCloseStoreFn _close;

    /// Whether every symbol resolved.
    internal bool Ready;

    internal Crypt32()
    {
        Ready = false;
        void* library = LoadLibraryA("crypt32.dll".ToPointer());
        if (library == null)
            return;

        bool complete = true;
        _open = (CertOpenStoreFn)FindSymbol(library, "CertOpenStore", &complete);
        _enumerate = (CertEnumCertificatesInStoreFn)FindSymbol(
            library, "CertEnumCertificatesInStore", &complete);
        _close = (CertCloseStoreFn)FindSymbol(library, "CertCloseStore", &complete);
        Ready = complete;
    }

    private void* FindSymbol(void* library, String name, bool* complete)
    {
        void* symbol = GetProcAddress(library, name.ToPointer());
        if (symbol == null)
            *complete = false;
        return symbol;
    }

    /// Every certificate in the system store `storeName` that parses.
    internal void ReadSystemStore(String storeName, bool localMachine,
                                  X509Certificate2Collection certificates)
    {
        uint flags = (localMachine ? CertSystemStoreLocalMachine : CertSystemStoreCurrentUser) |
                     CertStoreReadOnly | CertStoreOpenExisting;
        void* store = _open((byte*)(void*)CertStoreProviderSystemA, 0u, 0u, flags,
                            (void*)storeName.ToPointer());
        if (store == null)
            return;

        // Each call frees the context it is given, so the walk leaks nothing.
        CertContext* context = _enumerate(store, null);
        while (context != null)
        {
            if (((*context).EncodingType & X509AsnEncoding) != 0u)
            {
                var encoded = new byte[(nuint)(*context).EncodedLength];
                for (nuint i = 0u; i < encoded.Length; i++)
                    encoded[i] = (*context).Encoded[i];
                var certificate = X509Certificate2.FromDer(encoded);
                if (certificate.Ok)
                    certificates.Add(certificate.Value);
            }
            context = _enumerate(store, context);
        }
        _close(store, 0u);
    }
}

#endif

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
