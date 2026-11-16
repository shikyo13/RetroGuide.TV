from types import SimpleNamespace as NS
from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from attribution.api import create_app
from attribution.config import Config
from attribution.database import Database
from attribution.reporting import revenue_report

SECRET = 'a' * 64
SIGNED = 'signed-fixture-placeholder'

class FakeApple:
    def __init__(self):
        self.tx = transaction()
        self.failure = False
    def installation(self, signed):
        if signed != SIGNED: raise ValueError()
        return NS(appTransactionId='app-1')
    def transaction(self, signed):
        if signed != SIGNED: raise ValueError()
        return self.tx
    def attribution(self, token):
        if self.failure: raise OSError()
        return {'attribution':True, 'orgId':24939740, 'campaignId':12, 'adGroupId':34, 'keywordId':56}
    def notification(self, signed):
        if signed != SIGNED: raise ValueError()
        return NS(notificationUUID='notification-1', data=NS(signedTransactionInfo=SIGNED))

def transaction(**kwargs):
    fields = dict(environment='Production', transactionId='1', originalTransactionId='1',
                  appAccountToken=None, appTransactionId='app-1', purchaseDate=1000,
                  signedDate=2000, price=9990, currency='USD', inAppOwnershipType='PURCHASED', revocationDate=None)
    fields.update(kwargs)
    return NS(**fields)

@pytest.fixture
def setup(tmp_path):
    db = Database(str(tmp_path/'db.sqlite'))
    apple = FakeApple()
    client = TestClient(create_app(Config(str(tmp_path/'db.sqlite'),str(tmp_path)),apple,db))
    identifier = str(uuid4())
    return db,apple,client,identifier

def register(client, identifier, **extra):
    return client.post(f'/v1/installations/{identifier}', headers={'Authorization':f'Bearer {SECRET}'},
                       json={'signedAppTransaction':SIGNED, **extra})

def upload(client, identifier, signed=SIGNED):
    return client.post(f'/v1/installations/{identifier}/purchases',
                       headers={'Authorization':f'Bearer {SECRET}'},json={'signedTransaction':signed})

def test_valid_body_survives_middleware_and_duplicate_restore_counts_once(setup):
    db,apple,client,identifier = setup
    assert register(client,identifier,attributionToken='token-12345').status_code == 200
    apple.tx.appAccountToken = identifier
    assert upload(client,identifier).status_code == 200
    assert upload(client,identifier).status_code == 200
    group = revenue_report(db,0,3000)['groups'][0]
    assert group['purchases'] == 1
    assert group['keywordId'] == 56
    assert group['netSales'] == '9.99'

def test_uploading_another_users_purchase_cannot_claim_their_revenue(setup):
    db,apple,client,identifier = setup
    register(client,identifier,attributionToken='token-12345')
    apple.tx.appAccountToken = str(uuid4())
    upload(client,identifier)
    assert revenue_report(db,0,3000)['groups'][0]['campaignId'] is None

def test_attribution_failure_does_not_prevent_purchase_ingestion(setup):
    db,apple,client,identifier = setup
    apple.failure = True
    assert register(client,identifier,attributionToken='token-12345').status_code == 503
    assert upload(client,identifier).status_code == 200
    assert len(revenue_report(db,0,3000)['groups']) == 1

def test_bad_signatures_and_credentials_are_rejected_without_echoing_secrets(setup):
    db,apple,client,identifier = setup
    register(client,identifier)
    assert upload(client,identifier,'invalid-signature-12345').status_code == 422
    response = client.post(f'/v1/installations/{identifier}/purchases',
                           headers={'Authorization':f'Bearer {"b"*64}'},json={'signedTransaction':SIGNED})
    assert response.status_code == 403
    response = client.post(f'/v1/installations/{identifier}',json={'signedAppTransaction':'secret'})
    assert response.status_code == 422
    assert 'secret' not in response.text
    assert revenue_report(db,0,3000)['groups'] == []

def test_body_limit(setup):
    _,_,client,identifier = setup
    assert client.post(f'/v1/installations/{identifier}',content=b'x'*100000).status_code == 413

