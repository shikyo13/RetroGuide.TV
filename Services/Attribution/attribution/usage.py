"""Setup and usage steps sent by the app, and their report.

Each row says an installation did something on a UTC day. Names and details
come from fixed lists; anything else is dropped, so newer app versions can
add events without breaking older servers.
"""
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
import re
import time

SERVERS = {'none', 'plex', 'jellyfin', 'jellyfin+plex'}
# UsageEvent.FailureReason and UsageEvent.SetupProblem in the app.
REASONS = {'timeout', 'offline', 'unreachable', 'notSecure', 'certificate', 'unauthorized',
           'serverError', 'rejected', 'unreadable', 'badAddress', 'cancelled', 'interrupted',
           'noLibraries', 'other'}
PROBLEMS = {'plexNoServers', 'jellyfinFoundNone', 'jellyfinFoundNotSecure', 'jellyfinFoundUntrusted',
            'jellyfinNotSecure', 'jellyfinUntrusted', 'jellyfinNoAnswer', 'jellyfinUnencryptedChosen',
            'jellyfinNotSecureInternet', 'jellyfinLocalNetworkBlocked', 'plexLocalNetworkBlocked'}
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
# The App Store country (StoreKit's Storefront.countryCode, ISO 3166-1 alpha-3),
# not where the device is. Apple signs the same code into each purchase.
STOREFRONT = re.compile(r'[A-Z]{3}')
# The languages the app is translated into; it reports the one it shows.
LANGUAGES = {'en', 'es', 'fr', 'de', 'it', 'pt-BR', 'nl', 'ja', 'ko', 'zh-Hans', 'zh-Hant', 'pl', 'sv', 'ru', 'cs', 'hi', 'bn', 'mr', 'te', 'ta', 'gu', 'kn', 'ml', 'pa', 'or'}
UNKNOWN = 'unknown'
# Events from devices with a wrong clock or a long time offline.
ACCEPTED_DAYS_BACK = 14
ACCEPTED_DAYS_AHEAD = 1

SCHEMA = '''
CREATE TABLE IF NOT EXISTS usage_events (
 installation TEXT NOT NULL, name TEXT NOT NULL, detail TEXT NOT NULL, day TEXT NOT NULL,
 platform TEXT NOT NULL, version TEXT NOT NULL, received_at INTEGER NOT NULL,
 PRIMARY KEY(installation, name, detail, day)
);
CREATE TABLE IF NOT EXISTS installation_context (
 installation TEXT PRIMARY KEY, storefront TEXT, language TEXT, updated_at INTEGER NOT NULL
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

def context(storefront, language):
    """The country and language worth keeping; anything unexpected is dropped."""
    storefront = storefront if storefront and STOREFRONT.fullmatch(storefront) else None
    language = language if language in LANGUAGES else None
    return storefront, language

def store(database, installation, platform, version, events, storefront=None, language=None):
    now = int(time.time())
    storefront, language = context(storefront, language)
    with database.connection() as db:
        db.executemany('INSERT OR IGNORE INTO usage_events VALUES(?,?,?,?,?,?,?)',
                       [(installation, name, detail, day, platform, version, now)
                        for name, detail, day in events])
        if storefront or language:
            # The latest values win: people change their App Store country or language.
            db.execute('''INSERT INTO installation_context VALUES(?,?,?,?)
                ON CONFLICT(installation) DO UPDATE SET
                storefront=COALESCE(excluded.storefront,installation_context.storefront),
                language=COALESCE(excluded.language,installation_context.language),
                updated_at=excluded.updated_at''', (installation, storefront, language, now))

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
        contexts = {row['installation']: row for row in db.execute('SELECT * FROM installation_context')}
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
    def funnel_of(installs):
        steps = {f'{n}:{d}' if d else n: count(installs, n, d) for n, d in FUNNEL}
        steps['activeOnLaterDay'] = sum(len(days_active[i] - {first_day[i]}) > 0 for i in installs)
        return {'installations': len(installs), **steps}
    funnel = {platform: funnel_of(installs) for platform, installs in sorted(by_platform.items()) + [('all', cohort)]}
    def grouped(field):
        groups = defaultdict(list)
        for install in cohort:
            value = contexts[install][field] if install in contexts else None
            groups[value or UNKNOWN].append(install)
        return {key: funnel_of(installs) for key, installs in sorted(groups.items())}
    # Why installations first seen in range stopped: installations per reason.
    why = defaultdict(lambda: defaultdict(int))
    for install in cohort:
        for name, detail in reached[install]:
            if name in WHY and detail:
                why[name][detail] += 1
    return {'start': start.isoformat(), 'end': end.isoformat(),
            'daily': {day: {k: len(v) for k, v in sorted(names.items())} for day, names in sorted(daily.items())},
            'firstSeenInRange': funnel,
            'firstSeenByStorefront': grouped('storefront'),
            'firstSeenByLanguage': grouped('language'),
            'whyFirstSeenInRange': {name: dict(sorted(counts.items())) for name, counts in sorted(why.items())}}
