#!/bin/sh

# Mandatory:
#
# API token for the bot entity

export HUBOT_SLACK_TOKEN=

# Redis URL for data saving/reloading

export REDIS_URL=

#
# Optional:
#

# set the log level, use debug for useful logs :)

export HUBOT_LOG_LEVEL=

# If set to 1, notifications are sent in DMs to the notified people.
# Otherwise, notifications are redirected on the channel #qbot-dev

export QBOT_PROD_READY=

# Path to the JSON file linking Redmine projects to notification channels
# (slack channels and/or matrix rooms), see project-links.json.tpl.
# Defaults to ./project-links.json. The file is re-read on each
# notification, no restart needed.

export QBOT_PROJECT_LINKS=

# Matrix support (optional): notifications are mirrored on a matrix
# homeserver when both variables below are set.
# Rooms must NOT be end-to-end encrypted (the bot does not support E2EE).

# Server name of the matrix homeserver, e.g. matrix.intersec.com.
# The API is reached at https://<server_name>, and user ids for DMs are
# built from the user's email: @<email local part>:<server_name>

export MATRIX_SERVER_NAME=

# Access token of the bot user (from POST /_matrix/client/v3/login)

export MATRIX_ACCESS_TOKEN=

# Room receiving all matrix notifications when QBOT_PROD_READY is not 1.
# The server name is appended if missing: '#qbot-dev' means
# '#qbot-dev:<MATRIX_SERVER_NAME>' (quote the value, it starts with #)

export QBOT_MATRIX_DEV_ROOM=

# Base URL of the matrix client API, only needed when it is not served
# at https://<MATRIX_SERVER_NAME> (see /.well-known/matrix/client)

export MATRIX_HOMESERVER_URL=
