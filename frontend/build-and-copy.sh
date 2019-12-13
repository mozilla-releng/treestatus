#!/bin/sh

set -e

FROM=./result
TO=./../api/src/treestatus_api/static/ui

rm -f $FROM
nix-build -o $FROM

rm -f $TO/*
cp $FROM/* $TO/ -R
sudo chown $(id -un): $TO -R
chmod +rw $TO -R


