#==========================================================================
# Copyright 2014 VictorOps, Inc.
# https://github.com/victorops/hubot-victorops/blob/master/LICENSE
#==========================================================================

Path = require 'path'
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
      @robot.logger.info()
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

  sendToVO: (js) ->
    m = JSON.stringify(js)
    message = "VO-MESSAGE:" + m.length + "\n" + m
    @robot.logger.info "send to chat server: #{message}" if js.MESSAGE != "PING"
    @ws.send( message )

  send: (user, strings...) ->
    @sendToVO( @chat( strings.join "\n" ) )

  reply: (user, strings...) ->
    strings = "@#{user.user.id}: #{strings.join "\n"}"
    @sendToVO @chat( strings )

  respond: (regex, callback) ->
    @hear regex, callback

  ping: () ->
    msg = {
      "MESSAGE": "PING",
      "TRANSACTION_ID": @generateUUID()
    }
    @sendToVO(msg)

  connectToVO: () ->
    @disconnect()

    if @loginAttempts-- <= 0
      @robot.logger.info "Unable to connect; giving up."
      process.exit 1

    @robot.logger.info "Attempting connection to VictorOps at #{@wsURL}..."

    @ws = new WebSocket(@wsURL)

    @ws.on "open", () =>
      @sendToVO(@login())

    @ws.on "error", (error) =>
      @disconnect(error)

    @ws.on "message", (message) =>
      @receiveWS(message)

    @ws.on 'close', () =>
      @loggedIn = false
      @robot.logger.info 'WebSocket closed.'

  disconnect: (error) ->
    @lastPong = new Date()
    @loggedIn = false
    @rcvdStatusList = false
    if @ws?
      @robot.logger.info("#{error} - disconnecting...")
      @ws.terminate()
      @ws = null

  rcvVOEvent: ( typ, obj ) ->
    user = @robot.brain.userForId "VictorOps"
    hubotMsg = "#{@robot.name} VictorOps #{typ} #{JSON.stringify(obj)}"
    @robot.logger.info hubotMsg
    @receive new TextMessage user, hubotMsg

  receiveWS: (msg) ->
    data = JSON.parse( msg.replace /VO-MESSAGE:[^\{]*/, "" )

    @robot.logger.info "Received #{data.MESSAGE}" if data.MESSAGE != "PONG"
    # Turn on for debugging
    #@robot.logger.info msg

    if data.MESSAGE == "CHAT_NOTIFY_MESSAGE" && data.PAYLOAD.CHAT.USER_ID != @robot.name
      user = @robot.brain.userForId data.PAYLOAD.CHAT.USER_ID
      @receive new TextMessage user, data.PAYLOAD.CHAT.TEXT.replace(/&quot;/g,'"')

    else if data.MESSAGE == "PONG"
      @lastPong = new Date()

    else if data.MESSAGE == "STATE_NOTIFY_MESSAGE" && data.PAYLOAD.USER_STATUS_LIST?
      @rcvdStatusList = true

    else if data.MESSAGE == "ENTITY_STATE_NOTIFY_MESSAGE"
      user = @robot.brain.userForId "VictorOps"
      @rcvVOEvent 'entitystate', entity for entity in data.PAYLOAD.SYSTEM_ALERT_STATE_LIST

    else if data.MESSAGE == "TIMELINE_LIST_REPLY_MESSAGE"
      for item in data.PAYLOAD.TIMELINE_LIST
        if item.ALERT?
          # get a list of current victor ops incident keys in the brain
          voIKeys = @robot.brain.get "VO_INCIDENT_KEYS"
          # catch null lists and init as blank
          if not voIKeys?
            voIKeys = []

          # name the new key and set the brain
          voCurIName = item.ALERT["INCIDENT_NAME"]
          @robot.brain.set voCurIName, item.ALERT

          # update the list of current victor ops incident keys in the brain
          voIKeys.push
            name: voCurIName
            timestamp: new Date
          @robot.brain.set "VO_INCIDENT_KEYS", voIKeys

          # clean up victor ops incident keys in the brain
          @cleanupBrain()

          @robot.emit "alert", item.ALERT
          @rcvVOEvent 'alert', item.ALERT
        else
          @robot.logger.info "Not an alert."

    else if data.MESSAGE == "LOGIN_REPLY_MESSAGE"
      if data.PAYLOAD.STATUS != "200"
        @robot.logger.info "Failed to log in: #{data.PAYLOAD.DESCRIPTION}"
        @loggedIn = false
        @ws.terminate()
      else
        @loginAttempts = @getLoginAttempts()
        @loggedIn = true
        if process.env.HUBOT_ANNOUNCE?
          @sendToVO(@chat(process.env.HUBOT_ANNOUNCE))
        setTimeout =>
          if ( ! @rcvdStatusList )
            @robot.logger.info "Did not get status list in time; reconnecting..."
            @disconnect()
        , 5000

    @shell.prompt() if data.MESSAGE != "PONG"

  cleanupBrain: ->
    # get a list of all the victor ops incident keys in the brain
    voIKeys = @robot.brain.get "VO_INCIDENT_KEYS"

    # remove keys from the victor ops incident keys list and from the brain
    # if they are older than 24 hours
    voIKeysFiltered = voIKeys.filter((item) ->
      return (new Date(item.timestamp).getDate() + 1 >= new Date)
    )

    # set the victor ops incident keys list in the the brain to the updated
    # list value
    @robot.brain.set "VO_INCIDENT_KEYS", voIKeysFiltered

  run: ->
    pkg = require Path.join __dirname, '..', 'package.json'
    @robot.logger.info "VictorOps adapter version #{pkg.version}"

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
