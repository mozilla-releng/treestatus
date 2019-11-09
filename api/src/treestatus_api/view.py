# -*- coding: utf-8 -*-
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

import os

import flask

ROOT_DIR = os.path.dirname(__file__)
STATIC_DIR = os.path.join(ROOT_DIR, 'static')


def static_handler(filename):
    if filename in ['ui/', 'ui/index.html']:
        return flask.redirect('/static/ui')
    elif filename == 'ui' or not (filename.endswith('.css') or
                                  filename.endswith('.js') or
                                  filename.endswith('.svg') or
                                  filename.endswith('.woff') or
                                  filename.endswith('.woff2') or
                                  filename.endswith('.eot') or
                                  filename.endswith('.ttf') or
                                  filename.endswith('.ico') or
                                  filename.endswith('.html') or
                                  filename.endswith('.txt')
                                  ):
        return flask.Response(index_html(), mimetype='text/html')
    elif filename.startswith('ui/main-') and filename.endswith('.css'):
        return flask.Response(main_css(filename), mimetype='text/css')
    return flask.send_from_directory(STATIC_DIR, filename)


def main_css(filename):
    with open(os.path.join(STATIC_DIR, filename)) as f:
        css = f.read()
    return css.replace('url(/', 'url(/static/ui/')


def index_html():
    with open(os.path.join(STATIC_DIR, 'ui/index.html')) as f:
        index = f.read()

    app = flask.current_app
    root_url = '/static/ui'

    body_attrs = ''
    for attr, attr_value in [
            ('release-version', app.config['VERSION']),
            ('release-channel', app.config['ENV']),
            ('treestatus-api-url', app.config['APP_URL']),
            ]:
        body_attrs += f'data-{attr}="{attr_value}" '

    for from_, to_ in [('src="/main', f'src="{root_url}/main'),
                       ('href="/main', f'href="{root_url}/main'),
                       ('<body', f'<body {body_attrs.strip()}'),
                       ('<head>', '<head>\n  <link rel="shortcut icon" href="/static/ui/favicon.ico">'),
                       ]:
        index = index.replace(from_, to_)
    return index
