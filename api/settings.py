# -*- coding: utf-8 -*-
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

import base64
import copy
import functools
import os

import treestatus_api.lib.pulse
import treestatus_api.lib.security


def compose(*functions):
    return functools.reduce(lambda f, g: lambda x: f(g(x)), functions, lambda x: x)

def required(variable):
    if variable in os.environ:
        return os.environ[variable]
    raise RuntimeError(f'{variable} environment variable is required')

def as_int(default):
    return compose(int, default)

def as_bool(default):
    return compose(
        lambda x: str(x).lower() in ['1', 'true'],
        default,
    )

def as_list(default):
    return compose(
        lambda x: [i.strip() for i in x.split(';')],
        default,
    )

def as_dict(default):
    return compose(
        lambda x: {
            i.split(':')[0].strip(): i.split(':')[1].strip()
            for i in x.split(';')
        },
        default,
    )

def b64decode(default):
    return compose(base64.b64decode, default)

def default(default_value):
    def _default(variable):
        if variable in os.environ:
            return os.environ[variable]
        return default_value
    return _default


# -- LOAD SECRETS -------------------------------------------------------------

secrets = {
    item: default(item)
    for (item, default) in [
        # environment in which we should run this application
        ('ENV', required),

        # taskcluster client that is used to send notifications, for more details
        # look at src/treestatus_api/__init__.py and check also at api/SCOPES.rst
        # what are needed for this client
        ('TASKCLUSTER_ROOT_URL', default('https://taskcluster.net')),
        ('TASKCLUSTER_CLIENT_ID', required),
        ('TASKCLUSTER_ACCESS_TOKEN', required),

        # treestatus_api specific secrets, for more details look at src/treestatus_api/api.py
        ('PULSE_TREESTATUS_ENABLE', as_bool(default(False))),
        ('STATUSPAGE_ENABLE', as_bool(default(True))),
        ('STATUSPAGE_TOKEN', required),  # < -authentication token
        ('STATUSPAGE_PAGE_ID', required),  # < -id of the page which we are interacting with
        ('STATUSPAGE_COMPONENTS', as_dict(required)),  # < -a tree_name= > component_id mapping
        ('STATUSPAGE_NOTIFY_ON_ERROR', required),  # < -email to where to send when error happens
        ('STATUSPAGE_TAGS', as_list(required)),  # < -list of tags which will trigger creation of status page incident

        # Database connection string, for more details look at src/treestatus_api/lib/db.py
        ('DATABASE_URL', required),

        # Log errors to sentry, for more details look at src/treestatus_api/lib/log.py
        ('SENTRY_DSN', default(None)),

        # Authentication, for more details look at src/treestatus_api/lib/auth.py
        ('TASKCLUSTER_AUTH', as_bool(default(True))),
        ('SECRET_KEY', b64decode(required)),

        # Cors, for more details look at src/treestatus_api/lib/cors.py
        ('CORS_ORIGINS', default('*')),
        ('CORS_RESOURCES', default('*')),

        # Security, for more details look at src/treestatus_api/lib/security.py
        ('SECURITY_CSP_REPORT_URI', default(None)),

        # Pulse, for more details look at src/treestatus_api/lib/pulse.py
        ('PULSE_USER', required),
        ('PULSE_PASSWORD', required),
        ('PULSE_HOST', default(treestatus_api.lib.pulse.DEFAULT_CONFIG['PULSE_HOST'])),
        ('PULSE_PORT', as_int(default(treestatus_api.lib.pulse.DEFAULT_CONFIG['PULSE_PORT']))),
        ('PULSE_VIRTUAL_HOST', default(treestatus_api.lib.pulse.DEFAULT_CONFIG['PULSE_VIRTUAL_HOST'])),
        ('PULSE_USE_SSL', as_bool(default(treestatus_api.lib.pulse.DEFAULT_CONFIG['PULSE_USE_SSL']))),
        ('PULSE_CONNECTION_TIMEOUT', as_int(default(treestatus_api.lib.pulse.DEFAULT_CONFIG['PULSE_CONNECTION_TIMEOUT']))),

        # Cache, for more details look at src/treestatus_api/lib/cache.py
        ('CACHE_TYPE', default('simple')),
        ('REDIS_URL', default(None)),
    ]
}

locals().update(secrets)

APP_URL = 'https://treestatus.mozilla-releng.net'
if secrets['ENV'] == 'localdev':
    APP_URL = 'https://localhost:8002'
elif secrets['ENV'] == 'dev':
    APP_URL = 'https://dev.treestatus.mozilla-releng.net'
elif secrets['ENV'] == 'staging':
    APP_URL = 'https://stage.treestatus.mozilla-releng.net'

SECURITY = copy.deepcopy(treestatus_api.lib.security.DEFAULT_CONFIG)
for url in [TASKCLUSTER_ROOT_URL,
            APP_URL,
            ]:
    SECURITY['content_security_policy']['connect-src'] += f' {url}'

with open(os.path.join(os.path.dirname(__file__), 'version.txt')) as f:
    VERSION = f.read().strip()

SQLALCHEMY_TRACK_MODIFICATIONS = False
SQLALCHEMY_DATABASE_URI = secrets['DATABASE_URL']

if ENV == 'localdev':
    SQLALCHEMY_ECHO = True

CACHE = dict()
CACHE['CACHE_DEFAULT_TIMEOUT'] = 60 * 5
CACHE['CACHE_KEY_PREFIX'] = 'treestatus_api_'
CACHE['CACHE_TYPE'] = secrets['CACHE_TYPE']

if secrets['REDIS_URL']:
    CACHE['CACHE_TYPE'] = 'redis'
    CACHE['CACHE_REDIS_URL'] = secrets['REDIS_URL']
