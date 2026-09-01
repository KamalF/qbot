# Small Matrix client used to mirror notifications on a Matrix homeserver.
#
# Uses the plain client-server HTTP API (no SDK, no E2E encryption):
# rooms the bot posts to must be unencrypted.
#
# Configuration:
#   MATRIX_SERVER_NAME    - server name of the homeserver, used to build
#                           DM user ids: @<email local part>:<server_name>
#   MATRIX_ACCESS_TOKEN   - access token of the bot user
#   MATRIX_HOMESERVER_URL - optional, base URL of the client API when not
#                           served at https://<server_name>

'use strict'

escape_html = (str) ->
  return '' if not str?
  String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

# Convert the slack-flavored content built by event-handler
# (*bold*, `code`) into matrix HTML
slack_to_html = (str) ->
  escape_html(str)
    .replace(/\*([^*\n]+)\*/g, '<b>$1</b>')
    .replace(/`([^`\n]+)`/g, '<code>$1</code>')
    .replace(/\n/g, '<br/>')

# Slack attachment colors: the named ones use the slack palette,
# the others are already hex colors
SLACK_COLORS = {
  good: '#2eb886'
  warning: '#daa038'
  danger: '#e01e5a'
}

# Colored circles, with the color they are drawn with, to stand for the
# colored bar slack puts on the side of an attachment
COLOR_EMOJIS = [
  ['\u{1f534}', 0xdd, 0x2e, 0x44]
  ['\u{1f7e0}', 0xf4, 0x90, 0x0c]
  ['\u{1f7e1}', 0xfd, 0xcb, 0x58]
  ['\u{1f7e2}', 0x78, 0xb1, 0x59]
  ['\u{1f535}', 0x55, 0xac, 0xee]
  ['\u{1f7e3}', 0xaa, 0x8e, 0xd6]
  ['\u26ab',    0x31, 0x37, 0x3d]
]

# Pick the circle closest to a slack attachment color, null when the
# color is missing or not a color we can read
attachment_emoji = (color) ->
  return null if not color?
  hex = SLACK_COLORS[color] ? color
  return null if not /^#[0-9a-fA-F]{6}$/.test hex
  r = parseInt hex.substring(1, 3), 16
  g = parseInt hex.substring(3, 5), 16
  b = parseInt hex.substring(5, 7), 16
  best = null
  for [emoji, er, eg, eb] in COLOR_EMOJIS
    dr = r - er
    dg = g - eg
    db = b - eb
    dist = dr * dr + dg * dg + db * db
    if not best? or dist < best[1]
      best = [emoji, dist]
  return best[0]

# Slack folds long attachment texts behind a "Show more" button.
# Matrix HTML has no equivalent, so the text is cut instead and the
# reader is sent to the ticket for the rest.
MAX_TEXT_LINES = 8
MAX_TEXT_CHARS = 600

# Return [text, cut], cut telling whether something was dropped
truncate_text = (str) ->
  cut = false
  lines = str.split '\n'
  if lines.length > MAX_TEXT_LINES
    lines = lines[0...MAX_TEXT_LINES]
    cut = true
  out = lines.join '\n'
  if out.length > MAX_TEXT_CHARS
    # cut on a word boundary, the trailing word is likely partial
    out = out.substring(0, MAX_TEXT_CHARS).replace(/\s+\S*$/, '')
    cut = true
  return [out, cut]

# Build [plain_body, html_body] for matrix from the slack-style
# text + attachments message
format_notif = (text, msg) ->
  plain = text
  html = "<p>#{escape_html(text)}</p>"

  attachments = msg?.attachments ? []
  for att in attachments
    quote = ''
    # slack draws a colored bar on the side of the attachment; matrix
    # HTML has no styling, and clients paint links with their own
    # color, so a colored circle leads the title instead
    emoji = attachment_emoji att.color
    prefix = if emoji? then "#{emoji} " else ''
    if att.title?
      plain += "\n#{prefix}#{att.title}"
      title = escape_html(att.title)
      if att.title_link?
        plain += " (#{att.title_link})"
        quote += "#{prefix}<b><a href=\"#{escape_html(att.title_link)}\">" +
                 "#{title}</a></b>"
      else
        quote += "#{prefix}<b>#{title}</b>"
    if att.text? and att.text.length > 0
      [body, cut] = truncate_text att.text
      plain += "\n#{body}"
      quote += '<br/>' if quote.length > 0
      quote += slack_to_html(body)
      if cut
        if att.title_link?
          plain += "\n… (see the ticket)"
          quote += "<br/><a href=\"#{escape_html(att.title_link)}\">" +
                   '&hellip; (see the ticket)</a>'
        else
          plain += "\n…"
          quote += '<br/>&hellip;'
    fields = att.fields ? []
    for f in fields
      plain += "\n#{f.title}: #{f.value}"
      quote += '<br/>' if quote.length > 0
      quote += "<b>#{escape_html(f.title)}:</b> #{escape_html(f.value)}"
    html += "<blockquote>#{quote}</blockquote>"

  return [plain, html]

# A room is a matrix room id (!xxx:server) or alias (#xxx:server);
# slack channels (#xxx) have no ':'
is_matrix_room = (chan) -> /^[!#].+:.+/.test chan

txn_counter = 0

class MatrixClient
  constructor: (@robot) ->
    @server_name = process.env.MATRIX_SERVER_NAME
    @token = process.env.MATRIX_ACCESS_TOKEN
    url = process.env.MATRIX_HOMESERVER_URL
    url = "https://#{@server_name}" if not url? or url.length == 0
    @url = url.replace /\/+$/, ''

  enabled: ->
    @server_name? and @server_name.length > 0 and
      @token? and @token.length > 0

  api: (method, path, body, cb) ->
    req = @robot.http("#{@url}/_matrix/client/v3#{path}")
      .header('Authorization', "Bearer #{@token}")
      .header('Content-Type', 'application/json')

    handler = (err, res, resp_body) =>
      if err
        @robot.logger.error "matrix: #{method} #{path} failed: #{err}"
        return cb? err, null
      try
        data = JSON.parse resp_body
      catch e
        data = {}
      if res.statusCode >= 300
        # 404s are part of normal operation (missing account data)
        level = if res.statusCode == 404 then 'debug' else 'error'
        @robot.logger[level] "matrix: #{method} #{path}: HTTP #{res.statusCode}: #{resp_body}"
        return cb? new Error("matrix HTTP #{res.statusCode}"), data
      cb? null, data

    switch method
      when 'GET' then req.get() handler
      when 'POST' then req.post(JSON.stringify(body ? {})) handler
      when 'PUT' then req.put(JSON.stringify(body ? {})) handler

  # Resolve a room alias or id to a room id, joining the room if
  # needed. Results are cached in the brain.
  join: (room, cb) ->
    # qualify local aliases: '#qbot-test' -> '#qbot-test:<server_name>'
    room += ":#{@server_name}" if room.indexOf(':') == -1
    room_id = @robot.brain.get "matrix.room.#{room}"
    return cb null, room_id if room_id?
    @api 'POST', "/join/#{encodeURIComponent(room)}", {}, (err, data) =>
      return cb err, null if err
      @robot.brain.set "matrix.room.#{room}", data.room_id
      cb null, data.room_id

  # Send a message to a public room (id or alias)
  send: (room, plain, html) ->
    return if not @enabled()
    @join room, (err, room_id) =>
      return if err
      @sendToRoomId room_id, plain, html

  sendToRoomId: (room_id, plain, html) ->
    txn_counter += 1
    txn = "qbot#{Date.now()}.#{txn_counter}"
    msg = {
      msgtype: 'm.text'
      body: plain
    }
    if html?
      msg.format = 'org.matrix.custom.html'
      msg.formatted_body = html
    @api 'PUT', "/rooms/#{encodeURIComponent(room_id)}/send/m.room.message/#{txn}", msg, null

  # The bot's own user id, resolved lazily and kept in memory
  whoami: (cb) ->
    return cb @user_id if @user_id?
    @api 'GET', '/account/whoami', null, (err, data) =>
      return cb null if err
      @user_id = data.user_id
      cb @user_id

  # Get the user id -> [room ids] map of direct rooms from the bot
  # account's m.direct account data. Stored on the homeserver, it is
  # shared by all the bot instances, so DM rooms are never duplicated.
  # Calls back with the map ({} when not set yet), or null on error.
  get_direct_rooms: (cb) ->
    @whoami (user_id) =>
      return cb null if not user_id
      path = "/user/#{encodeURIComponent(user_id)}/account_data/m.direct"
      @api 'GET', path, null, (err, data) ->
        if err
          return cb (if data?.errcode == 'M_NOT_FOUND' then {} else null)
        cb data

  # Send a DM to the matrix user matching an email address
  # (@<email local part>:<server_name>), creating an unencrypted
  # direct room on first use and registering it in m.direct.
  sendDM: (mail, plain, html) ->
    return if not @enabled()
    if not mail? or mail.indexOf('@') <= 0
      @robot.logger.debug "matrix: no email available, cannot DM (#{mail})"
      return
    localpart = mail.split('@')[0].toLowerCase()
    user_id = "@#{localpart}:#{@server_name}"
    @get_direct_rooms (direct) =>
      # do not create a room blindly on errors, it could duplicate
      # an existing DM room
      return if not direct?
      rooms = direct[user_id]
      if rooms? and rooms.length > 0
        return @sendToRoomId rooms[0], plain, html
      @api 'POST', '/createRoom', {
        is_direct: true
        preset: 'trusted_private_chat'
        invite: [user_id]
      }, (err, data) =>
        return if err
        direct[user_id] = [data.room_id]
        path = "/user/#{encodeURIComponent(@user_id)}/account_data/m.direct"
        @api 'PUT', path, direct, null
        @sendToRoomId data.room_id, plain, html

module.exports = { MatrixClient, format_notif, is_matrix_room }
