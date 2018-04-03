# Description:
#   Handle user subscriptions to various notifications
#
# Commands:
#   qbot redmine - Modify subscription to redmine notifications
#   qbot gerrit - Modify subscription to gerrit notifications
#
# Author:
#   vthib, yannKagan

'use strict'

# Match a user to the key holding the list of subscriptions to
# disable
get_user_nosubs_key = (nickname) -> "#{nickname}.nosubscriptions"


is_prod_ready = ->
  env = process.env.QBOT_PROD_READY
  return env? and env == '1'


fix_channel = (channel, text) ->
  if is_prod_ready()
    return [channel, text]
  else
    return ['#qbot-dev', "notification to #{channel}: #{text}"]

on_status = (type, robot, res) ->
    nickname = res.envelope.user.name
    nosubs = robot.brain.get(get_user_nosubs_key(nickname))
    if nosubs? and type in nosubs
      msg  = "You are not subscribed to #{type} notifications. "
      msg += "You're missing out! :sunglasses:\n"
      msg += "To subscribe, use the `#{type} subscribe` command"
    else
      msg  = "You are already subscribed to #{type} notifications. "
      msg += "What more could you want :upside_down_face:?\n"
      msg += "To unsubscribe, use the `#{type} unsubscribe` command"

    res.send msg


on_action = (cmd, nickname, type, robot, res) ->
  key = get_user_nosubs_key(nickname)
  nosubs = robot.brain.get(key)
  if not nosubs?
    nosubs = []

  if cmd == 'subscribe'
    index = nosubs.indexOf(type)
    if index == -1
      res.send "You are already subscribed to #{type} notifications."
      return
    nosubs.splice(index, 1)
    res.send "You will now receive #{type} notifications."
  else if cmd == 'unsubscribe'
    if type in nosubs
      res.send "You are not subscribed to #{type} notifications."
      return
    nosubs.push type
    res.send "You are no longer subscribed to #{type} notifications."
  else
    res.send "Unknown #{cmd} command."
    return

  robot.brain.set(key, nosubs)


module.exports = (robot) ->

  # Handle notifications
  robot.on 'user-send', (nickname, type, text, msg) ->
    [chan, text] = fix_channel "@#{nickname}", text

    # Check the user has signed up for this type of notifications
    nosubs = robot.brain.get(get_user_nosubs_key(nickname))
    if nosubs? and type in nosubs
      if is_prod_ready()
        robot.logger.debug "unsubscribed #{type} notif for @#{nickname}"
        return
      text = "unsubscribed #{type} " + text

    # send msg to user
    robot.adapter.client.web.chat.postMessage(chan, text, msg)


  # Redmine status
  robot.respond /redmine$/, (res) ->
    on_status('redmine', robot, res)

  # Redmine sub/unsub
  robot.respond /redmine (.*)/i, (res) ->
    cmd = res.match[1]
    nickname = res.envelope.user.name
    on_action(cmd, nickname, 'redmine', robot, res)

  # Gerrit status
  robot.respond /gerrit$/, (res) ->
    on_status('gerrit', robot, res)

  # Gerrit sub/unsub
  robot.respond /gerrit (.*)/i, (res) ->
    cmd = res.match[1]
    nickname = res.envelope.user.name
    on_action(cmd, nickname, 'gerrit', robot, res)
