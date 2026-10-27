"""Ingestion only. Reports and credentials are never served on the public API."""
import re
import sqlite3
from uuid import UUID
from fastapi import FastAPI, Header, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from .apple import Apple
from .config import Config
from .database import Database

class Payload(BaseModel):
    model_config = ConfigDict(extra='forbid')

class Installation(Payload):
    signedAppTransaction: str = Field(min_length=20, max_length=32768)
    attributionToken: str | None = Field(default=None, min_length=10, max_length=16384)

class Purchase(Payload):
    signedTransaction: str = Field(min_length=20, max_length=32768)

class Notification(Payload):
    signedPayload: str = Field(min_length=20, max_length=65536)

def create_app(config=None, apple=None, database=None):
    config = config or Config.load()
    apple = apple or Apple(config)
    database = database or Database(config.database)
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, error):
        # Pydantic's normal error response can include tokens from the input.
        return JSONResponse({'error': 'Invalid request'}, status_code=422)

    from .limits import BodyLimit
    app.add_middleware(BodyLimit)

    def credentials(authorization):
        if not authorization or not re.fullmatch(r'Bearer [a-f0-9]{64}', authorization):
            raise HTTPException(401, 'Installation authorization required')
        return authorization[7:]

    @app.get('/health')
    def health():
        return {'status':'ok', 'environment':config.environment}

    @app.post('/v1/installations/{identifier}')
    def installation(identifier: UUID, body: Installation, authorization: str | None = Header(default=None)):
        secret = credentials(authorization)
        try:
            signed_app = apple.installation(body.signedAppTransaction)
        except Exception:
            raise HTTPException(422, 'App transaction verification failed') from None
        try:
            row = database.register(str(identifier), secret, signed_app)
        except PermissionError:
            raise HTTPException(403, 'Installation identity mismatch') from None
        if body.attributionToken and row['attribution'] is None:
            try:
                payload = apple.attribution(body.attributionToken)
                database.attribute(str(identifier), body.attributionToken, payload)
            except sqlite3.IntegrityError:
                raise HTTPException(409, 'Attribution token already used') from None
            except Exception:
                raise HTTPException(503, 'Attribution temporarily unavailable') from None
        return {'accepted':True, 'attributionResolved':bool(body.attributionToken or row['attribution'])}

    @app.post('/v1/installations/{identifier}/purchases')
    def purchase(identifier: UUID, body: Purchase, authorization: str | None = Header(default=None)):
        try:
            database.authenticate(str(identifier), credentials(authorization))
        except PermissionError:
            raise HTTPException(403, 'Installation identity mismatch') from None
        try:
            tx = apple.transaction(body.signedTransaction)
        except Exception:
            raise HTTPException(422, 'Purchase verification failed') from None
        # Attribution uses only Apple's signed account token or app identity,
        # never the upload URL's installation ID. Restores cannot reassign sales.
        database.purchase(tx)
        return {'accepted':True}

    @app.post('/v1/notifications/apple')
    def notification(body: Notification):
        try:
            event = apple.notification(body.signedPayload)
            if not event.notificationUUID:
                raise ValueError('Missing notification ID')
            if event.data and event.data.signedTransactionInfo:
                tx = apple.transaction(event.data.signedTransactionInfo)
            else:
                tx = None
        except Exception:
            raise HTTPException(422, 'Notification verification failed') from None
        if tx is not None:
            database.purchase(tx, event.notificationUUID)
        return {'accepted':True}
    return app
