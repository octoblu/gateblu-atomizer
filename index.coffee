_       = require 'lodash'
meshblu = require 'meshblu'
request = require 'request'
url     = require 'url'
debug   = require('debug')('gateblu-atomizer')
{EventEmitter} = require 'events'

class GatebluAtomizer extends EventEmitter
  constructor: (config={}) ->
    @meshbluOptions = _.pick config, 'uuid', 'token', 'server', 'port'
    @target = {uuid: config.targetUuid, token: config.targetToken}
    @queue = []

    @processFunctions =
      'add-device': @addDevice
      'remove-device': @removeDevice
      'nodered-instance-start': @addDevice
      'nodered-instance-stop': @removeDevice
      'create': @addDevice
      'delete': @removeDevice

  run: =>
    @connection = meshblu.createConnection _.cloneDeep(@meshbluOptions)
    @connection.on 'message', @onMessage
    @connection.on 'notReady', @onNotReady
    @connection.on 'ready', @onReady
    @processQueue()

  onMessage: (message) =>
    debug 'onMessage', message.topic
    @queue.push message
    @processQueue()

  onNotReady: (data) =>
    console.error "Failed to authenticate", data

  onReady: =>
    @emit 'ready'

  processQueue: =>
    debug 'processQueue'
    return if @processingQueue || !@queue.length

    @processingQueue = true

    message = @queue.pop()

    gatebluUpdateFunction = @processFunctions[message.topic]

    unless gatebluUpdateFunction?
      console.error('unknown message topic', message)
      @connection.message devices: message.fromUuid, topic: 'atomizer-error', error: 'unknown message topic', originalMessage: message
      @processingQueue = false
      _.defer @processQueue
      return

    gatebluUpdateFunction message.payload, (error) =>
      debug 'gatebluUpdateFunction complete', error
      if error?
        console.error 'error updating gateblu', error
        @connection.message devices: message.fromUuid, topic: 'atomizer-error', error: error, originalMessage: message
      else
        @connection.message devices: @target.uuid, topic: 'refresh'

      @processingQueue = false
      _.defer @processQueue

  addDevice: (device, callback=->) =>
    debug 'addDevice', device.uuid
    @getGateblu (error, gateblu) =>
      debug 'gotGateblu', error, gateblu
      return callback(error) if error?

      gateblu.devices = null if _.isEmpty(gateblu.devices)

      gateblu.devices ?= []

      gateblu.devices = _.reject(gateblu.devices, uuid: device.uuid)

      debug 'devices', gateblu.devices

      gateblu.devices.push {uuid: device.uuid, token: device.token, connector: 'flow-runner'}
      @saveGateblu gateblu, callback

  removeDevice: (device, callback=->) =>
    debug 'removeDevice', device
    @getGateblu (error, gateblu) =>
      gateblu.devices = _.reject gateblu.devices, uuid: device.uuid
      @saveGateblu gateblu, callback

  getGateblu: (callback=->) =>
    options = @getGatebluRequestOptions()
    options.method = 'GET'

    request options, (error, response, body) =>
      gateblu = _.omit _.first(body.devices), '_id'
      _.defer callback, error, gateblu

  saveGateblu: (gateblu, callback=->) =>

    options = @getGatebluRequestOptions()
    options.method = 'PUT'
    options.json   = gateblu

    debug 'saveGateblu', JSON.stringify(options)
    request options, (error, response, body) =>
      debug 'put complete', error, response.statusCode, body
      callback error, body
    # @connection.update gateblu, (data) =>
    #   debug '@connection.update', data.error
    #   return callback(data) if data.error?
    #   callback()

  getGatebluRequestOptions: =>
    {
      json: true
      headers:
        meshblu_auth_uuid:  @target.uuid
        meshblu_auth_token: @target.token
      uri: url.format(
        protocol: if @meshbluOptions.port == 443 then 'https' else 'http'
        hostname: @meshbluOptions.server
        port:     @meshbluOptions.port
        pathname: "/devices/#{@target.uuid}"
      )
    }

module.exports = GatebluAtomizer
