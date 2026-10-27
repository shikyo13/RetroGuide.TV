"""Local administration. No report or credential endpoints are exposed publicly."""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
from .database import Database
from .reporting import revenue_report
from .ads_reports import AdsReports

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command',choices=['revenue','sync-ads'])
    parser.add_argument('--start',required=True,help='First UTC day, YYYY-MM-DD')
    parser.add_argument('--end',required=True,help='Last UTC day, inclusive')
    parser.add_argument('--campaign',type=int)
    args = parser.parse_args()
    db = Database(os.environ['ATTRIBUTION_DATABASE'])
    start = datetime.fromisoformat(args.start).replace(tzinfo=timezone.utc)
    end = datetime.fromisoformat(args.end).replace(tzinfo=timezone.utc)+timedelta(days=1)
    if args.command == 'revenue':
        result = revenue_report(db,int(start.timestamp()*1000),int(end.timestamp()*1000),
                                os.getenv('STORE_ENVIRONMENT','Production'))
        print(json.dumps(result,indent=2))
    else:
        if args.campaign is None: parser.error('--campaign is required for sync-ads')
        # Token issuance is separate from reporting and depends on the registered
        # OAuth client's grant. Read refreshed tokens from a protected file.
        path = Path(os.environ['APPLE_ADS_ACCESS_TOKEN_FILE'])
        def token():
            if path.stat().st_mode & 0o077: raise ValueError('Token file must have mode 600')
            value = path.read_text().strip()
            if not value: raise ValueError('Missing access token')
            return value
        client = AdsReports(token,os.environ['APPLE_ADS_ACCOUNT_ID'])
        try:
            count = client.sync(db,args.start,args.end,args.campaign)
        finally:
            client.client.close()
        print(json.dumps({'snapshots':count}))

if __name__ == '__main__':
    main()
