#!/bin/bash
set -e

EXTRA_ARGS=""

if [ "$ENV" == "localdev" ]
then
    MY_DIR=$(realpath $(dirname $0))
    CERT="${MY_DIR}/cert.pem"
    KEY="${MY_DIR}/key.pem"

    # Local development only - we don't want these in deployed environments
    EXTRA_ARGS="--bind $HOST:$PORT --workers 3 --timeout 3600 --reload --reload-engine=poll --certfile=$CERT --keyfile=$KEY"
fi

exec gunicorn treestatus_api.flask:app --log-file - $EXTRA_ARGS
