// SPDX-License-Identifier: 0BSD
//
// The platform's root store: crypt32's ROOT on Windows, the system bundle
// elsewhere. What it holds differs by machine, so only its shape is printed.
module X509StoreCase;

import Standard.Console;
import Standard.Security.Cryptography.X509Certificates;

public int Main()
{
    X509Store roots = X509Store.Open(StoreName.Root);
    nuint count = roots.Certificates.Count;
    Console.WriteLine($"more than 20 roots: {count > 20u}");

    nuint readBack = 0u;
    nuint selfIssued = 0u;
    foreach (X509Certificate2 root in roots.Certificates)
    {
        var again = X509Certificate2.FromDer(root.RawData);
        if (again.Ok && again.Value.Equals(root) && root.Thumbprint.ByteLength() == 40u)
            readBack++;
        if (root.IsSelfIssued)
            selfIssued++;
    }
    Console.WriteLine($"every root reads back: {readBack == count}");
    Console.WriteLine($"most roots are self-issued: {selfIssued * 2u > count}");

    X509Store again = X509Store.Open(StoreName.Root);
    Console.WriteLine($"opened twice, the same: {again.Certificates.Count == count}");

    X509Store authorities = X509Store.Open(StoreName.CertificateAuthority);
    Console.WriteLine($"intermediates open: {authorities.Name == StoreName.CertificateAuthority}");
    return 0;
}
