#!/usr/bin/env bash

set -o xtrace

DIR=~/ink.codes.fileproxy

if [ -d $DIR ];
then
  echo "aborting: directory exists: WARNING: script will remove ${DIR}"
  exit 1;
fi

node server &
pid=$!
swift test
rm -rf $DIR
kill $pid
