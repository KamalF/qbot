# Handle Redmine webhook notifications
#
# Initially copied from https://github.com/tenten0213/hubot-redmine-notifier
#
# Ported (2026-07) from the old suer/itnode redmine_webhook plugin to
# Redmine 7.0 NATIVE webhooks. The native payload differs:
#   { "type": "issue.created|issue.updated|issue.deleted",
#     "timestamp": "<iso8601>",
#     "data": { "issue": { ...standard REST API issue JSON... } } }
# For "issue.updated", data.issue.journal = { user:{id,name}, notes, details:[...] }.
#
# Unlike the old plugin, the native payload only carries {id,name} for users and
# {id,name} for the project (no login, no firstname/lastname, no watchers, no
# project identifier, no issue url). qbot needs logins (to DM users), the project
# identifier (to route to a Slack channel via `link_project`), and watchers, so we
# enrich from the Redmine REST API.
#
# Configuration (Redmine 7.0+):
#   Admin -> Settings -> API -> enable webhooks.
#   Each subscriber (or a shared service account) adds a webhook under
#   My account -> Webhooks: URL http://<hubot-host>:<hubot-port>/hubot/redmine-notify,
#   events `issue.created` + `issue.updated`, and the projects to watch. The webhook
#   owner needs the `use_webhooks` permission on those projects.
#   Set HUBOT_REDMINE_URL (e.g. https://support.intersec.com) and
#   HUBOT_REDMINE_API_KEY so qbot can resolve the fields above.
#
#   HUBOT_REDMINE_API_KEY does NOT need to be an admin key. A non-admin service
#   account is enough, verified on Redmine 7.0: /users/:id.json exposes `login` to
#   any authenticated caller (UsersController is `require_admin, except: :show`,
#   and unlike `mail` or `status` the `login` field carries no admin guard), and
#   the project identifier plus watchers need only `view_issues` and
#   `view_issue_watchers` on the project.
#
#   The service account must be a MEMBER of every project it receives webhooks
#   for. It can only resolve users who share a visible project with it, so
#   otherwise /users/:id.json returns 404, the author never resolves, and the
#   notification is dropped silently (see `return unless author?` below).
#
# URLS:
#   POST /hubot/redmine-notify

'use strict'

notifier = require('./notif-handler.coffee')

REDMINE_URL = (process.env.HUBOT_REDMINE_URL or '').replace(/\/+$/, '')
REDMINE_API_KEY = process.env.HUBOT_REDMINE_API_KEY

class RedmineNotifier extends notifier.NotifHandler
  constructor: ->
    super("redmine-notify")

  # Returns { action, issue } for a native issue.* event, or null otherwise.
  parse: (body) ->
    return null unless body? and body.type? and body.data? and body.data.issue?
    [model, verb] = body.type.split('.')
    return null unless model == 'issue'
    # map native verbs onto the vocabulary event-handler already understands
    action = if verb == 'created' then 'opened' else verb
    { action: action, issue: body.data.issue }

module.exports = (robot) ->
  robot.redmine_notifier = new RedmineNotifier

  # GET a Redmine REST API path and hand the parsed JSON (or null) to cb.
  api = (path, cb) ->
    unless REDMINE_URL and REDMINE_API_KEY
      robot.logger.error "redmine-notify: HUBOT_REDMINE_URL / HUBOT_REDMINE_API_KEY not set"
      return cb(null)
    robot.http("#{REDMINE_URL}#{path}")
      .header('X-Redmine-API-Key', REDMINE_API_KEY)
      .header('Accept', 'application/json')
      .get() (err, res, bodyText) ->
        if err? or res.statusCode >= 300
          robot.logger.error "redmine-notify api #{path}: #{err or res.statusCode}"
          return cb(null)
        try
          cb(JSON.parse(bodyText))
        catch e
          robot.logger.error "redmine-notify api #{path}: bad JSON (#{e})"
          cb(null)

  # Resolve a user id -> { id, login, firstname, lastname, name } (or null).
  resolveUser = (id, cb) ->
    return cb(null) unless id?
    api "/users/#{id}.json", (data) -> cb(data?.user or null)

  robot.router.post "/hubot/redmine-notify", (req, res) ->
    res.end('')
    body = robot.redmine_notifier.dataFetch(req, robot)
    parsed = robot.redmine_notifier.parse(body)
    return unless parsed?
    { action, issue } = parsed
    return unless action in ['opened', 'updated']

    journal = issue.journal
    updaterId = if journal? and journal.user? then journal.user.id else issue.author?.id

    # 1) project identifier (channel routing key), 2) watchers, 3) user logins
    api "/projects/#{issue.project.id}.json", (projData) ->
      projectIdentifier =
        projData?.project?.identifier or String(issue.project.id)

      api "/issues/#{issue.id}.json?include=watchers", (issData) ->
        watcherStubs = issData?.issue?.watchers or []

        ids = {}
        ids[issue.author.id] = true if issue.author?.id?
        ids[issue.assigned_to.id] = true if issue.assigned_to?.id?
        ids[updaterId] = true if updaterId?
        ids[w.id] = true for w in watcherStubs when w.id?

        resolved = {}
        pending = Object.keys(ids).length

        finish = ->
          author = resolved[issue.author?.id]
          assignee = resolved[issue.assigned_to?.id]
          updater = resolved[updaterId] or author
          return unless author?   # cannot notify without at least the author login

          details = {
            type: 'redmine-notif'
            action: action
            assignee: assignee
            author: author
            updater: updater
            issueId: issue.id
            subject: issue.subject
            description: issue.description
            status: issue.status.name
            tracker: issue.tracker.name
            priority: issue.priority.name
            project: issue.project.name
            project_id: projectIdentifier
            url: "#{REDMINE_URL}/issues/#{issue.id}"
            watchers: (resolved[w.id] for w in watcherStubs when resolved[w.id]?)
            notes: if journal? then journal.notes else undefined
            # native payload has no rendered journal HTML; event-handler falls
            # back to `notes`. The structured journal.details are available on
            # `issue.journal.details` if a richer message is wanted later.
            journal_html: undefined
          }
          robot.emit 'redmine-notif', details

        if pending == 0
          finish()
        else
          for id of ids
            do (id) ->
              resolveUser id, (u) ->
                resolved[id] = u if u?
                pending -= 1
                finish() if pending == 0
