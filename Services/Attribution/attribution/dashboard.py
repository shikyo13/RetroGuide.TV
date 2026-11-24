"""Private, read-only stats dashboard for the owner's own computer.

Runs against a copy of the database, never alongside the public ingestion API,
and answers only this computer: the connection must come from loopback and be
addressed to localhost, so neither another device nor a web page pointing its
own name at 127.0.0.1 can read it. Bind it to 127.0.0.1.
"""
import ipaddress
import os
from pathlib import Path
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, JSONResponse
from . import dashboard_data

LOCAL_HOSTS = {'localhost', '127.0.0.1', '[::1]'}
STATIC = Path(__file__).parent / 'dashboard'
PAGES = {'': ('index.html', 'text/html'), 'dashboard.css': ('dashboard.css', 'text/css'),
         'dashboard.js': ('dashboard.js', 'text/javascript')}
MAX_DAYS = 3650
HEADERS = {'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff',
           'Referrer-Policy': 'no-referrer', 'Cross-Origin-Resource-Policy': 'same-origin',
           'Content-Security-Policy': "default-src 'self'; style-src 'self'; script-src 'self'; frame-ancestors 'none'"}

def is_local(request):
    try:
        from_loopback = ipaddress.ip_address(request.client.host).is_loopback
    except (AttributeError, ValueError):
        return False
    host = request.headers.get('host', '').rsplit(':', 1)[0].lower()
    return from_loopback and host in LOCAL_HOSTS

def create_app():
    database = os.environ['ATTRIBUTION_DATABASE']
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware('http')
    async def guard(request: Request, call_next):
        if request.method not in ('GET', 'HEAD') or not is_local(request):
            return JSONResponse({'detail': 'Open this page at localhost on this computer'}, status_code=403, headers=HEADERS)
        response = await call_next(request)
        response.headers.update(HEADERS)
        return response

    @app.get('/data')
    def data(days: int = Query(30, ge=0, le=MAX_DAYS)):
        return dashboard_data.summary(database, days)

    @app.get('/{page:path}')
    def page(page: str):
        if page not in PAGES:
            raise HTTPException(404)
        name, media = PAGES[page]
        return FileResponse(STATIC / name, media_type=media)

    return app
