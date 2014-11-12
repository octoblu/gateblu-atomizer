config          = require './meshblu.json'
GatebluAtomizer = require './index'

gatebluAtomizer = new GatebluAtomizer config
gatebluAtomizer.on 'ready', =>
  console.log 'Connected to Meshblu'
gatebluAtomizer.run()

