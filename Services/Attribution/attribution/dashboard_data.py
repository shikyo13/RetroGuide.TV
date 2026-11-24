"""Read-only summaries for the private dashboard.

Two kinds of day appear, and the page names both:
- Installs and purchases have exact times, so they are grouped by local day in
  `DASHBOARD_TIMEZONE` (an IANA name such as Europe/London; UTC when unset).
- App activity (devices active, programs watched, setup steps) arrives as one
  mark per device per UTC day, so it can only be grouped by UTC day.

Take-home pay comes from Apple, not this service: `DASHBOARD_PROCEEDS_FILE` names a
JSON file of Apple's purchase reports ({"rows": [{date, territory, purchases,
proceedsUSD, salesUSD}]}), which say what each sale paid out after Apple's commission
and taxes. Purchases newer than Apple's latest day are estimated from those figures.
"""
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import json
import os
import sqlite3
from pathlib import Path
from zoneinfo import ZoneInfo
from .countries import alpha2

DEFAULT_TIMEZONE = 'UTC'
RECENT_PURCHASES = 15
# Apple's purchase reports keep filling in for about this many days after a day ends.
LATE_REPORT_DAYS = 4
# A country's per-sale payout counts as exact when its last few sales paid the same.
EXACT_SALES = 3
CENT = 0.005
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
    """Everything the page shows; ranged parts cover the last `days` days (0 = all).

    Local-day data (installs, purchases) and UTC-day data (activity) each get
    their own bounds over the same number of days, and every series says from
    which day it was recorded, so a series never looks empty before it began.
    """
    zone = local_zone()
    now = now or datetime.now(timezone.utc)
    today, utc_today = now.astimezone(zone).date(), now.date()
    db = connect(path)
    try:
        installs = [{'id': r['id'], 'day': local_day(r['first_seen'], zone), 'utcDay': local_day(r['first_seen'], timezone.utc)}
                    for r in db.execute('SELECT id, first_seen FROM installations')]
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
    since = {'installs': min((i['day'] for i in installs), default=None),
             'purchases': min((p['day'] for p in purchases), default=None),
             'activity': min((date.fromisoformat(r['day']) for r in usage), default=None)}
    if days > 0:
        start, utc_start = today - timedelta(days=days - 1), utc_today - timedelta(days=days - 1)
    else:
        start = min([d for d in since.values() if d] + [today])
        utc_start = min(start, utc_today)
    return {
        'timezone': str(zone),
        # When the database file last changed: on a copy, when it was copied.
        'dataAsOf': datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).isoformat(),
        'since': {k: v.isoformat() if v else None for k, v in since.items()},
        'headline': headline(installs, paid, usage, today, utc_today),
        'daily': daily(installs, paid, start, today, since),
        'activity': activity(usage, utc_start, utc_today, since['activity']),
        'funnel': funnel(installs, paid, usage, utc_start, since['activity']),
        'reasons': reasons(usage, utc_start),
        'sales': sales(purchases, start),
        'countries': countries(installs, paid, contexts, start),
        'versions': versions(usage, utc_start),
        'recent': recent(paid, usage, zone, start),
        'takeHome': take_home(os.getenv('DASHBOARD_PROCEEDS_FILE'), paid, today, utc_today, utc_start),
    }

