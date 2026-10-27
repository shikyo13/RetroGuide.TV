"""Revenue grouped by Apple's attributed IDs, without estimating missing matches."""
from collections import defaultdict
from decimal import Decimal
import json

def revenue_report(database, start_ms, end_ms, environment='Production'):
    if start_ms >= end_ms:
        raise ValueError('Start must precede end')
    with database.connection() as db:
        rows = db.execute('''SELECT p.*,i.attribution,i.app_identity AS installation_identity FROM purchases p
            LEFT JOIN installations i ON i.id=p.account_token
            WHERE p.environment=? AND p.purchased_at>=? AND p.purchased_at<?''',
            (environment, start_ms, end_ms)).fetchall()
        identities = defaultdict(list)
        for installation in db.execute('SELECT app_identity,first_seen,attribution FROM installations WHERE attribution IS NOT NULL'):
            if installation['app_identity']:
                identities[installation['app_identity']].append(dict(installation))
    groups = defaultdict(lambda: {'purchases':0, 'refunds':0, 'unknownPricePurchases':0,
                                 'gross':Decimal(0), 'refunded':Decimal(0)})
    for row in rows:
        # Family Sharing is access, not a second paid transaction.
        if row['ownership'] != 'PURCHASED':
            continue
        attribution = json.loads(row['attribution']) if row['attribution'] else {}
        if row['app_identity'] and row['installation_identity'] and row['app_identity'] != row['installation_identity']:
            # An App Store account change must not inherit another account's ad.
            attribution = {}
        # Apple signs the per-app account identity on newer OS versions. Use it
        # across devices only when a single acquisition predates the purchase.
        if attribution.get('attribution') is not True and row['app_identity']:
            candidates = {}
            for install in identities[row['app_identity']]:
                candidate = json.loads(install['attribution'])
                if install['first_seen'] <= row['purchased_at'] and candidate.get('attribution') is True:
                    key = tuple(candidate.get(field) for field in ('campaignId','adGroupId','keywordId'))
                    candidates[key] = candidate
            if len(candidates) == 1:
                attribution = next(iter(candidates.values()))
        attributed = attribution.get('attribution') is True
        key = (attribution.get('campaignId') if attributed else None,
               attribution.get('adGroupId') if attributed else None,
               attribution.get('keywordId') if attributed else None,
               row['currency'] or 'UNKNOWN')
        group = groups[key]
        group['purchases'] += 1
        group['refunds'] += row['revoked_at'] is not None
        if row['price'] is None:
            group['unknownPricePurchases'] += 1
        else:
            amount = Decimal(row['price']) / Decimal(1000)
            group['gross'] += amount
            if row['revoked_at'] is not None:
                group['refunded'] += amount
    result = []
    for (campaign, ad_group, keyword, currency), group in groups.items():
        result.append(dict(campaignId=campaign, adGroupId=ad_group, keywordId=keyword,
                           currency=currency, **{k:v for k,v in group.items() if k not in ('gross','refunded')},
                           grossSales=str(group['gross']), refundedSales=str(group['refunded']),
                           netSales=str(group['gross']-group['refunded'])))
    return {'environment':environment, 'purchaseStartInclusive':start_ms, 'purchaseEndExclusive':end_ms,
            'groups':result}
