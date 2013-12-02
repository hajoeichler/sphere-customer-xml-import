_ = require('underscore')._
{parseString} = require 'xml2js'
Config = require '../config'
Rest = require('sphere-node-connect').Rest
Q = require 'q'
crypto = require 'crypto'

exports.CustomerXmlImport = (options) ->
  @_options = options
  @rest = new Rest Config
  @

exports.CustomerXmlImport.prototype.process = (data, callback) ->
  throw new Error 'JSON Object required' unless _.isObject data
  throw new Error 'Callback must be a function' unless _.isFunction callback

  if data.attachments
    for k,v of data.attachments
      @transform @getAndFix(v), (stocks) =>
        @createOrUpdate stocks, callback
  else
    @returnResult false, 'No XML data attachments found.', callback

# helpers - move out
exports.CustomerXmlImport.prototype.returnResult = (positiveFeedback, msg, callback) ->
  d =
    message:
      status: positiveFeedback
      msg: msg
  console.log 'Error occurred: %j', d if not positiveFeedback
  callback d

exports.CustomerXmlImport.prototype.val = (row, name, fallback) ->
  return row[name][0] if row[name]
  fallback

exports.CustomerXmlImport.prototype.getAndFix = (raw) ->
  #TODO: decode base64 - make configurable for testing
  "<?xml?><root>#{raw}</root>"
# end of helpers

exports.CustomerXmlImport.prototype.createOrUpdate = (customers, callback) ->
  @rest.GET "/customers", (error, response, body) =>
    if response.statusCode is not 200
      @returnResult false, 'Can not fetch existing customers.', callback
      return
    existingCustomers = JSON.parse(body).results
    for ec in existingCustomers
      # get custom object
      @returnResult false, 'Not implemented yet', callback

exports.CustomerXmlImport.prototype.transform = (xml, callback) ->
  parseString xml, (err, result) =>
    @returnResult false, 'Error on parsing XML:' + err, callback if err
    @mapCustomer result.root, callback

exports.CustomerXmlImport.prototype.mapCustomer = (xmljs, callback) ->
  customers = []
  for k,xml of xmljs.Customer
    for e in xml.Employee
      d =
        email: @val e, 'email'
        firstName: @val e, 'firstname', ''
        lastName: @val e, 'lastname'
        password: Math.random().toString(36).slice(2) # some random password
      customers.push d
  callback(customers)

