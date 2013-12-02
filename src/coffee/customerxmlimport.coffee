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
      @transform @getAndFix(v), (customers) =>
        @createOrUpdate customers, callback
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
    email2id = {}
    for ec in existingCustomers
      email2id[ec.email] = ec.id
    console.log "Existing customers: " + _.size(email2id)
    for c of customers
      for e in customers[c]
        if email2id[e.email]
          @returnResult false, 'Not yet implemented', callback
        else
          @rest.POST "/customers", JSON.stringify(e), (error, response, body) =>
            if response.statusCode is 201
              id = JSON.parse(body).id
              d =
                container: "customerNr2id"
                key: c
                value: id
              @rest.POST "/custom-objects", JSON.stringify(d), (error, response, body) =>
                d =
                  container: "id2CustomerNr"
                  key: id
                  value: c
                @rest.POST "/custom-objects", JSON.stringify(d), (error, response, body) =>
                  @returnResult true, 'Customer created', callback
            else
              @returnResult false, 'Problem on creating customer:' + body, callback

exports.CustomerXmlImport.prototype.transform = (xml, callback) ->
  parseString xml, (err, result) =>
    @returnResult false, 'Error on parsing XML:' + err, callback if err
    @mapCustomer result.root, callback

exports.CustomerXmlImport.prototype.mapCustomer = (xmljs, callback) ->
  customers = {}
  for k,xml of xmljs.Customer
    cNr = @val xml, 'CustomerNr'
    customers[cNr] = []
    for e in xml.Employee
      eNr = @val e, 'employeeNr'
      d =
        email: @val e, 'email'
        firstName: @val e, 'firstname', ''
        lastName: @val e, 'lastname'
        password: Math.random().toString(36).slice(2) # some random password
      customers[cNr].push d
  callback(customers)
