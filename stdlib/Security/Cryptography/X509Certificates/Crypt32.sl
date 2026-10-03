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

#if WINDOWS

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
