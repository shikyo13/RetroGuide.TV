"""Read-only Apple Ads Platform API reporting with atomic daily snapshots."""
from datetime import date
from decimal import Decimal
import json
import time
import httpx

PAGE_SIZE = 100
MAX_PAGES = 1000
MAX_ATTEMPTS = 3
API_BASE = 'https://api.ads.apple.com/v1/reports/apps'

class AdsReports:
    def __init__(self, token_provider, account_id, client=None, sleep=time.sleep):
        self.token_provider = token_provider
        self.account_id = int(account_id)
        self.client = client or httpx.Client(timeout=30, follow_redirects=False)
        self.sleep = sleep

    def fetch(self, level, start, end, campaign_id=None):
        if level not in ('campaigns', 'keywords'):
            raise ValueError('Unsupported reporting level')
        first, last = date.fromisoformat(start), date.fromisoformat(end)
        if not 0 <= (last-first).days < 90:
            raise ValueError('Daily report range must be between 1 and 90 days')
        if level == 'keywords' and campaign_id is None:
            raise ValueError('Keyword reports require a campaign ID')
        body = {'pagination': {'offset':0, 'pageSize':PAGE_SIZE},
                'timeRange': {'start':start, 'end':end, 'timeZone':'UTC'}}
        if first != last:
            body['timeRange']['granularity'] = 'DAILY'
        if campaign_id is not None:
            body['filters'] = [{'field':'campaignId','operator':'EQUALS','value':str(int(campaign_id))}]
        rows = []
        for _ in range(MAX_PAGES):
            payload = self._request(level, body)
            page = payload['result']['rows']
            if not isinstance(page, list):
                raise ValueError('Invalid report rows')
            rows.extend(page)
            total = payload['pagination']['totalCount']
            if len(rows) >= total:
                return rows
            if not page:
                raise ValueError('Incomplete pagination')
            body['pagination']['offset'] += len(page)
        raise ValueError('Report exceeds pagination limit')

    def _request(self, level, body):
        for attempt in range(MAX_ATTEMPTS):
            token = self.token_provider()
            response = self.client.post(f'{API_BASE}/{level}/query', json=body,
                headers={'Authorization':f'Bearer {token}', 'X-AP-Context':f'adAccountId={self.account_id}'})
            if response.status_code == 429 or 500 <= response.status_code < 600:
                if attempt < MAX_ATTEMPTS - 1:
                    try: delay = float(response.headers.get('Retry-After', 2 ** attempt))
                    except ValueError: delay = 2 ** attempt
                    self.sleep(max(0, min(delay, 60)))
                    continue
            response.raise_for_status()
            return response.json()
        raise RuntimeError('Report unavailable')

    def sync(self, database, start, end, campaign_id):
        # Fetch and validate everything before replacing stored snapshots.
        records = []
        for level in ('campaigns','keywords'):
            for row in self.fetch(level, start, end, campaign_id):
                meta = row['metadata']
                if level == 'campaigns' and int(meta['id']) != int(campaign_id):
                    raise ValueError('Unexpected campaign')
                if level == 'keywords' and int(meta['campaignId']) != int(campaign_id):
                    raise ValueError('Unexpected campaign')
                metrics = [dict(row['totalMetrics'], date=start)] if start == end else row['granularMetrics']
                for metric in metrics:
                    day = date.fromisoformat(metric['date']).isoformat()
                    if not start <= day <= end: raise ValueError('Unexpected report date')
                    spend = metric['localSpend']
                    amount = Decimal(spend['amount'])
                    if not amount.is_finite() or amount < 0: raise ValueError('Invalid spend')
                    records.append((day,level,str(meta['id']),spend['currency'],str(amount),
                                    int(metric['impressions']),int(metric['taps']),
                                    int(metric['totalInstalls']) if metric.get('totalInstalls') is not None else None,
                                    json.dumps(meta),int(time.time())))
        with database.connection() as db:
            db.execute('''DELETE FROM reports WHERE day>=? AND day<=? AND
                ((level='campaigns' AND object_key=?) OR
                 (level='keywords' AND CAST(json_extract(metadata,'$.campaignId') AS TEXT)=?))''',
                       (start,end,str(campaign_id),str(campaign_id)))
            db.executemany('INSERT INTO reports VALUES(?,?,?,?,?,?,?,?,?,?)',records)
        return len(records)
