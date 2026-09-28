#!/bin/bash
# Makes the x509 test PKI. Run on the Linux box; everything lands in ~/x509-pki.
set -e
rm -rf ~/x509-pki
mkdir -p ~/x509-pki
cd ~/x509-pki

cat > ext.cnf <<'EOF'
[root]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash

[inter]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always

[subca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always

[noca]
basicConstraints = critical, CA:FALSE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always

[noku]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always

[nc]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
nameConstraints = critical, permitted;DNS:example.com, permitted;IP:192.0.2.0/255.255.255.0, excluded;DNS:bad.example.com, excluded;IP:2001:db8::/ffff:ffff::

[good]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:www.example.com, DNS:example.com

[wrongeku]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:client.example.com

[badku]
basicConstraints = critical, CA:FALSE
keyUsage = critical, cRLSign
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:badku.example.com

[wildcard]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:*.example.com, DNS:*.a.example.com

[ip]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = IP:192.0.2.1, IP:2001:db8::1, URI:https://example.com/path, email:admin@example.com, DNS:ip.example.com

[critical]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:critical.example.com
1.3.6.1.4.1.55555.1 = critical, DER:05:00

[ncgood]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:www.example.com, DNS:*.example.com, IP:192.0.2.5

[ncother]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:www.example.com, DNS:www.example.org

[ncexcluded]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:bad.example.com

[ncip]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:ip.example.com, IP:198.51.100.7

[plainleaf]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:leaf.example.com
EOF

key() { openssl genpkey -algorithm "$@"; }

# root name subject extsection  (self-signed)
selfsigned() {
    openssl req -utf8 -new -key "$1.key" -subj "$2" -out "$1.csr"
    openssl x509 -req -in "$1.csr" -key "$1.key" -set_serial "$3" \
        -not_before 20260101000000Z -not_after 20460101000000Z \
        -extfile ext.cnf -extensions root -out "$1.pem"
}

# issue name subject issuer serial section [notBefore notAfter]
issue() {
    local nb=${6:-20260101000000Z}
    local na=${7:-20360101000000Z}
    openssl req -utf8 -new -key "$1.key" -subj "$2" -out "$1.csr"
    openssl x509 -req -in "$1.csr" -CA "$3.pem" -CAkey "$3.key" -set_serial "$4" \
        -not_before "$nb" -not_after "$na" \
        -extfile ext.cnf -extensions "$5" -out "$1.pem"
}

for name in root rootb inter noca sub noku nc caa cab; do
    key ed25519 -out $name.key
done
for name in good expired notyet wrongeku badku wildcard ip critical undernoca undersub undernoku \
            ncgood ncother ncexcluded ncip cyclic; do
    key ed25519 -out $name.key
done

selfsigned root "/C=US/O=Stainless, Test/CN=Stainless Test Root" 0x01
selfsigned rootb "/C=US/O=Stainless Test/CN=Stainless Cross Root" 0x02

issue inter "/C=US/O=Stainless Test/CN=Stainless Test Intermediate" root 0x1000 inter
# The same name and key, issued by the other root.
openssl x509 -req -in inter.csr -CA rootb.pem -CAkey rootb.key -set_serial 0x2000 \
    -not_before 20260101000000Z -not_after 20360101000000Z \
    -extfile ext.cnf -extensions inter -out intercross.pem

issue noca "/C=US/O=Stainless Test/CN=Not A CA" root 0x1001 noca
issue sub "/C=US/O=Stainless Test/CN=Too Deep" inter 0x1002 subca
issue noku "/C=US/O=Stainless Test/CN=No Cert Sign" root 0x1003 noku
issue nc "/C=US/O=Stainless Test/CN=Constrained" root 0x1004 nc

# Two CAs that issue each other, and nothing trusted above them.
openssl req -utf8 -new -key caa.key -subj "/CN=Cycle A" -out caa.csr
openssl req -utf8 -new -key cab.key -subj "/CN=Cycle B" -out cab.csr
openssl req -x509 -key cab.key -subj "/CN=Cycle B" -set_serial 7 -not_before 20260101000000Z -not_after 20360101000000Z -out cabself.pem
openssl x509 -req -in caa.csr -CA cabself.pem -CAkey cab.key -set_serial 0x3001 \
    -not_before 20260101000000Z -not_after 20360101000000Z -extfile ext.cnf -extensions subca -out caa.pem
openssl x509 -req -in cab.csr -CA caa.pem -CAkey caa.key -set_serial 0x3002 \
    -not_before 20260101000000Z -not_after 20360101000000Z -extfile ext.cnf -extensions subca -out cab.pem
issue cyclic "/CN=cyclic.example.com" caa 0x3003 plainleaf 20260101000000Z 20280101000000Z

issue good "/C=US/ST=Texas/L=Austin/O=Example Ünïcode/OU=Web/CN=www.example.com" inter 0x0123456789abcdef good 20260101000000Z 20280101000000Z
issue expired "/CN=expired.example.com" inter 0x10 plainleaf 20200101000000Z 20210101000000Z
issue notyet "/CN=notyet.example.com" inter 0x11 plainleaf 20300101000000Z 20310101000000Z
issue wrongeku "/CN=client.example.com" inter 0x12 wrongeku 20260101000000Z 20280101000000Z
issue badku "/CN=badku.example.com" inter 0x13 badku 20260101000000Z 20280101000000Z
issue wildcard "/CN=*.example.com" inter 0x14 wildcard 20260101000000Z 20280101000000Z
issue ip "/CN=192.0.2.1" inter 0x15 ip 20260101000000Z 20280101000000Z
issue critical "/CN=critical.example.com" inter 0x16 critical 20260101000000Z 20280101000000Z
issue undernoca "/CN=leaf.example.com" noca 0x17 plainleaf 20260101000000Z 20280101000000Z
issue undersub "/CN=leaf.example.com" sub 0x18 plainleaf 20260101000000Z 20280101000000Z
issue undernoku "/CN=leaf.example.com" noku 0x19 plainleaf 20260101000000Z 20280101000000Z
issue ncgood "/CN=www.example.com" nc 0x1a ncgood 20260101000000Z 20280101000000Z
issue ncother "/CN=www.example.org" nc 0x1b ncother 20260101000000Z 20280101000000Z
issue ncexcluded "/CN=bad.example.com" nc 0x1c ncexcluded 20260101000000Z 20280101000000Z
issue ncip "/CN=ip.example.com" nc 0x1d ncip 20260101000000Z 20280101000000Z

# RSA and P-256, parse and chain.
key RSA -pkeyopt rsa_keygen_bits:2048 -out rsaroot.key
key RSA -pkeyopt rsa_keygen_bits:2048 -out rsaleaf.key
key EC -pkeyopt ec_paramgen_curve:P-256 -out p256root.key
key EC -pkeyopt ec_paramgen_curve:P-256 -out p256leaf.key
selfsigned rsaroot "/C=US/O=Stainless Test/CN=Stainless RSA Root" 0x40
issue rsaleaf "/CN=rsa.example.com" rsaroot 0x41 good 20260101000000Z 20280101000000Z
selfsigned p256root "/C=US/O=Stainless Test/CN=Stainless P-256 Root" 0x50
issue p256leaf "/CN=p256.example.com" p256root 0x51 good 20260101000000Z 20280101000000Z

# Real ones, from another encoder.
cp /etc/ssl/certs/ISRG_Root_X1.pem isrgx1.pem
cp /etc/ssl/certs/ISRG_Root_X2.pem isrgx2.pem
curl -sS -o e6.pem https://letsencrypt.org/certs/2024/e6.pem
curl -sS -o r10.pem https://letsencrypt.org/certs/2024/r10.pem

for f in *.pem; do
    openssl x509 -in "$f" -outform DER -out "${f%.pem}.der"
done

{
for f in *.pem; do
    echo "== $f"
    openssl x509 -in "$f" -noout -fingerprint -sha1
    openssl x509 -in "$f" -noout -fingerprint -sha256
    openssl x509 -in "$f" -noout -serial -subject -issuer -dates -nameopt RFC2253
done
} > fingerprints.txt

# RSA-PSS over SHA-384 with a 48-byte salt, and a leaf the name constraints allow.
key RSA -pkeyopt rsa_keygen_bits:2048 -out rsapss.key
openssl req -utf8 -new -key rsapss.key -subj "/CN=pss.example.com" -out rsapss.csr
openssl x509 -req -in rsapss.csr -CA rsaroot.pem -CAkey rsaroot.key -set_serial 0x42 \
    -not_before 20260101000000Z -not_after 20280101000000Z -extfile ext.cnf -extensions good \
    -sha384 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:48 -sigopt rsa_mgf1_md:sha384 \
    -out rsapss.pem
cat >> ext.cnf <<'EOF'

[ncok]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:www.example.com, DNS:api.example.com, IP:192.0.2.5
EOF
key ed25519 -out ncok.key
issue ncok "/CN=www.example.com" nc 0x1e ncok 20260101000000Z 20280101000000Z

echo verify:
openssl verify -CAfile root.pem -untrusted inter.pem good.pem
openssl verify -CAfile isrgx2.pem e6.pem
openssl verify -CAfile isrgx1.pem r10.pem
ls
