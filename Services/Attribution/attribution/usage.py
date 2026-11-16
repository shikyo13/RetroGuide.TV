"""Setup and usage steps sent by the app, and their report.

Each row says an installation did something on a UTC day. Names and details
come from fixed lists; anything else is dropped, so newer app versions can
add events without breaking older servers.
"""
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import time

SERVERS = {'none', 'plex', 'jellyfin', 'jellyfin+plex'}
# UsageEvent.FailureReason and UsageEvent.SetupProblem in the app (1.9.1).
REASONS = {'timeout', 'offline', 'unreachable', 'notSecure', 'certificate', 'unauthorized',
           'serverError', 'rejected', 'unreadable', 'badAddress', 'cancelled', 'interrupted',
           'noLibraries', 'other'}
PROBLEMS = {'plexNoServers', 'jellyfinFoundNone', 'jellyfinFoundNotSecure', 'jellyfinFoundUntrusted',
            'jellyfinNotSecure', 'jellyfinUntrusted', 'jellyfinNoAnswer'}
EVENTS = {
    'active': SERVERS,
    'setup': {'welcome', 'plexLink', 'plexServers', 'jellyfinFind', 'jellyfinAddress',
              'jellyfinSignIn', 'libraries', 'failed'},
    'serverConnected': {'plex', 'jellyfin'},
    'libraryFailed': {''} | REASONS,
    'setupFailed': REASONS,
    'setupProblem': PROBLEMS,
    'lineupReady': {'0', '1-9', '10-49', '50+'},
    'watched': {'', 'plex', 'jellyfin'},
    'proViewed': {''},
}
PLATFORMS = ('iPhone', 'iPad', 'AppleTV', 'Mac')
# Events from devices with a wrong clock or a long time offline.
ACCEPTED_DAYS_BACK = 14
ACCEPTED_DAYS_AHEAD = 1

SCHEMA = '''
CREATE TABLE IF NOT EXISTS usage_events (
 installation TEXT NOT NULL, name TEXT NOT NULL, detail TEXT NOT NULL, day TEXT NOT NULL,
 platform TEXT NOT NULL, version TEXT NOT NULL, received_at INTEGER NOT NULL,
 PRIMARY KEY(installation, name, detail, day)
);
'''

def accepted(events, today=None):
    """The events worth keeping, as (name, detail, day)."""
    today = today or datetime.now(timezone.utc).date()
    earliest = today - timedelta(days=ACCEPTED_DAYS_BACK)
    latest = today + timedelta(days=ACCEPTED_DAYS_AHEAD)
    kept = set()
    for event in events:
        if event.detail not in EVENTS.get(event.name, ()):
            continue
        try:
            day = date.fromisoformat(event.day)
        except ValueError:
            continue
        if earliest <= day <= latest:
            kept.add((event.name, event.detail, event.day))
    return kept

def store(database, installation, platform, version, events):
    now = int(time.time())
    with database.connection() as db:
        db.executemany('INSERT OR IGNORE INTO usage_events VALUES(?,?,?,?,?,?,?)',
                       [(installation, name, detail, day, platform, version, now)
                        for name, detail, day in events])

WHY = ('setupProblem', 'setupFailed', 'libraryFailed')

FUNNEL = [('setup', 'welcome'), ('setup', 'plexLink'), ('setup', 'jellyfinFind'),
          ('setup', 'libraries'), ('setup', 'failed'), ('setupProblem', None), ('serverConnected', None),
          ('libraryFailed', None), ('lineupReady', None), ('watched', None), ('proViewed', None)]

def usage_report(database, start, end):
    """Daily activity, and how far installations first seen in [start, end] got.

    `start` and `end` are inclusive `date`s. Installations count from the first
    day they sent usage, which for earlier app versions is their first day on
    one that sends it.
    """
    if start > end:
        raise ValueError('Start must not follow end')
    with database.connection() as db:
        rows = db.execute('SELECT installation,name,detail,day,platform,version FROM usage_events').fetchall()
    first_day, platform_of, reached, days_active = {}, {}, defaultdict(set), defaultdict(set)
    daily = defaultdict(lambda: defaultdict(set))
    for row in rows:
        install = row['installation']
        if install not in first_day or row['day'] < first_day[install]:
            first_day[install] = row['day']
        platform_of[install] = row['platform']
        reached[install].add((row['name'], row['detail']))
        if row['name'] == 'active':
            days_active[install].add(row['day'])
        if start.isoformat() <= row['day'] <= end.isoformat():
            day = daily[row['day']]
            if row['name'] == 'active':
                day['active'].add(install)
                day[f"active:{row['platform']}"].add(install)
            elif row['name'] == 'watched':
                day['watched'].add(install)
            else:
                day[f"{row['name']}:{row['detail']}" if row['detail'] else row['name']].add(install)
    cohort = [i for i, d in first_day.items() if start.isoformat() <= d <= end.isoformat()]
    def count(installs, name, detail):
        return sum(any(n == name and (detail is None or d == detail) for n, d in reached[i]) for i in installs)
    by_platform = defaultdict(list)
    for install in cohort:
        by_platform[platform_of[install]].append(install)
    funnel = {}
    for platform, installs in sorted(by_platform.items()) + [('all', cohort)]:
        steps = {f'{n}:{d}' if d else n: count(installs, n, d) for n, d in FUNNEL}
        steps['activeOnLaterDay'] = sum(len(days_active[i] - {first_day[i]}) > 0 for i in installs)
        funnel[platform] = {'installations': len(installs), **steps}
    # Why installations first seen in range stopped: installations per reason.
    why = defaultdict(lambda: defaultdict(int))
    for install in cohort:
        for name, detail in reached[install]:
            if name in WHY and detail:
                why[name][detail] += 1
    return {'start': start.isoformat(), 'end': end.isoformat(),
            'daily': {day: {k: len(v) for k, v in sorted(names.items())} for day, names in sorted(daily.items())},
            'firstSeenInRange': funnel,
            'whyFirstSeenInRange': {name: dict(sorted(counts.items())) for name, counts in sorted(why.items())}}
