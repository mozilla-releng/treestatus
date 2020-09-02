# -*- coding: utf-8 -*-
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

import datetime

import flask
import kombu

import treestatus_api.lib.dockerflow
import treestatus_api.lib.log

logger = treestatus_api.lib.log.get_logger(__name__)

DEFAULT_CONFIG = dict(PULSE_HOST="pulse.mozilla.org", PULSE_PORT=5671, PULSE_VIRTUAL_HOST="/", PULSE_USE_SSL=True, PULSE_CONNECTION_TIMEOUT=5)


class Pulse(object):
    """Documentation about Pulse

    https://wiki.mozilla.org/Auto-tools/Projects/Pulse
    https://wiki.mozilla.org/Auto-tools/Projects/Pulse/Exchanges
    """

    def __init__(self, host, port, user, password, virtual_host="/", ssl=True, connect_timeout=5):
        self.connection = kombu.Connection(
            hostname=host, port=port, userid=user, password=password, virtual_host=virtual_host, ssl=ssl, connect_timeout=connect_timeout
        )

    def ping(self):
        with self.connection as connection:
            if connection.connected:
                connection.close()
                connection.connect()
            else:
                connection.connect()
                connection.close()

    def publish(self, exchange_name, routing_key, payload):
        with self.connection as connection:
            if not connection.connected:
                connection.connect()

            exchange = kombu.Exchange(exchange_name, type="topic")
            message = {
                "payload": payload,
                "_meta": {"exchange": exchange_name, "routing_key": routing_key, "serializer": "json", "sent": datetime.datetime.utcnow().isoformat()},
            }

            producer = connection.Producer(exchange=exchange, routing_key=routing_key, serializer="json")
            producer.publish(message)
            connection.close()


def init_app(app):
    return Pulse(
        app.config.get("PULSE_HOST", DEFAULT_CONFIG["PULSE_HOST"]),
        app.config.get("PULSE_PORT", DEFAULT_CONFIG["PULSE_PORT"]),
        app.config.get("PULSE_USER"),
        app.config.get("PULSE_PASSWORD"),
        app.config.get("PULSE_VIRTUAL_HOST", DEFAULT_CONFIG["PULSE_VIRTUAL_HOST"]),
        app.config.get("PULSE_USE_SSL", DEFAULT_CONFIG["PULSE_USE_SSL"]),
        app.config.get("PULSE_CONNECTION_TIMEOUT", DEFAULT_CONFIG["PULSE_CONNECTION_TIMEOUT"]),
    )


def app_heartbeat():
    try:
        flask.current_app.pulse.ping()
    except Exception as e:
        logger.exception(e)
        raise treestatus_api.lib.dockerflow.HeartbeatException("Cannot connect to pulse the service.")
