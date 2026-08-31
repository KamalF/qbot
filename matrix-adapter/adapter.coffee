# Matrix chat adapter for hubot, using the plain client-server HTTP
# API through the shared MatrixClient (no E2EE). Messages are received
# with a /sync long-polling loop, and room invites are accepted
# automatically so users can DM commands to the bot.
#
# Uses the same MATRIX_* configuration as matrix-client.coffee.

'use strict'

{Adapter, TextMessage} = require 'hubot'

matrix = require './matrix-client.coffee'

# limit the initial sync payload: old events are skipped anyway
INITIAL_FILTER = JSON.stringify {room: {timeline: {limit: 1}}}

class MatrixAdapter extends Adapter
  run: ->
    @client = new matrix.MatrixClient(@robot)
    if not @client.enabled()
      @robot.logger.error 'matrix adapter: MATRIX_SERVER_NAME and ' +
                          'MATRIX_ACCESS_TOKEN must be set'
      return
    @client.whoami (user_id) =>
      if not user_id?
        @robot.logger.error 'matrix adapter: cannot fetch the bot user id'
        return
      @user_id = user_id
      @robot.logger.info "matrix adapter: connected as #{user_id}"
      @emit 'connected'
      @sync null

  sync: (since) ->
    qs = 'timeout=30000'
    if since?
      qs += "&since=#{encodeURIComponent(since)}"
    else
      qs += "&filter=#{encodeURIComponent(INITIAL_FILTER)}"
    @client.api 'GET', "/sync?#{qs}", null, (err, data) =>
      if err or not data?.next_batch?
        # wait a bit before retrying so a broken homeserver does not
        # turn this loop into a busy one
        setTimeout (=> @sync since), 10000
        return
      # skip the events of the initial sync, they are old news
      @process data if since?
      @sync data.next_batch

  process: (data) ->
    invites = data.rooms?.invite ? {}
    for room_id of invites
      @robot.logger.info "matrix adapter: invited to #{room_id}, joining"
      @client.api 'POST', "/join/#{encodeURIComponent(room_id)}", {}, null

    joined = data.rooms?.join ? {}
    for room_id, room of joined
      events = room.timeline?.events ? []
      for ev in events
        continue if ev.type != 'm.room.message'
        continue if ev.sender == @user_id
        continue if ev.content?.msgtype != 'm.text'
        @receive_event room_id, ev

  receive_event: (room_id, ev) ->
    # identify users by the local part of their matrix id, which
    # matches the local part of their email
    localpart = ev.sender.substring(1).split(':')[0]
    user = @robot.brain.userForId ev.sender
    user.name = localpart
    user.room = room_id
    @robot.receive new TextMessage(user, ev.content.body, ev.event_id)

  send: (envelope, strings...) ->
    for str in strings
      @client.send envelope.room, str

  reply: (envelope, strings...) ->
    for str in strings
      @client.send envelope.room, "#{envelope.user.name}: #{str}"

exports.use = (robot) -> new MatrixAdapter robot
