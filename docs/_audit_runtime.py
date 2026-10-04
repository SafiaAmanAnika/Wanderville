"""Read-only local configuration/database audit. Never prints credentials."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'code/server'))
from app.core.config import settings
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url

url = make_url(settings.database_url)
print(json.dumps({
    'environment': settings.wanderville_env,
    'database_driver': url.drivername,
    'database_host': url.host,
    'database_port': url.port,
    'database_name': url.database,
    'google_client_id_configured': bool(settings.google_client_id),
    'smtp_host': settings.smtp_host,
    'smtp_port': settings.smtp_port,
    'smtp_user_configured': bool(settings.smtp_user),
    'smtp_password_configured': bool(settings.smtp_password),
    'smtp_starttls': settings.smtp_starttls,
    'email_base_url': settings.email_base_url,
    'email_from_is_placeholder': settings.email_from.endswith('.example'),
    'dev_email_count': len(list((ROOT / 'code/server/.dev-mail').glob('*.eml'))),
}, indent=2))
try:
    engine = create_engine(settings.database_url, connect_args={'connect_timeout': 5})
    with engine.connect() as conn:
        conn.execute(text('SET TRANSACTION READ ONLY'))
        print('DATABASE_READ_ONLY_CHECK', json.dumps({
            'select_1': conn.scalar(text('SELECT 1')),
            'database': conn.scalar(text('SELECT current_database()')),
            'server_address': str(conn.scalar(text('SELECT inet_server_addr()'))),
            'version': conn.scalar(text('SHOW server_version')),
            'migration_revision': conn.scalar(text('SELECT version_num FROM alembic_version')),
            'table_count': len(inspect(conn).get_table_names()),
            'catalog_count': conn.scalar(text('SELECT count(*) FROM item_definitions')),
        }))
        conn.rollback()
    engine.dispose()
except Exception as exc:
    print('DATABASE_READ_ONLY_CHECK_FAILED', type(exc).__name__)

import httpx
for route in ('/health', '/ready'):
    try:
        response = httpx.get('http://127.0.0.1:8000' + route, timeout=3)
        print('LOCAL_API', route, response.status_code)
    except httpx.HTTPError as exc:
        print('LOCAL_API', route, type(exc).__name__)
