#!/bin/sh

set -e

RESULT=./result
OUT=./out
TO=./../api/src/treestatus_api/static/ui

rm -f $RESULT
rm -rf $OUT
mkdir $OUT
echo "Building frontend..."
docker container rm treestatus || :
docker run --name treestatus -v $(pwd):/src nixos/nix sh -c "cd /src && nix-build -o $RESULT"
# pipe through tar to avoid permission denied issues
docker container cp treestatus:$(readlink $RESULT)/ - | tar -C $OUT --strip-components=1 -x
chmod 644 $OUT/*

rm -f $TO/*
cp -R $OUT/* $TO/
rm -rf $RESULT $OUT

echo "Done"
echo "Please commit the changes located in $TO"
