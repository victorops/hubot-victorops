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
{Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'

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
        user = @robot.brain.userForId '1', name: 'Shell', room: 'Shell'
        @vo.sendToVO @vo.chat(buffer)
      @repl.prompt()

    @repl.setPrompt "#{@robot.name} >> "
    @repl.prompt()

  prompt: ->
    @repl.prompt()


class VictorOps extends Adapter

  constructor: (robot) ->
    @wsURL = process.env.HUBOT_VICTOROPS_URL
    @userID = process.env.HUBOT_VICTOROPS_USER
    @password = process.env.HUBOT_VICTOROPS_PASSWORD
    @orgSlug = process.env.HUBOT_VICTOROPS_ORG
    @robot = robot
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

  run: ->
    self = @

    @loginMsg = self.login( self.userID, self.password, self.orgSlug )
    #console.log @loginMsg

    @ws = new WebSocket(@wsURL)

    @ws.on "open", () ->
      user = self.robot.brain.userForId '1', name: 'Shell', room: 'Shell'
      self.sendToVO( self.loginMsg )

    @ws.on "message", (message) ->
      self.receive_ws( message )

    @shell = new Shell( @robot, self )

    self.emit "connected"

  receive_ws: (msg) ->
    data = JSON.parse( msg.replace /VO-MESSAGE:[^\{]*/, "" )

    console.log "Received #{data.MESSAGE}"
    # console.log msg

    if data.MESSAGE == "CHAT_NOTIFY_MESSAGE" && data.PAYLOAD.CHAT.USER_ID != @robot.name
      console.log "Allow hubot to receive message from #{data.PAYLOAD.CHAT.USER_ID}"
      user = @robot.brain.userForId data.PAYLOAD.CHAT.USER_ID
      @receive new TextMessage user, data.PAYLOAD.CHAT.TEXT

    @shell.prompt()

exports.VictorOps = VictorOps

exports.use = (robot) ->
  new VictorOps robot
