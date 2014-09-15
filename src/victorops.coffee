#==========================================================================
# Copyright 2014 VictorOps, Inc.
# https://github.com/victorops/hubot-victorops/blob/master/LICENSE
#==========================================================================

Readline = require 'readline'
WebSocket = require 'ws'
{Adapter,Robot,TextMessage} = require 'hubot'

class Shell

  constructor: (robot, vo) ->
    @robot = robot
    stdin = process.openStdin()
    stdout = process.stdout
    @vo = vo
    @user = @robot.brain.userForId '1', name: 'Shell', room: 'Shell'

    process.on 'uncaughtException', (err) =>
      @robot.logger.error err.stack

    @repl = Readline.createInterface stdin, stdout, null

    @repl.on 'close', =>
      console.log()
      stdin.destroy()
      @robot.shutdown()
      process.exit 0

    @repl.on 'line', (buffer) =>
      if buffer.trim().length > 0
        @repl.close() if buffer.toLowerCase() is 'exit'
        @vo.sendToVO @vo.chat(buffer)
        @robot.receive new TextMessage @user, buffer, 'messageId'
      @repl.prompt()

    @repl.setPrompt "#{@robot.name} >> "
    @repl.prompt()

  prompt: ->
    @repl.prompt()


class VictorOps extends Adapter

  constructor: (robot) ->
    @wsURL = @envWithDefault( process.env.HUBOT_VICTOROPS_URL, 'wss://chat.victorops.com/chat' )
    @password = process.env.HUBOT_VICTOROPS_KEY
    @robot = robot
    @loggedIn = false
    @loginAttempts = @getLoginAttempts()
    @loginRetryInterval = @envIntWithDefault( process.env.HUBOT_VICTOROPS_LOGIN_INTERVAL, 5 ) * 1000
    super robot

  envWithDefault: (envVar, defVal) ->
    if (envVar?)
      envVar
    else
      defVal

  envIntWithDefault: (envVar, defVal) ->
    parseInt( @envWithDefault( envVar, "#{defVal}" ), 30 )

  getLoginAttempts: () ->
    @envIntWithDefault( process.env.HUBOT_VICTOROPS_LOGIN_ATTEMPTS, 15 )

  generateUUID: ->
    d = new Date().getTime()
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) ->
      r = (d + Math.random()*16)%16 | 0;
      v = if c is 'x' then r else (r & 0x3|0x8)
      v.toString(16)
    )

  login: () ->
    msg = {
      "MESSAGE": "ROBOT_LOGIN_REQUEST_MESSAGE",
      "TRANSACTION_ID": @generateUUID(),
      "PAYLOAD": {
          "PROTOCOL": "1.0",
          "NAME": @robot.name,
          "KEY": @password,
          "DEVICE_NAME": "hubot"
      }
    }

  chat: (msg) ->
    msg = {
      "MESSAGE": "CHAT_ACTION_MESSAGE",
      "TRANSACTION_ID": @generateUUID(),
      "PAYLOAD": {
          "CHAT": {
              "IS_ONCALL": false,
              "IS_ROBOT": true,
              "TEXT": msg,
              "ROOM_ID": "*"
          }
      }
    }

  sendToVO: (js) ->
    m = JSON.stringify(js)
    message = "VO-MESSAGE:" + m.length + "\n" + m
    console.log "send to chat server: #{message}"
    @ws.send( message )

  send: (user, strings...) ->
    js = @chat( strings.join "\n" )
    @sendToVO( @chat( strings.join "\n" ) )

  reply: (user, strings...) ->
    @send str for str in strings

  respond: (regex, callback) ->
    @hear regex, callback

  connectToVO: () ->
    _ = @

    if @ws?
      @ws.close()

    if @loginAttempts-- <= 0
      console.log "Unable to connect; giving up."
      process.exit 1

    console.log "Attempting connection to VictorOps at #{@wsURL}..."
    _.loggedIn = false

    @ws = new WebSocket(@wsURL)

    @ws.on "open", () ->
      _.sendToVO( _.login() )

    @ws.on "message", (message) ->
      _.receive_ws( message )

    @ws.on 'close', () ->
      _.loggedIn = false
      console.log 'disconnected!'

  # Transform incident notifications into hubot messages too
  rcvIncidentMsg: ( user, entity ) ->
    hubotMsg = "VictorOps entitystate #{JSON.stringify(entity)}"
    console.log hubotMsg
    @receive new TextMessage user, hubotMsg

  receive_ws: (msg) ->
    data = JSON.parse( msg.replace /VO-MESSAGE:[^\{]*/, "" )

    console.log "Received #{data.MESSAGE}"
    # console.log msg

    if data.MESSAGE == "CHAT_NOTIFY_MESSAGE" && data.PAYLOAD.CHAT.USER_ID != @robot.name
      user = @robot.brain.userForId data.PAYLOAD.CHAT.USER_ID
      @receive new TextMessage user, data.PAYLOAD.CHAT.TEXT

    else if data.MESSAGE == "ENTITY_STATE_NOTIFY_MESSAGE"
      user = @robot.brain.userForId "VictorOps"
      @rcvIncidentMsg user, entity for entity in data.PAYLOAD.SYSTEM_ALERT_STATE_LIST

    else if data.MESSAGE == "LOGIN_REPLY_MESSAGE"
      if data.PAYLOAD.STATUS != "200"
        console.log "Failed to log in: #{data.PAYLOAD.DESCRIPTION}"
      else
        @loginAttempts = @getLoginAttempts()
        @loggedIn = true

    @shell.prompt()


  run: ->
    @shell = new Shell( @robot, @ )

    @connectToVO()

    setInterval =>
      if ( ! @loggedIn )
        @connectToVO()
    , @loginRetryInterval

    @emit "connected"

exports.VictorOps = VictorOps

exports.use = (robot) ->
  new VictorOps robot
