"""Apple-signed transaction verification and AdServices exchange."""
from pathlib import Path
import time
import httpx
from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier

class Apple:
    def __init__(self, config):
        roots = [p.read_bytes() for p in Path(config.roots).glob('*.cer')]
        if not roots:
            raise ValueError('Apple root certificates are required')
        self.config = config
        self.verifier = SignedDataVerifier(roots, True, Environment(config.environment),
                                          config.bundle_id, config.app_id)

    def transaction(self, signed):
        tx = self.verifier.verify_and_decode_signed_transaction(signed)
        if tx.productId != self.config.product_id or not tx.transactionId or not tx.originalTransactionId:
            raise ValueError('Unexpected product or missing transaction identity')
        return tx

    def installation(self, signed):
        return self.verifier.verify_and_decode_app_transaction(signed)

    def notification(self, signed):
        return self.verifier.verify_and_decode_notification(signed)

    def attribution(self, token):
        with httpx.Client(timeout=10, follow_redirects=False) as client:
            for attempt in range(3):
                response = client.post('https://api-adservices.apple.com/api/v1/',
                                       content=token, headers={'Content-Type': 'text/plain'})
                if response.status_code == 404 and attempt < 2:
                    time.sleep(5)
                    continue
                response.raise_for_status()
                payload = response.json()
                if type(payload.get('attribution')) is not bool:
                    raise ValueError('Invalid attribution response')
                if payload['attribution'] and payload.get('orgId') != self.config.org_id:
                    raise ValueError('Attribution does not belong to this advertising organization')
                return payload
