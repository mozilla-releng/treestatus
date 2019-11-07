# -*- coding: utf-8 -*-
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

import os

import taskcluster

import treestatus_api.config
import treestatus_api.models  # noqa


def create_app(config=None):
    app = treestatus_api.lib.flask.create_app(
        project_name=treestatus_api.config.PROJECT_NAME,
        config=config,
        extensions=[
            'log',
            'security',
            'cors',
            'api',
            'auth',
            'db',
            'cache',
            'pulse',
        ],
    )

    app.notify = taskcluster.Notify(
        options=dict(
            rootUrl=app.config['TASKCLUSTER_ROOT_URL'],
            credentials=dict(
                clientId=app.config['TASKCLUSTER_CLIENT_ID'],
                accessToken=app.config['TASKCLUSTER_ACCESS_TOKEN'],
            ),
        ),
    )

    app.api.register(os.path.join(os.path.dirname(__file__), 'api.yml'))

    return app
