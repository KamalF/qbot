'use strict'

util = require('util')

get_color_from_tracker = (tracker) ->
  switch tracker
    when 'Bug' then 'danger'
    when 'Feature', 'Main' then 'good'
    else '#6878cc'

get_color_from_comment = (comment) ->
  if /Verified-1/.test(comment)
    return '#323232'
  else if /Verified\+1/.test(comment)
    return '#439fe0'
  else if /Code-Review-2/.test(comment)
    return 'danger'
  else if /Code-Review-1/.test(comment)
    return 'warning'
  else if /Code-Review\+1/.test(comment)
    return 'good'
  return '#8a2be2'

replace_html = (html) ->
  html = html.replace /<\/?strong>/g, "*"
  html = html.replace /<\/?i>/g, "`"
  html = html.replace /<\/?a[^>]*>/g, ""
  return html

module.exports = (robot) ->
  # Handle redmine notifications
  robot.on 'redmine-notif', (details) ->

    # Use description of the ticket if just opened,
    # update notes if updated
    if details.action == 'opened'
      content = details.description
    else if details.journal_html? and details.journal_html.length > 0
      replaced = details.journal_html.map replace_html
      content = replaced.join '\n'
    else
      content = details.notes
    content or= ''

    # Build a pretty message for the related ticket
    msg = {
      attachments: [
        {
          title: "#{details.tracker} ##{details.issueId}: #{details.subject}"
          title_link: details.url
          text: content
          fallback: ""
          fields: [
            {
               title: "Status"
               value: details.status
               short: true
            },
            {
               title: "Priority"
               value: details.priority
               short: true
            },
            {
               title: "Project"
               value: details.project
               short: true
            }
          ]
          color: get_color_from_tracker details.tracker
        }
      ]
      as_user: true
    }

    # assignee_name comes straight from the webhook payload, so the field
    # survives when the assignee is a group or an unresolvable user
    if details.assignee_name
      msg.attachments[0].fields.unshift({
        title: "Assignee"
        value: details.assignee_name
        short: true
      })

    text = "#{details.updater_name} has updated ##{details.issueId}"

    notified = {}
    # notify user if not updater and not already notified
    notify_user = (login) ->
      return unless login?
      if login != details.updater?.login and login not of notified
        robot.emit 'user-send', login, 'redmine', text, msg
        notified[login] = true

    # Send notification to assignee
    notify_user details.assignee?.login

    # Send notification to author
    notify_user details.author?.login

    # Send notification to watchers
    for idx,w of details.watchers
      notify_user w.login

    if details.action == 'opened' or (details.status_changed and details.status == 'New')
      if details.project_id?
        robot.emit 'channel-send', details.project_id, text, msg

  robot.on 'gerrit-notif', (details) ->
    # Build a pretty message for the related gerrit notif
    msg = {
      attachments: [
        {
          title: details.subject
          title_link: details.change_url
          text: details.comment
          color: get_color_from_comment details.comment
        }
      ]
      as_user: true
    }

    notify_user_gerrit = (login) ->
      if details.emitter
        text = details.author.replace /<.*>/, "@#{details.emitter}"
      else
        text = details.author

      robot.emit 'user-send', login, 'gerrit', text, msg

    # Send notification to owner of patch
    if details.author != details.change_owner
      notify_user_gerrit details.nickname
    if details.reviewers?
        for user in details.reviewers
            if user != details.emitter && user != details.nickname
                notify_user_gerrit user
