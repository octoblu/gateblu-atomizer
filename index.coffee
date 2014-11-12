_       = require 'lodash'
meshblu = require 'meshblu'
request = require 'request'
url     = require 'url'
{EventEmitter} = require 'events'

class GatebluAtomizer extends EventEmitter
  constructor: (config={}) ->
    @meshbluOptions = _.pick config, 'uuid', 'token', 'server', 'port'
    @target = {uuid: config.targetUuid, token: config.targetToken}
    @queue = []

    @processFunctions =
      'add-device': @addDevice
      'remove-device': @removeDevice

  run: =>
    @connection = meshblu.createConnection @meshbluOptions
    @connection.on 'message', @onMessage
    @connection.on 'notReady', @onNotReady
    @connection.on 'ready', @onReady
    @processQueue()

  onMessage: (message) =>
    @queue.push message

  onNotReady: (data) =>
    console.error "Failed to authenticate", data

  onReady: =>
    @emit 'ready'

  processQueue: =>
    return _.delay(@processQueue, 500) if _.isEmpty @queue

    message = @queue.pop()

    gatebluUpdateFunction = @processFunctions[message.topic]

    unless gatebluUpdateFunction?
      console.error('unknown message topic', message)
      @connection.message devices: message.fromUuid, topic: 'atomizer-error', error: 'unknown message topic', originalMessage: message
      _.defer @processQueue
      return

    gatebluUpdateFunction message.payload, (error) =>
      if error?
        console.error 'error updating gateblu', error
        @connection.message devices: message.fromUuid, topic: 'atomizer-error', error: error, originalMessage: message

      @processQueue()

  addDevice: (device, callback=->) =>
    @getGateblu (error, gateblu) =>
      return callback(error) if error?

      gateblu.devices.push device
      @saveGateblu gateblu, callback

  removeDevice: (uuid, callback=->) =>
    @getGateblu (error, gateblu) =>
      gateblu.devices = _.reject gateblu.devices, uuid: uuid
      @saveGateblu gateblu, callback

  getGateblu: (gateblu, callback=->) =>
    protocol = if @meshbluOptions.port == 443 then 'https' else 'http'
    uri = url.format protocol: protocol, hostname: @meshbluOptions.server, port: @meshbluOptions.port, pathname: "/devices/#{@target.uuid}"
    options = {
      json: true
      headers:
        skynet_auth_uuid:  @target.uuid
        skynet_auth_token: @target.token
    }

    request.get uri, options, (error, response, body) =>
      _.defer callback, error, body

  saveGateblu: (gateblu, callback=->) =>
    @connection.update gateblu, (data) =>
      return callback(data) if data.eventCode != 401
      callback()



module.exports = GatebluAtomizer
