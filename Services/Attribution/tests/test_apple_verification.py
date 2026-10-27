from pathlib import Path
from datetime import datetime, timedelta, timezone
import base64
import httpx
import jwt
import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from attribution.apple import Apple
from attribution.config import Config

ROOTS = Path(__file__).parent/'certificates'

def verifier():
    return Apple(Config(':unused:',str(ROOTS)))

@pytest.mark.parametrize('method', ['transaction','installation','notification'])
def test_real_apple_verifier_rejects_unsigned_and_symmetric_tokens(method):
    apple = verifier()
    for algorithm,key in [('none',None),('HS256','attacker-controlled-secret-that-is-long-enough')]:
        token = jwt.encode({'bundleId':apple.config.bundle_id,'environment':'Production',
                            'productId':apple.config.product_id,'transactionId':'123'},key,algorithm=algorithm)
        with pytest.raises(Exception): getattr(apple,method)(token)

def test_real_apple_verifier_rejects_attacker_signed_certificate_chain():
    apple = verifier()
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Untrusted test signer')])
    now = datetime.now(timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(1).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=1))
            .sign(key,hashes.SHA256()))
    encoded = base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode()
    signed = jwt.encode({'bundleId':apple.config.bundle_id,'environment':'Production',
                         'productId':apple.config.product_id,'transactionId':'123'},key,algorithm='ES256',
                        headers={'x5c':[encoded,encoded,encoded]})
    with pytest.raises(Exception): apple.transaction(signed)

def test_adservices_retry_and_developer_payload_rejection(monkeypatch):
    apple = verifier()
    calls = []
    waits = []
    def handler(request):
        calls.append(request)
        if len(calls)<3: return httpx.Response(404)
        return httpx.Response(200,json={'attribution':True,'orgId':555555555})
    client = httpx.Client(transport=httpx.MockTransport(handler))
    monkeypatch.setattr('attribution.apple.httpx.Client',lambda **kwargs:client)
    monkeypatch.setattr('attribution.apple.time.sleep',waits.append)
    with pytest.raises(ValueError): apple.attribution('token')
    assert waits == [5,5]
    assert len(calls) == 3
