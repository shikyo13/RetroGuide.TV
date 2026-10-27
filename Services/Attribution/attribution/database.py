"""Idempotent storage for installations, signed purchases and report snapshots."""
from contextlib import contextmanager
import hashlib
import json
import os
import sqlite3
import time

SCHEMA = '''
CREATE TABLE IF NOT EXISTS installations (
 id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, first_seen INTEGER NOT NULL,
 app_identity TEXT, attribution TEXT, token_hash TEXT UNIQUE
);
CREATE TABLE IF NOT EXISTS purchases (
 environment TEXT NOT NULL, transaction_id TEXT NOT NULL, original_id TEXT NOT NULL,
 account_token TEXT, app_identity TEXT, purchased_at INTEGER NOT NULL,
 signed_at INTEGER NOT NULL, price INTEGER, currency TEXT, ownership TEXT NOT NULL,
 revoked_at INTEGER, PRIMARY KEY(environment, transaction_id)
);
CREATE TABLE IF NOT EXISTS notifications (id TEXT PRIMARY KEY, received_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS reports (
 day TEXT NOT NULL, level TEXT NOT NULL, object_key TEXT NOT NULL,
 currency TEXT NOT NULL, spend TEXT NOT NULL, impressions INTEGER NOT NULL,
 taps INTEGER NOT NULL, installs INTEGER, metadata TEXT NOT NULL,
 retrieved_at INTEGER NOT NULL, PRIMARY KEY(day,level,object_key,currency)
);
'''

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def enum_value(value):
    return getattr(value, 'value', value)

class Database:
    def __init__(self, path):
        self.path = path
        with self.connection() as db:
            db.executescript(SCHEMA)
        os.chmod(self.path, 0o600)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            db.execute('PRAGMA journal_mode=WAL')
            with db:
                yield db
        finally:
            db.close()

    def register(self, identifier, secret, app):
        identity = getattr(app, 'appTransactionId', None)
        identity = digest(str(identity)) if identity else None
        with self.connection() as db:
            db.execute('INSERT OR IGNORE INTO installations(id,secret_hash,first_seen,app_identity) VALUES(?,?,?,?)',
                       (identifier, digest(secret), int(time.time()*1000), identity))
            row = db.execute('SELECT * FROM installations WHERE id=?', (identifier,)).fetchone()
            import hmac
            if not hmac.compare_digest(row['secret_hash'], digest(secret)):
                raise PermissionError('Installation credentials do not match')
            if row['app_identity'] != identity:
                raise PermissionError('Installation identity changed')
            return dict(row)

    def authenticate(self, identifier, secret):
        import hmac
        with self.connection() as db:
            row = db.execute('SELECT * FROM installations WHERE id=?', (identifier,)).fetchone()
        if row is None or not hmac.compare_digest(row['secret_hash'], digest(secret)):
            raise PermissionError('Installation credentials do not match')
        return dict(row)

    def attribute(self, identifier, token, payload):
        # A token may not credit two installations; resolved attribution is immutable.
        with self.connection() as db:
            db.execute('UPDATE installations SET attribution=?,token_hash=? WHERE id=? AND attribution IS NULL',
                       (json.dumps(payload), digest(token), identifier))

    def purchase(self, tx, notification_id=None):
        identity = getattr(tx, 'appTransactionId', None)
        values = (enum_value(tx.environment), tx.transactionId, tx.originalTransactionId,
                  str(tx.appAccountToken).lower() if tx.appAccountToken else None,
                  digest(str(identity)) if identity else None, tx.purchaseDate, tx.signedDate,
                  tx.price, tx.currency, enum_value(tx.inAppOwnershipType), tx.revocationDate)
        if not tx.purchaseDate or not tx.signedDate or not values[9]:
            raise ValueError('Incomplete transaction')
        with self.connection() as db:
            if notification_id:
                if db.execute('SELECT 1 FROM notifications WHERE id=?', (notification_id,)).fetchone():
                    return
                db.execute('INSERT INTO notifications VALUES(?,?)', (notification_id, int(time.time())))
            db.execute('''INSERT INTO purchases VALUES(?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(environment,transaction_id) DO UPDATE SET
                signed_at=excluded.signed_at,price=excluded.price,currency=excluded.currency,
                ownership=excluded.ownership,revoked_at=excluded.revoked_at,
                account_token=COALESCE(purchases.account_token,excluded.account_token),
                app_identity=COALESCE(purchases.app_identity,excluded.app_identity)
                WHERE excluded.signed_at>purchases.signed_at''', values)
