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
