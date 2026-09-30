// SPDX-License-Identifier: 0BSD
// The test's way into the module: this file joins Standard.Security.Cryptography,
// so it reaches AES-GCM's length check.
module Standard.Security.Cryptography;

public bool AreGcmTestLengthsAllowed(ulong textLength, ulong associatedLength) =>
    AesGcm.AreLengthsAllowed(textLength, associatedLength);