def test_refund_old_restore_and_refund_reversal(setup):
    db,apple,client,identifier = setup
    register(client,identifier)
    upload(client,identifier)
    apple.tx = transaction(signedDate=4000,revocationDate=3500)
    assert client.post('/v1/notifications/apple',json={'signedPayload':SIGNED}).status_code == 200
    assert client.post('/v1/notifications/apple',json={'signedPayload':SIGNED}).status_code == 200
    apple.tx = transaction()
    upload(client,identifier)
    group = revenue_report(db,0,3000)['groups'][0]
    assert group['refunds'] == 1 and group['netSales'] == '0.00'
    apple.tx = transaction(signedDate=5000)
    upload(client,identifier)
    assert revenue_report(db,0,3000)['groups'][0]['netSales'] == '9.99'

def test_currency_environment_family_and_unknown_price_are_not_combined(setup):
    db,_,_,_ = setup
    db.purchase(transaction())
    db.purchase(transaction(transactionId='2',price=None,currency='EUR'))
    db.purchase(transaction(transactionId='3',inAppOwnershipType='FAMILY_SHARED'))
    db.purchase(transaction(transactionId='4',environment='Sandbox'))
    groups = revenue_report(db,0,3000)['groups']
    assert sum(g['purchases'] for g in groups) == 2
    assert {g['currency'] for g in groups} == {'USD','EUR'}
    assert next(g for g in groups if g['currency']=='EUR')['unknownPricePurchases'] == 1

def test_attribution_is_immutable_and_token_cannot_credit_two_installations(setup):
    db,apple,client,identifier = setup
    register(client,identifier,attributionToken='token-12345')
    assert register(client,str(uuid4()),attributionToken='token-12345').status_code == 409
    apple.failure = True
    assert register(client,identifier,attributionToken='token-99999').status_code == 200

def test_cross_device_uses_signed_identity_and_only_unambiguous_prior_acquisition(setup):
    db,apple,client,identifier = setup
    register(client,identifier,attributionToken='token-12345')
    with db.connection() as conn:
        conn.execute('UPDATE installations SET first_seen=500')
    apple.tx.appAccountToken = str(uuid4())
    upload(client,identifier)
    assert revenue_report(db,0,3000)['groups'][0]['campaignId'] == 12
    # A different signed account cannot inherit the acquisition.
    db.purchase(transaction(transactionId='2',appTransactionId='different-account'))
    assert len(revenue_report(db,0,3000)['groups']) == 2
    other = str(uuid4())
    db.register(other,SECRET,NS(appTransactionId='app-1'))
    db.attribute(other,'other-token',{'attribution':True,'campaignId':99})
    with db.connection() as conn:
        conn.execute('UPDATE installations SET first_seen=500')
    # Conflicting eligible campaigns must not be guessed or double-counted.
    groups = revenue_report(db,0,3000)['groups']
    assert len(groups) == 1 and groups[0]['campaignId'] is None and groups[0]['purchases']==2

def test_changed_apple_account_does_not_inherit_previous_accounts_campaign(setup):
    db,apple,client,identifier = setup
    register(client,identifier,attributionToken='token-12345')
    apple.tx = transaction(appAccountToken=identifier,appTransactionId='different-account')
    upload(client,identifier)
    assert revenue_report(db,0,3000)['groups'][0]['campaignId'] is None

