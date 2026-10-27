"""Server configuration. All credentials are supplied by the deployment."""
from dataclasses import dataclass
import os

@dataclass(frozen=True)
class Config:
    database: str
    roots: str
    bundle_id: str = 'com.adamhunt.retroguide'
    app_id: int = 6816213425
    product_id: str = 'com.adamhunt.retroguide.pro'
    org_id: int = 24939740
    environment: str = 'Production'

    @classmethod
    def load(cls):
        environment = os.getenv('STORE_ENVIRONMENT', 'Production')
        if environment not in ('Production', 'Sandbox'):
            raise ValueError('Only Apple-signed Production or Sandbox data is supported')
        return cls(os.environ['ATTRIBUTION_DATABASE'], os.environ['APPLE_ROOT_CERTIFICATES'],
                   environment=environment)
