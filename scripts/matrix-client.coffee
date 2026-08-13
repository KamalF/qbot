# Small Matrix client used to mirror notifications on a Matrix homeserver.
#
# Uses the plain client-server HTTP API (no SDK, no E2E encryption):
# rooms the bot posts to must be unencrypted.
#
# Configuration:
#   MATRIX_HOMESERVER_URL - base URL of the homeserver (https://matrix.example.com)
#   MATRIX_ACCESS_TOKEN   - access token of the bot user
#   MATRIX_SERVER_NAME    - server name used to build DM user ids:
#                           @<email local part>:<server_name>

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

# Build [plain_body, html_body] for matrix from the slack-style
# text + attachments message
format_notif = (text, msg) ->
  plain = text
  html = "<p>#{escape_html(text)}</p>"

  attachments = msg?.attachments ? []
  for att in attachments
    quote = ''
    if att.title?
      plain += "\n#{att.title}"
      title = escape_html(att.title)
      if att.title_link?
        plain += " (#{att.title_link})"
        quote += "<b><a href=\"#{escape_html(att.title_link)}\">#{title}</a></b>"
      else
        quote += "<b>#{title}</b>"
    if att.text? and att.text.length > 0
      plain += "\n#{att.text}"
      quote += '<br/>' if quote.length > 0
      quote += slack_to_html(att.text)
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
    @url = (process.env.MATRIX_HOMESERVER_URL ? '').replace /\/+$/, ''
    @token = process.env.MATRIX_ACCESS_TOKEN
    @server_name = process.env.MATRIX_SERVER_NAME

  enabled: -> @url.length > 0 and @token? and @token.length > 0

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
        @robot.logger.error "matrix: #{method} #{path}: HTTP #{res.statusCode}: #{resp_body}"
        return cb? new Error("matrix HTTP #{res.statusCode}"), data
      cb? null, data

    switch method
      when 'GET' then req.get() handler
      when 'POST' then req.post(JSON.stringify(body ? {})) handler
      when 'PUT' then req.put(JSON.stringify(body ? {})) handler

  # Resolve a room alias or id to a room id, joining the room if
  # needed. Results are cached in the brain.
  join: (room, cb) ->
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

  # Send a DM to the matrix user matching an email address
  # (@<email local part>:<server_name>), creating an unencrypted
  # direct room on first use. The room is cached in the brain and
  # reused for all subsequent DMs to this user.
  sendDM: (mail, plain, html) ->
    return if not @enabled()
    if not @server_name? or @server_name.length == 0
      @robot.logger.debug 'matrix: MATRIX_SERVER_NAME not set, cannot DM'
      return
    if not mail? or mail.indexOf('@') <= 0
      @robot.logger.debug "matrix: no email available, cannot DM (#{mail})"
      return
    localpart = mail.split('@')[0].toLowerCase()
    user_id = "@#{localpart}:#{@server_name}"
    key = "matrix.dm.#{user_id}"
    room_id = @robot.brain.get key
    if room_id?
      return @sendToRoomId room_id, plain, html
    @api 'POST', '/createRoom', {
      is_direct: true
      preset: 'trusted_private_chat'
      invite: [user_id]
    }, (err, data) =>
      return if err
      @robot.brain.set key, data.room_id
      @sendToRoomId data.room_id, plain, html

module.exports = { MatrixClient, format_notif, is_matrix_room }
