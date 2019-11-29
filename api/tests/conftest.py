# -*- coding: utf-8 -*-
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

import os

import pytest


def get_app_config(extra_config):
    config = {"APP_TESTING": True, "SECRET_KEY": os.urandom(24)}
    config.update(extra_config)
    return config


def configure_app(app):
    """Configure flask application and ensure all mocks are in place
    """

    if hasattr(app, "db"):
        app.db.drop_all()
        app.db.create_all()


@pytest.fixture(scope="session")
def app():
    """Load treestatus_api in test mode
    """
    import treestatus_api

    config = get_app_config(
        {
            "SQLALCHEMY_DATABASE_URI": "sqlite://",
            "SQLALCHEMY_TRACK_MODIFICATIONS": False,
            "TASKCLUSTER_ROOT_URL": "http://taskcluster.mock",
            "TASKCLUSTER_CLIENT_ID": "something",
            "TASKCLUSTER_ACCESS_TOKEN": "something",
        }
    )
    app = treestatus_api.create_app(config)

    with app.app_context():
        configure_app(app)
        yield app
