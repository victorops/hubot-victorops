#//==========================================================================//
#//             Copyright 2014 VictorOps, Inc. All Rights Reserved           //
#//                                                                          //
#//                 PROPRIETARY AND CONFIDENTIAL INFORMATION                 //
#// The information contained herein is the proprietary and confidential     //
#// property of VictorOps, Inc. and may not be used, distributed, modified,  //
#// disclosed or reproduced without the express written permission of        //
#// VictorOps, Inc.                                                          //
#//==========================================================================//

Readline = require 'readline'
WebSocket = require 'ws'
{Adapter,Robot,TextMessage} = require 'hubot'

class Shell

  constructor: (robot, vo) ->
    @robot = robot
    stdin = process.openStdin()
    stdout = process.stdout
    @vo = vo

    process.on 'uncaughtException', (err) =>
      @robot.logger.error err.stack

    @repl = Readline.createInterface stdin, stdout, null

    @repl.on 'close', =>
      stdin.destroy()
      @robot.shutdown()
      process.exit 0

    @repl.on 'line', (buffer) =>
      if buffer.trim().length > 0
        @repl.close() if buffer.toLowerCase() is 'exit'
        @vo.sendToVO @vo.chat(buffer)
      @repl.prompt()

    @repl.setPrompt "#{@robot.name} >> "
    @repl.prompt()

  prompt: ->
    @repl.prompt()


class VictorOps extends Adapter

  constructor: (robot) ->
    @wsURL = process.env.HUBOT_VICTOROPS_URL
    @password = process.env.HUBOT_VICTOROPS_PASSWORD
    @orgSlug = process.env.HUBOT_VICTOROPS_ORG
    @userID = robot.name
    @robot = robot
    @connected = false
    super robot

  generateUUID: ->
    d = new Date().getTime()
    'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) ->
      r = (d + Math.random()*16)%16 | 0;
      v = if c is 'x' then r else (r & 0x3|0x8)
      v.toString(16)
    )

  login: (user, password, company) ->
    msg = {
      "MESSAGE": "LOGIN_REQUEST_MESSAGE",
      "TRANSACTION_ID": @generateUUID(),
      "PAYLOAD": {
          "PASSWORD": password,
          "ROLE": "USER",
          "PROTOCOL": "1.0",
          "USER_ID": user,
          "COMPANY_ID": company,
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

    console.log "Attempting connection to VictorOps..."

    @ws = new WebSocket(@wsURL)

    @ws.on "open", () ->
      _.connected = true
      _.sendToVO( _.login( _.userID, _.password, _.orgSlug ) )

    @ws.on "message", (message) ->
      _.receive_ws( message )

    @ws.on 'close', () ->
      _.connected = false
      console.log 'disconnected!'

  receive_ws: (msg) ->
    data = JSON.parse( msg.replace /VO-MESSAGE:[^\{]*/, "" )

    console.log "Received #{data.MESSAGE}"
    # console.log msg

    if data.MESSAGE == "CHAT_NOTIFY_MESSAGE" && data.PAYLOAD.CHAT.USER_ID != @robot.name
      user = @robot.brain.userForId data.PAYLOAD.CHAT.USER_ID
      @receive new TextMessage user, data.PAYLOAD.CHAT.TEXT

    @shell.prompt()


  run: ->
    @shell = new Shell( @robot, @ )

    setInterval =>
      if ( ! @connected )
        @connectToVO()
    , 5000

    @emit "connected"

exports.VictorOps = VictorOps

exports.use = (robot) ->
  new VictorOps robot
