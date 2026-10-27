import json
import httpx
import pytest
from attribution.ads_reports import AdsReports
from attribution.database import Database

def row(level):
    return {'metadata': {'id':12 if level=='campaigns' else 56,'campaignId':12},
            'totalMetrics':{'localSpend':{'amount':'0.10','currency':'USD'},'impressions':10,'taps':2}}

def test_pagination_headers_and_no_campaign_mutations():
    offsets = []
    def handler(request):
        assert request.method == 'POST' and request.url.path.endswith('/query')
        assert request.headers['X-AP-Context'] == 'adAccountId=123'
        body = json.loads(request.content)
        offsets.append(body['pagination']['offset'])
        assert 'granularity' not in body['timeRange']
        return httpx.Response(200,json={'result':{'rows':[row('campaigns')]},'pagination':{'totalCount':2}})
    reports = AdsReports(lambda:'test-token',123,httpx.Client(transport=httpx.MockTransport(handler)))
    assert len(reports.fetch('campaigns','2026-10-01','2026-10-01')) == 2
    assert offsets == [0,1]

def test_atomic_resync_and_missing_installs_stay_unknown(tmp_path):
    db = Database(str(tmp_path/'db'))
    calls = []
    def handler(request):
        level = request.url.path.split('/')[-2]
        calls.append(level)
        return httpx.Response(200,json={'result':{'rows':[row(level)]},'pagination':{'totalCount':1}})
    reports = AdsReports(lambda:'test-token',123,httpx.Client(transport=httpx.MockTransport(handler)))
    for _ in range(2): assert reports.sync(db,'2026-10-01','2026-10-01',12) == 2
    with db.connection() as conn:
        rows = conn.execute('SELECT * FROM reports').fetchall()
    assert len(rows) == 2
    assert all(r['spend']=='0.10' and r['installs'] is None for r in rows)
    # Failed refresh must retain the last complete snapshots.
    reports.client = httpx.Client(transport=httpx.MockTransport(lambda request:httpx.Response(401)))
    with pytest.raises(httpx.HTTPStatusError): reports.sync(db,'2026-10-01','2026-10-01',12)
    with db.connection() as conn: assert conn.execute('SELECT COUNT(*) FROM reports').fetchone()[0] == 2

def test_throttling_is_bounded():
    waits = []
    reports = AdsReports(lambda:'test-token',123,
                         httpx.Client(transport=httpx.MockTransport(lambda r:httpx.Response(429,headers={'Retry-After':'9999'}))),
                         waits.append)
    with pytest.raises(httpx.HTTPStatusError): reports.fetch('campaigns','2026-10-01','2026-10-01')
    assert waits == [60,60]