def take_home(path, paid, today, utc_today, utc_start):
    """What Apple pays out, in US dollars, per UTC day (Apple's reports use UTC days).

    Apple's own figures count wherever it has reported. Its last few days fill in
    late, so for those days (and since) any purchase this service saw that Apple
    hasn't reported yet is estimated from what sales in the same App Store country
    paid, or from the average sale where there's none yet.

    Today and yesterday follow the local days of the purchase counts beside them:
    each of those purchases is valued at what Apple paid per sale in its country,
    exactly where that has always been the same amount (a US sale: $7.00).
    """
    try:
        rows = json.loads(Path(path).read_text())['rows'] if path else None
    except (OSError, ValueError, KeyError):
        rows = None
    if not rows:
        return {'available': False}
    reported, reported_count = defaultdict(float), defaultdict(int)
    # Per sale, newest first, for each country: prices change, so the latest counts.
    per_sale = defaultdict(list)
    for row in sorted(rows, key=lambda r: r['date'], reverse=True):
        reported[row['date']] += row['proceedsUSD']
        reported_count[row['date']] += row['purchases']
        if row['purchases']:
            per_sale[row['territory']].append(row['proceedsUSD'] / row['purchases'])
    through = max(reported)
    latest = [amounts[0] for amounts in per_sale.values()]
    fallback = sum(latest) / len(latest) if latest else 0.0
    def estimate(purchase):
        amounts = per_sale.get(alpha2(purchase['storefront']) or '')
        return amounts[0] if amounts else fallback
    def exact(purchase):
        # The same amount for this country's recent sales: no taxes or rates moving it.
        recent = per_sale.get(alpha2(purchase['storefront']) or '', [])[:EXACT_SALES]
        return len(recent) == EXACT_SALES and max(recent) - min(recent) < CENT
    seen = defaultdict(list)
    for p in paid:
        seen[local_day(p['purchased_at'], timezone.utc).isoformat()].append(p)
    settled_before = (date.fromisoformat(through) - timedelta(days=LATE_REPORT_DAYS)).isoformat()
    estimated, estimated_count = defaultdict(float), 0
    for day, purchases in seen.items():
        missing = len(purchases) - reported_count.get(day, 0)
        if day >= settled_before and missing > 0:
            estimated[day] = sum(estimate(p) for p in purchases[-missing:])
            estimated_count += missing
    days = sorted(set(reported) | set(estimated))
    running, series = 0.0, []
    for day in days:
        amount = reported.get(day, 0.0) + estimated.get(day, 0.0)
        running += amount
        if day >= utc_start.isoformat():
            series.append({'day': day, 'amount': round(amount, 2), 'estimated': day in estimated, 'total': round(running, 2)})
    def on(day):
        bought = [p for p in paid if p['day'] == day]
        return {'amount': round(sum(estimate(p) for p in bought), 2), 'estimated': not all(exact(p) for p in bought)}
    month = utc_today.replace(day=1).isoformat()
    return {
        'available': True, 'through': through, 'estimatedPurchases': estimated_count,
        'today': on(today), 'yesterday': on(today - timedelta(days=1)),
        'allTime': {'amount': round(running, 2), 'estimated': bool(estimated)},
        'thisMonth': {'amount': round(sum(reported.get(d, 0.0) + estimated.get(d, 0.0) for d in days if d >= month), 2),
                      'estimated': any(d >= month for d in estimated)},
        'daily': series,
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
    return {'installs': counted([i['day'] for i in installs]), 'purchases': counted([p['day'] for p in paid]),
            'active': devices('active'), 'watched': devices('watched')}

def days_between(start, end):
    return [start + timedelta(days=n) for n in range((end - start).days + 1)]

def daily(installs, paid, start, today, since):
    """Installs and purchases per local day; today's row is still in progress."""
    counts = defaultdict(lambda: {'installs': 0, 'purchases': 0})
    for i in installs:
        counts[i['day']]['installs'] += 1
    for p in paid:
        counts[p['day']]['purchases'] += 1
    recorded = lambda key, d: since[key] is not None and d >= since[key]
    return [{'day': d.isoformat(), **counts[d], 'partial': d == today,
             'installsRecorded': recorded('installs', d), 'purchasesRecorded': recorded('purchases', d)}
            for d in days_between(start, today)]

def activity(usage, start, utc_today, since):
    """Devices active by type, and devices that watched, per UTC day; days before
    activity was recorded say so."""
    seen = defaultdict(lambda: defaultdict(set))
    for r in usage:
        if r['name'] in ('active', 'watched'):
            seen[r['day']][r['platform'] if r['name'] == 'active' else 'watched'].add(r['installation'])
    rows = []
    for d in days_between(start, utc_today):
        day = d.isoformat()
        rows.append({'day': day, **{k: len(seen[day][k]) for k in PLATFORMS + ('watched',)},
                     'recorded': since is not None and d >= since, 'partial': d == utc_today})
    return rows

def funnel(installs, paid, usage, utc_start, since):
    """How far installations first seen in the range (once activity was recorded) got.
    Admission uses the UTC day, the same clock as the activity it is compared with."""
    if since is None:
        return {'since': None, 'steps': []}
    since = max(utc_start, since)
    cohort = {i['id'] for i in installs if i['utcDay'] >= since}
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
    """Paid purchases per currency in the range, in milliunits (formatted per currency
    on the page), plus what was left out of them and why."""
    rows = defaultdict(lambda: {'purchases': 0, 'amountMilli': 0})
    left_out = {'free': 0, 'unknownPrice': 0, 'refunded': 0}
    for p in purchases:
        if p['day'] < start:
            continue
        if p['revoked_at'] is not None:
            left_out['refunded'] += 1
        elif p['price'] is None:
            left_out['unknownPrice'] += 1
        elif p['price'] == 0:
            left_out['free'] += 1
        else:
            row = rows[p['currency']]
            row['purchases'] += 1
            row['amountMilli'] += p['price']
    currencies = [{'currency': c, **r} for c, r in rows.items()]
    return {'currencies': sorted(currencies, key=lambda r: (-r['purchases'], r['currency'] or '')), **left_out}

def countries(installs, paid, contexts, start):
    """Installs and purchases per App Store country in the range (`region` is its two-letter
    code, for its name); None when not reported."""
    rows = defaultdict(lambda: {'installs': 0, 'purchases': 0})
    for i in installs:
        if i['day'] >= start:
            rows[contexts.get(i['id'])]['installs'] += 1
    for p in paid:
        if p['day'] >= start:
            rows[p['storefront']]['purchases'] += 1
    return sorted(({'country': k, 'region': alpha2(k), **v} for k, v in rows.items()),
                  key=lambda r: (r['country'] is None, -r['purchases'], -r['installs']))

def versions(usage, start):
    """Devices active in the range, by the app version each last reported."""
    latest = {}
    for r in usage:
        if r['name'] == 'active' and r['day'] >= start.isoformat():
            # Latest day wins; on the same day the newer version does (people update, not downgrade).
            seen = (r['day'], version_key(r['version']), r['version'])
            if r['installation'] not in latest or seen > latest[r['installation']]:
                latest[r['installation']] = seen
    counts = defaultdict(int)
    for _, _, version in latest.values():
        counts[version] += 1
    # Newest first: an update ladder, read top to bottom.
    return sorted(({'version': v, 'devices': n} for v, n in counts.items()), key=lambda r: version_key(r['version']), reverse=True)

def version_key(version):
    return tuple(int(part) for part in version.split('.') if part.isdigit())

def recent(paid, usage, zone, start):
    """The latest paid purchases in the range, newest first; None where a detail wasn't reported."""
    platform = {r['installation']: r['platform'] for r in usage}
    rows = []
    for p in reversed([p for p in paid if p['day'] >= start][-RECENT_PURCHASES:]):
        when = datetime.fromtimestamp(p['purchased_at'] / MILLIS, timezone.utc).astimezone(zone)
        rows.append({'time': when.strftime('%b %-d, %-I:%M %p'), 'priceMilli': p['price'],
                     'currency': p['currency'], 'country': p['storefront'], 'region': alpha2(p['storefront']), 'platform': platform.get(p['account_token'])})
    return rows

if __name__ == '__main__':
    print(json.dumps(summary(os.environ['ATTRIBUTION_DATABASE'], 30), indent=1))