def test_usage_needs_a_registered_installation_and_keeps_only_known_events(setup):
    from datetime import datetime, timezone
    from attribution.usage import usage_report
    db,apple,client,identifier = setup
    today = datetime.now(timezone.utc).date()
    body = {'platform':'iPhone', 'version':'1.9', 'events':[
        {'name':'setup', 'detail':'welcome', 'day':today.isoformat()},
        {'name':'setup', 'detail':'welcome', 'day':today.isoformat()},
        {'name':'watched', 'detail':'plex', 'day':today.isoformat()},
        {'name':'something-newer', 'detail':'', 'day':today.isoformat()},
        {'name':'proViewed', 'detail':'a title', 'day':today.isoformat()},
        {'name':'proViewed', 'detail':'', 'day':'1999-01-01'}]}
    post = lambda: client.post(f'/v1/installations/{identifier}/usage',
                               headers={'Authorization':f'Bearer {SECRET}'}, json=body)
    assert post().status_code == 403
    assert register(client,identifier).status_code == 200
    assert post().json() == {'accepted':2}
    assert post().status_code == 200
    funnel = usage_report(db,today,today)['firstSeenInRange']['iPhone']
    assert funnel['installations'] == 1 and funnel['setup:welcome'] == 1 and funnel['watched'] == 1
    assert funnel['proViewed'] == 0

def test_usage_reasons_match_the_app():
    """The app's reason names must be the service's, or its events are dropped."""
    import re
    from pathlib import Path
    from attribution.usage import REASONS, PROBLEMS
    swift = (Path(__file__).parents[3] / 'Packages/RetroGuideKit/Sources/RetroGuideKit/Attribution/UsageEvent.swift').read_text()
    def cases(enum):
        body = swift.split(f'enum {enum}:')[1].split('\n    }\n')[0]
        return set(re.findall(r'^\s+case (\w+)\s*$', body, re.M))
    assert cases('FailureReason') == REASONS
    assert cases('SetupProblem') == PROBLEMS

def test_usage_report_says_why_setup_stopped(setup):
    from datetime import datetime, timezone
    from attribution.usage import usage_report
    db,apple,client,identifier = setup
    today = datetime.now(timezone.utc).date().isoformat()
    assert register(client,identifier).status_code == 200
    body = {'platform':'iPhone', 'version':'1.9.1', 'events':[
        {'name':'setup', 'detail':'welcome', 'day':today},
        {'name':'setupProblem', 'detail':'plexNoServers', 'day':today},
        {'name':'libraryFailed', 'detail':'timeout', 'day':today},
        {'name':'setupFailed', 'detail':'a message', 'day':today}]}
    response = client.post(f'/v1/installations/{identifier}/usage',
                           headers={'Authorization':f'Bearer {SECRET}'}, json=body)
    assert response.json() == {'accepted':3}
    report = usage_report(db, datetime.now(timezone.utc).date(), datetime.now(timezone.utc).date())
    assert report['whyFirstSeenInRange'] == {'libraryFailed':{'timeout':1}, 'setupProblem':{'plexNoServers':1}}
    assert report['firstSeenInRange']['iPhone']['setupProblem'] == 1

def test_country_and_language_split_reports_without_costing_events(setup):
    from datetime import datetime, timezone
    from attribution.usage import usage_report
    db,apple,client,identifier = setup
    today = datetime.now(timezone.utc).date()
    assert register(client,identifier).status_code == 200
    post = lambda **extra: client.post(f'/v1/installations/{identifier}/usage',
        headers={'Authorization':f'Bearer {SECRET}'},
        json={'platform':'iPad', 'version':'1.9.2',
              'events':[{'name':'setup', 'detail':'welcome', 'day':today.isoformat()}], **extra})
    # Older apps send neither; a malformed value is ignored, never the events.
    assert post().json() == {'accepted':1}
    assert post(storefront='Germany', language='xx').json() == {'accepted':1}
    report = usage_report(db,today,today)
    assert report['firstSeenByStorefront'] == {'unknown': report['firstSeenInRange']['all']}
    assert post(storefront='DEU', language='de').json() == {'accepted':1}
    report = usage_report(db,today,today)
    assert report['firstSeenByStorefront']['DEU']['setup:welcome'] == 1
    assert report['firstSeenByLanguage']['de']['installations'] == 1
    # Purchases carry the App Store country Apple signed into them.
    apple.tx = transaction(appAccountToken=identifier, storefront='DEU', currency='EUR')
    assert upload(client,identifier).status_code == 200
    assert revenue_report(db,0,3000)['byStorefront'] == [
        {'storefront':'DEU', 'currency':'EUR', 'purchases':1, 'refunds':0}]
