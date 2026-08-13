# Handle Gerrit webhook notifications
#
# Configuration:
#   GERRIT_URL           - base URL of the gerrit instance
#   GERRIT_HTTP_USER     - username of the bot gerrit account
#   GERRIT_HTTP_PASSWORD - HTTP password of the bot gerrit account
#                          (Settings > HTTP credentials, not the OIDC one)

'use strict'

notifier = require('./notif-handler.coffee')

b64 = (str) ->
  if Buffer.from?
    Buffer.from(str).toString('base64')
  else
    new Buffer(str).toString('base64')

# Query the gerrit REST API for account information, replacing the
# former LDAP lookups (gerrit now authenticates through OIDC).
# Calls back with the parsed JSON, or null on any error.
gerrit_api = (robot, path, cb) ->
  url = process.env.GERRIT_URL
  user = process.env.GERRIT_HTTP_USER
  password = process.env.GERRIT_HTTP_PASSWORD
  if not url or not user or not password
    robot.logger.error 'gerrit: GERRIT_URL, GERRIT_HTTP_USER and ' +
                       'GERRIT_HTTP_PASSWORD must be set'
    return cb null
  robot.http("#{url.replace /\/+$/, ''}/a#{path}")
    .header('Authorization', "Basic #{b64("#{user}:#{password}")}")
    .get() (err, res, body) ->
      if err or res.statusCode >= 300
        robot.logger.error "gerrit: GET #{path} failed: " +
                           "#{err ? 'HTTP ' + res.statusCode}"
        return cb null
      try
        # strip the XSSI prefix before parsing
        cb JSON.parse body.replace(/^\)\]\}'/, '')
      catch e
        robot.logger.error "gerrit: GET #{path}: invalid JSON"
        cb null

# Extract the email from a "Name <email>" or "Name (email)" string
mail_of = (user) ->
  split = user.split(/\<|\>/)
  if split.length < 2
    split = user.split(/\(|\)/)
  split[1]

# Get the gerrit username matching a "Name <email>" string.
# Calls back with (username or '', email).
get_user_login = (robot, user, finished) ->
  mail = mail_of user
  path = "/accounts/?q=email:#{encodeURIComponent(mail)}&n=1&o=DETAILS"
  gerrit_api robot, path, (accounts) ->
    finished accounts?[0]?.username ? '', mail

# Get the email of a gerrit username
get_user_mail = (robot, username, finished) ->
  gerrit_api robot, "/accounts/#{encodeURIComponent(username)}/detail", (account) ->
    finished account?.email

# Resolve a list of gerrit usernames to [{login, mail}] objects
resolve_reviewers = (robot, logins, finished) ->
  users = []
  remaining = logins.length
  return finished users if remaining == 0
  logins.forEach (login) ->
    get_user_mail robot, login, (mail) ->
      users.push { login: login, mail: mail }
      remaining -= 1
      finished users if remaining == 0

class GerritNotifier extends notifier.NotifHandler
  constructor: ->
    super("gerrit-notify")

  process: (req, res, robot) ->
    res.end('')
    data = @dataFetch(req, robot)

    get_user_login robot, data.change_owner, (login, mail) ->
      data.nickname = login
      data.owner_mail = mail
      get_user_login robot, data.author, (login) ->
        data.emitter = login
        resolve_reviewers robot, (data.reviewers ? []), (users) ->
          data.reviewer_users = users
          robot.emit 'gerrit-notif', data

module.exports = (robot) ->
  robot.gerrit_notifier = new GerritNotifier
  robot.router.post "/hubot/gerrit-notify", (req, res) ->
    details = robot.gerrit_notifier.process req, res, robot
