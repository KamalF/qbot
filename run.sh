#!/bin/sh

DIR=$(dirname $0)

if [ ! -f "$DIR/config.sh" ]; then
    echo "
It appears you do not have a config.sh file.
You need to configure the bot before running it:

$ cp config.sh.tpl config.sh
$ $EDITOR config.sh
"
    exit 1
fi

. $DIR/config.sh
$DIR/bin/hubot -a "${QBOT_ADAPTER:-slack}"
