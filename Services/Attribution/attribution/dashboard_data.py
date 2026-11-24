"""Read-only summaries for the private dashboard.

Installs and purchases are grouped by local day in `DASHBOARD_TIMEZONE` (an IANA
name such as Europe/London; UTC when unset). Usage steps arrive already dated by the device in UTC,
so those charts use UTC days.
"""
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import json
import os
import sqlite3
from zoneinfo import ZoneInfo

DEFAULT_TIMEZONE = 'UTC'
RECENT_PURCHASES = 15
MILLIS = 1000
PLATFORMS = ('iPhone', 'iPad', 'AppleTV', 'Mac')
# Setup and viewing steps, in the order people reach them.
FUNNEL = (('serverConnected', 'Server connected'), ('lineupReady', 'Channels built'),
          ('watched', 'Watched a program'), ('proViewed', 'Opened Pro page'), ('purchased', 'Bought Pro'))

def connect(path):
    """A connection that cannot write, even by mistake."""
    db = sqlite3.connect(f'file:{path}?mode=ro', uri=True, timeout=10)
    db.row_factory = sqlite3.Row
    return db

def local_zone():
    return ZoneInfo(os.getenv('DASHBOARD_TIMEZONE', DEFAULT_TIMEZONE))

def summary(path, days, now=None):
    """Everything the page shows for the last `days` local days (0 = since the start)."""
    zone = local_zone()
    now = now or datetime.now(timezone.utc)
    today = now.astimezone(zone).date()
    db = connect(path)
    try:
        installs = [(r['id'], local_day(r['first_seen'], zone)) for r in db.execute('SELECT id, first_seen FROM installations')]
        purchases = [dict(r) for r in db.execute(
            '''SELECT purchased_at, price, currency, storefront, account_token, revoked_at FROM purchases
               WHERE environment='Production' AND ownership='PURCHASED' ORDER BY purchased_at''')]
        usage = db.execute('SELECT installation, name, detail, day, platform, version FROM usage_events').fetchall()
        contexts = {r['installation']: r['storefront'] for r in db.execute('SELECT installation, storefront FROM installation_context')}
    finally:
        db.close()
    first = min([d for _, d in installs] or [today])
    start = first if days <= 0 else max(first, today - timedelta(days=days - 1))
    paid = [p for p in purchases if (p['price'] or 0) > 0 and p['revoked_at'] is None]
    for p in paid:
        p['day'] = local_day(p['purchased_at'], zone)
    return {
        'generatedAt': now.isoformat(), 'timezone': str(zone), 'today': today.isoformat(),
        # When the database file last changed: on a copy, when it was copied.
        'dataAsOf': datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).isoformat(),
        'start': start.isoformat(),
        'headline': headline(installs, paid, usage, today, now),
        'daily': daily(installs, paid, start, today),
        'active': active(usage, start, now.date()),
        'funnel': funnel(installs, paid, usage, start),
        'reasons': reasons(usage, start),
        'versions': versions(usage, now.date()),
        'countries': countries(installs, paid, contexts, start),
        'recent': recent(paid, usage, zone),
        'refunds': sum(1 for p in purchases if p['revoked_at'] is not None),
    }

def local_day(millis, zone):
    return datetime.fromtimestamp(millis / MILLIS, timezone.utc).astimezone(zone).date()

def revenue(purchases):
    """Sales per currency, in whole units; currencies are never added together."""
    totals = defaultdict(int)
    for p in purchases:
        totals[p['currency'] or 'UNKNOWN'] += p['price']
    return {currency: round(amount / MILLIS, 2) for currency, amount in sorted(totals.items())}

def headline(installs, paid, usage, today, now):
    def on(day):
        bought = [p for p in paid if p['day'] == day]
        return {'installs': sum(1 for _, d in installs if d == day), 'purchases': len(bought), 'revenue': revenue(bought)}
    utc_today, utc_yesterday = now.date().isoformat(), (now.date() - timedelta(days=1)).isoformat()
    def devices(name, day):
        return len({r['installation'] for r in usage if r['name'] == name and r['day'] == day})
    return {
        'today': on(today), 'yesterday': on(today - timedelta(days=1)),
        'allTime': {'installs': len(installs), 'purchases': len(paid), 'revenue': revenue(paid)},
        'activeToday': devices('active', utc_today), 'activeYesterday': devices('active', utc_yesterday),
        'watchedToday': devices('watched', utc_today), 'watchedYesterday': devices('watched', utc_yesterday),
    }

