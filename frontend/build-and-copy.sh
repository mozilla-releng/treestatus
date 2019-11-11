#!/bin/sh

set -e

FROM=./result
TO=./../api/src/treestatus_api/static/ui

rm -f $FROM
nix-build -o $FROM

rm -f $TO/*
cp $FROM/* $TO/ -R
sudo chown rok:users $TO -R
chmod +rw $TO -R


