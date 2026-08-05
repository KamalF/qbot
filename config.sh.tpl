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

# Redmine 7.0 native webhooks: base URL and an API key. Required by
# scripts/redmine-handler.coffee to resolve user logins, watchers and the
# project identifier, which the native webhook payload does not include.
#
# This does NOT need to be an admin key. Use a dedicated non-admin service
# account with `view_issues` and `view_issue_watchers` on the watched projects,
# and make it a member of each of them so user lookups resolve.

export HUBOT_REDMINE_URL=
export HUBOT_REDMINE_API_KEY=
