"""Read-only summaries for the private dashboard.

Two kinds of day appear, and the page names both:
- Installs and purchases have exact times, so they are grouped by local day in
  `DASHBOARD_TIMEZONE` (an IANA name such as Europe/London; UTC when unset).
- App activity (devices active, programs watched, setup steps) arrives as one
  mark per device per UTC day, so it can only be grouped by UTC day.
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
WHY = ('playbackFailed', 'setupProblem', 'setupFailed', 'libraryFailed')
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
    """Everything the page shows; ranged parts cover the last `days` local days (0 = all)."""
    zone = local_zone()
    now = now or datetime.now(timezone.utc)
    today, utc_today = now.astimezone(zone).date(), now.date()
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
    for p in purchases:
        p['day'] = local_day(p['purchased_at'], zone)
    paid = [p for p in purchases if (p['price'] or 0) > 0 and p['revoked_at'] is None]
    first = min([d for _, d in installs] or [today])
    start = first if days <= 0 else max(first, today - timedelta(days=days - 1))
    activity_since = min((r['day'] for r in usage), default=None)
    return {
        'timezone': str(zone),
        # When the database file last changed: on a copy, when it was copied.
        'dataAsOf': datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).isoformat(),
        'activitySince': activity_since,
        'headline': headline(installs, paid, usage, today, utc_today),
        'daily': daily(installs, paid, start, today),
        'activity': activity(usage, start, utc_today, activity_since),
        'funnel': funnel(installs, paid, usage, start, activity_since),
        'reasons': reasons(usage, start),
        'sales': sales(purchases, start),
        'countries': countries(installs, paid, contexts, start),
        'versions': versions(usage, start),
        'recent': recent(paid, usage, zone, start),
    }

def local_day(millis, zone):
    return datetime.fromtimestamp(millis / MILLIS, timezone.utc).astimezone(zone).date()

def headline(installs, paid, usage, today, utc_today):
    """Today, yesterday and all time for each headline number."""
    yesterday, utc_yesterday = today - timedelta(days=1), (utc_today - timedelta(days=1)).isoformat()
    def counted(days):
        return {'today': days.count(today), 'yesterday': days.count(yesterday), 'allTime': len(days)}
    def devices(name):
        on = lambda day: len({r['installation'] for r in usage if r['name'] == name and r['day'] == day})
        return {'today': on(utc_today.isoformat()), 'yesterday': on(utc_yesterday),
                'allTime': len({r['installation'] for r in usage if r['name'] == name})}
    return {'installs': counted([d for _, d in installs]), 'purchases': counted([p['day'] for p in paid]),
            'active': devices('active'), 'watched': devices('watched')}

def days_between(start, end):
    return [start + timedelta(days=n) for n in range((end - start).days + 1)]

def daily(installs, paid, start, today):
    """Installs and purchases per local day; today's row is still in progress."""
    counts = defaultdict(lambda: {'installs': 0, 'purchases': 0})
    for _, day in installs:
        counts[day]['installs'] += 1
    for p in paid:
        counts[p['day']]['purchases'] += 1
    return [{'day': d.isoformat(), **counts[d], 'partial': d == today} for d in days_between(start, today)]

def activity(usage, start, utc_today, since):
    """Devices active by type, and devices that watched, per UTC day over the same span
    as the other charts; days before activity was recorded say so."""
    seen = defaultdict(lambda: defaultdict(set))
    for r in usage:
        if r['name'] in ('active', 'watched'):
            seen[r['day']][r['platform'] if r['name'] == 'active' else 'watched'].add(r['installation'])
    rows = []
    for d in days_between(start, utc_today):
        day = d.isoformat()
        rows.append({'day': day, **{k: len(seen[day][k]) for k in PLATFORMS + ('watched',)},
                     'recorded': since is not None and day >= since, 'partial': d == utc_today})
    return rows

def funnel(installs, paid, usage, start, since):
    """How far installations first seen in the range (once activity was recorded) got."""
    if since is None:
        return {'since': None, 'steps': []}
    since = max(start, date.fromisoformat(since))
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
    """Devices per reason, per kind of problem, most common first."""
    counts = defaultdict(lambda: defaultdict(set))
    for r in usage:
        if r['day'] >= start.isoformat() and r['name'] in WHY and r['detail']:
            counts[r['name']][r['detail']].add(r['installation'])
    return {name: sorted(((d, len(i)) for d, i in counts[name].items()), key=lambda x: -x[1])
            for name in WHY if name in counts}

def sales(purchases, start):
    """Paid purchases per currency in the range, plus what was left out of them."""
    rows = defaultdict(lambda: {'purchases': 0, 'amount': 0})
    free = refunded = 0
    for p in purchases:
        if p['day'] < start:
            continue
        if p['revoked_at'] is not None:
            refunded += 1
        elif not p['price']:
            free += 1
        else:
            row = rows[p['currency'] or 'UNKNOWN']
            row['purchases'] += 1
            row['amount'] += p['price']
    currencies = [{'currency': c, 'purchases': r['purchases'], 'amount': round(r['amount'] / MILLIS, 2)}
                  for c, r in rows.items()]
    return {'currencies': sorted(currencies, key=lambda r: (-r['purchases'], r['currency'])),
            'free': free, 'refunded': refunded}

def countries(installs, paid, contexts, start):
    """Installs and purchases per App Store country in the range; None when not reported."""
    rows = defaultdict(lambda: {'installs': 0, 'purchases': 0})
    for installation, day in installs:
        if day >= start:
            rows[contexts.get(installation)]['installs'] += 1
    for p in paid:
        if p['day'] >= start:
            rows[p['storefront']]['purchases'] += 1
    return sorted(({'country': k, **v} for k, v in rows.items()),
                  key=lambda r: (r['country'] is None, -r['purchases'], -r['installs']))

def versions(usage, start):
    """Devices active in the range, by the app version each last reported."""
    latest = {}
    for r in usage:
        if r['name'] == 'active' and r['day'] >= start.isoformat():
            if r['installation'] not in latest or r['day'] >= latest[r['installation']][0]:
                latest[r['installation']] = (r['day'], r['version'])
    counts = defaultdict(int)
    for _, version in latest.values():
        counts[version] += 1
    # Newest first: an update ladder, read top to bottom.
    order = lambda version: tuple(int(part) for part in version.split('.') if part.isdigit())
    return sorted(({'version': v, 'devices': n} for v, n in counts.items()), key=lambda r: order(r['version']), reverse=True)

def recent(paid, usage, zone, start):
    """The latest paid purchases in the range, newest first; None where a detail wasn't reported."""
    platform = {r['installation']: r['platform'] for r in usage}
    rows = []
    for p in reversed([p for p in paid if p['day'] >= start][-RECENT_PURCHASES:]):
        when = datetime.fromtimestamp(p['purchased_at'] / MILLIS, timezone.utc).astimezone(zone)
        rows.append({'time': when.strftime('%b %-d, %-I:%M %p'), 'price': round(p['price'] / MILLIS, 2),
                     'currency': p['currency'], 'country': p['storefront'], 'platform': platform.get(p['account_token'])})
    return rows

if __name__ == '__main__':
    print(json.dumps(summary(os.environ['ATTRIBUTION_DATABASE'], 30), indent=1))
