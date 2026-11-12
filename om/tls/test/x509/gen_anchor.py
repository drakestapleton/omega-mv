# SPDX-License-Identifier: Apache-2.0
# TEST INSTRUMENT ONLY (Python as a fixture builder; never on the product path): write the trust-anchor
# key-policy fixtures of review omega-mv-tlscap-35d44b5a finding 1 into vectors/anchor/ with Python
# cryptography (>= 41). Each root is a valid self-signed CA (operator-installed: it is only in its own
# store file), each leaf is a valid EC P-256 server certificate signed by that root with
# sha256WithRSAEncryption. Fresh random keys each run; private keys are never written; cases.txt does
# not depend on key bytes.
#   rootA<bits>e<e>  storeA<bits>e<e>.pem  lA<bits>e<e>.der    for (bits, e) in ROOTS below
#   1024/2^32+1  the finding: a weak modulus whose exponent is over the presented-key exponent policy
#                (3 .. 2^32-1), which used to be added into the bit count the anchor check reads
#   1024/65537   control: a weak modulus with the usual exponent
#   2048/65537   control: an adequate root
#   2048/2^32+1  control: an adequate modulus with an exponent over 32 bits (anchors need only >= 2048
#                bits; the presented-key exponent policy does not apply to them)
# Usage: python3 gen_anchor.py
import datetime
import math
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, "vectors", "anchor")
os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    os.remove(os.path.join(out, f))
T0, T1 = datetime.datetime(2026, 1, 1), datetime.datetime(2027, 1, 1)
R0, R1 = datetime.datetime(2020, 1, 1), datetime.datetime(2051, 1, 1)
ROOTS = [(1024, 4294967297), (1024, 65537), (2048, 65537), (2048, 4294967297)]


def die(msg):
    sys.exit("gen_anchor.py: " + msg)


def name(cn):
    return x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, "omtls test"),
                      x509.NameAttribute(NameOID.COMMON_NAME, cn)])


def rsa_with_e(bits, e):
    """an RSA key of exactly `bits` bits with public exponent e (odd, coprime to lambda)"""
    while True:
        k = rsa.generate_private_key(public_exponent=65537, key_size=bits)
        p, q = k.private_numbers().p, k.private_numbers().q
        lam = (p - 1) * (q - 1) // math.gcd(p - 1, q - 1)
        if math.gcd(e, lam) == 1:
            d = pow(e, -1, lam)
            pub = rsa.RSAPublicNumbers(e, p * q)
            return rsa.RSAPrivateNumbers(p, q, d, rsa.rsa_crt_dmp1(d, p), rsa.rsa_crt_dmq1(d, q),
                                         rsa.rsa_crt_iqmp(p, q), pub).private_key()


for bits, e in ROOTS:
    tag = "%de%d" % (bits, e)
    rk = rsa_with_e(bits, e)
    if rk.public_key().key_size != bits or rk.public_key().public_numbers().e != e:
        die("root %s: got %d bits e=%d" % (tag, rk.public_key().key_size, rk.public_key().public_numbers().e))
    rn = name("rootA" + tag)
    root = (x509.CertificateBuilder().subject_name(rn).issuer_name(rn).public_key(rk.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(R0).not_valid_after(R1)
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(rk.public_key()), critical=False)
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), critical=True)
            .sign(rk, hashes.SHA256()))
    lk = ec.generate_private_key(ec.SECP256R1())
    leaf = (x509.CertificateBuilder().subject_name(name("lA" + tag)).issuer_name(rn).public_key(lk.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(T0).not_valid_after(T1)
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(lk.public_key()), critical=False)
            .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(rk.public_key()), critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(True, False, False, False, False, False, False, False, False), critical=True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .add_extension(x509.SubjectAlternativeName([x509.DNSName("www.example.test"),
                                                        x509.DNSName("example.test")]), critical=False)
            .sign(rk, hashes.SHA256()))
    # the leaf really is signed by the root (a failure here is a generator defect, not a test result)
    try:
        leaf.verify_directly_issued_by(root)
    except Exception as x:  # noqa: BLE001 - any verification error is a generator defect
        die("leaf %s does not verify under its root: %s" % (tag, x))
    with open(os.path.join(out, "rootA%s.der" % tag), "wb") as f:
        f.write(root.public_bytes(serialization.Encoding.DER))
    with open(os.path.join(out, "storeA%s.pem" % tag), "wb") as f:
        f.write(root.public_bytes(serialization.Encoding.PEM))
    with open(os.path.join(out, "lA%s.der" % tag), "wb") as f:
        f.write(leaf.public_bytes(serialization.Encoding.DER))
print("anchor fixtures:", len(os.listdir(out)))