def days_between(start, end):
    return [start + timedelta(days=n) for n in range((end - start).days + 1)]

def daily(installs, paid, start, today):
    counts = defaultdict(lambda: {'installs': 0, 'purchases': 0})
    for _, day in installs:
        counts[day]['installs'] += 1
    for p in paid:
        counts[p['day']]['purchases'] += 1
    return [{'day': d.isoformat(), **counts[d]} for d in days_between(start, today)]

def active(usage, start, utc_today):
    seen = defaultdict(lambda: defaultdict(set))
    for r in usage:
        if r['name'] in ('active', 'watched'):
            key = r['platform'] if r['name'] == 'active' else 'watched'
            seen[r['day']][key].add(r['installation'])
    first_usage = min((r['day'] for r in usage), default=utc_today.isoformat())
    begin = max(start, date.fromisoformat(first_usage))
    return [{'day': d.isoformat(), **{k: len(seen[d.isoformat()][k]) for k in PLATFORMS + ('watched',)}}
            for d in days_between(begin, utc_today)]

def funnel(installs, paid, usage, start):
    """How far installations first seen since `start` (and since usage began) got."""
    first_usage = min((r['day'] for r in usage), default=None)
    if first_usage is None:
        return {'since': None, 'steps': []}
    since = max(start, date.fromisoformat(first_usage))
    cohort = {i for i, d in installs if d >= since}
    reached = defaultdict(set)
    for r in usage:
        if r['installation'] in cohort and not (r['name'] == 'lineupReady' and r['detail'] == '0'):
            reached[r['name']].add(r['installation'])
    reached['purchased'] = {p['account_token'] for p in paid if p['account_token'] in cohort}
    steps = [{'label': 'Installed', 'count': len(cohort)}]
    steps += [{'label': label, 'count': len(reached[name])} for name, label in FUNNEL]
    return {'since': since.isoformat(), 'steps': steps}

def reasons(usage, start):
    counts = defaultdict(lambda: defaultdict(set))
    for r in usage:
        if r['day'] >= start.isoformat() and r['name'] in ('playbackFailed', 'setupProblem', 'setupFailed', 'libraryFailed') and r['detail']:
            counts[r['name']][r['detail']].add(r['installation'])
    return {name: sorted(((d, len(i)) for d, i in details.items()), key=lambda x: -x[1]) for name, details in counts.items()}

def versions(usage, utc_today):
    """App versions among devices active on the latest day with activity."""
    days = sorted({r['day'] for r in usage if r['name'] == 'active' and r['day'] <= utc_today.isoformat()})
    if not days:
        return {'day': None, 'versions': []}
    counts = defaultdict(set)
    for r in usage:
        if r['name'] == 'active' and r['day'] == days[-1]:
            counts[r['version']].add(r['installation'])
    return {'day': days[-1], 'versions': sorted(((v, len(i)) for v, i in counts.items()), key=lambda x: -x[1])}

def countries(installs, paid, contexts, start):
    rows = defaultdict(lambda: {'installs': 0, 'purchases': 0})
    for installation, day in installs:
        if day >= start:
            rows[contexts.get(installation) or 'unknown']['installs'] += 1
    for p in paid:
        if p['day'] >= start:
            rows[p['storefront'] or 'unknown']['purchases'] += 1
    return sorted(([k, v['installs'], v['purchases']] for k, v in rows.items()), key=lambda x: (-x[2], -x[1]))

def recent(paid, usage, zone):
    platform = {r['installation']: r['platform'] for r in usage}
    rows = []
    for p in reversed(paid[-RECENT_PURCHASES:]):
        when = datetime.fromtimestamp(p['purchased_at'] / MILLIS, timezone.utc).astimezone(zone)
        rows.append({'time': when.strftime('%b %-d, %-I:%M %p'), 'price': round(p['price'] / MILLIS, 2),
                     'currency': p['currency'], 'country': p['storefront'] or 'unknown',
                     'platform': platform.get(p['account_token'], 'unknown')})
    return rows

if __name__ == '__main__':
    print(json.dumps(summary(os.environ['ATTRIBUTION_DATABASE'], 30), indent=1))
