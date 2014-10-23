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
        @vo.send( @robot.name, buffer )
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
    @pongLimit = @envIntWithDefault( process.env.HUBOT_VICTOROPS_LOGIN_PONG_LIMIT, 17000 )
    @rcvdStatusList = false
    super robot

  envWithDefault: (envVar, defVal) ->
    if (envVar?)
      envVar
    else
      defVal

  envIntWithDefault: (envVar, defVal) ->
    parseInt( @envWithDefault( envVar, "#{defVal}" ), 10 )

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

  sendToVO: (js, ws=@ws) ->
    m = JSON.stringify(js)
    message = "VO-MESSAGE:" + m.length + "\n" + m
    console.log "send to chat server: #{message}" if js.MESSAGE != "PING"
    ws.send( message )

  send: (user, strings...) ->
    js = @chat( strings.join "\n" )
    @sendToVO( @chat( strings.join "\n" ) )

  reply: (user, strings...) ->
    @send str for str in strings

  respond: (regex, callback) ->
    @hear regex, callback

  ping: () ->
    msg = {
      "MESSAGE": "PING",
      "TRANSACTION_ID": @generateUUID()
    }
    @sendToVO(msg)

  connectToVO: () ->
    _ = @

    @disconnect()

    if @loginAttempts-- <= 0
      console.log "Unable to connect; giving up."
      process.exit 1

    console.log "#{new Date()} Attempting connection to VictorOps at #{@wsURL}..."

    ws = new WebSocket(@wsURL)

    ws.on "open", () ->
      _.sendToVO( _.login(), @ )

    ws.on "error", (error) ->
      _.disconnect(error)

    ws.on "message", (message) ->
      _.receive_ws( message, @ )

    ws.on 'close', () ->
      _.loggedIn = false
      console.log 'WebSocket closed.'

  disconnect: (error) ->
    @lastPong = new Date()
    @loggedIn = false
    @rcvdStatusList = false
    if @ws?
      console.log("#{error} - disconnecting...")
      @ws.terminate()
      @ws = null

  # Transform incident notifications into hubot messages too
  rcvIncidentMsg: ( user, entity ) ->
    hubotMsg = "VictorOps entitystate #{JSON.stringify(entity)}"
    console.log hubotMsg
    @receive new TextMessage user, hubotMsg

  receive_ws: (msg, ws) ->
    data = JSON.parse( msg.replace /VO-MESSAGE:[^\{]*/, "" )

    console.log "Received #{data.MESSAGE}" if data.MESSAGE != "PONG"
    # console.log msg

    if data.MESSAGE == "CHAT_NOTIFY_MESSAGE" && data.PAYLOAD.CHAT.USER_ID != @robot.name
      user = @robot.brain.userForId data.PAYLOAD.CHAT.USER_ID
      @receive new TextMessage user, data.PAYLOAD.CHAT.TEXT.replace(/&quot;/g,'"')

    else if data.MESSAGE == "PONG"
      @lastPong = new Date()

    else if data.MESSAGE == "STATE_NOTIFY_MESSAGE" && data.PAYLOAD.USER_STATUS_LIST?
      @rcvdStatusList = true

    else if data.MESSAGE == "ENTITY_STATE_NOTIFY_MESSAGE"
      user = @robot.brain.userForId "VictorOps"
      @rcvIncidentMsg user, entity for entity in data.PAYLOAD.SYSTEM_ALERT_STATE_LIST

    else if data.MESSAGE == "LOGIN_REPLY_MESSAGE"
      if data.PAYLOAD.STATUS != "200"
        console.log "Failed to log in: #{data.PAYLOAD.DESCRIPTION}"
        @loggedIn = false
        ws.terminate()
      else
        @ws = ws
        @loginAttempts = @getLoginAttempts()
        @loggedIn = true
        setTimeout =>
          if ( ! @rcvdStatusList )
            console.log "Did not get status list in time; reconnecting..."
            @disconnect()
        , 5000

    @shell.prompt() if data.MESSAGE != "PONG"


  run: ->
    @shell = new Shell( @robot, @ )

    @connectToVO()

    setInterval =>
      pongInterval = new Date().getTime() - @lastPong.getTime()
      if ( ! @ws? || @ws.readyState != WebSocket.OPEN || ! @loggedIn || pongInterval > @pongLimit )
        @connectToVO()
      else
        @ping()
    , @loginRetryInterval

    @emit "connected"

exports.VictorOps = VictorOps

exports.use = (robot) ->
  new VictorOps robot
