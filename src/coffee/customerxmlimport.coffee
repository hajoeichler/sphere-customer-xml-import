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
    existing = Q.all [@getCustomerGroupId('B2B')]
    existing.spread (customerGroupId) =>
      for k,v of data.attachments
        @transform @getAndFix(v), customerGroupId, (customers) =>
          @createOrUpdate customers, callback
    .fail (err) =>
      @returnResult false, 'Problem: ' + err, callback
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
  @rest.GET "/customers?limit=0", (error, response, body) =>
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
              res = JSON.parse(body)
              id = res.customer.id
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
                  if e.customerGroup
                    d =
                      id: id
                      version: res.customer.version
                      actions: [ { action: "setCustomerGroup", customerGroup: e.customerGroup } ]
                    @rest.POST "/customers/#{id}", JSON.stringify(d), (error, response, body) =>
                      console.log error
                      console.log response.statusCode
                      console.log body
                      @returnResult true, 'Customer created with group', callback
                  else
                    @returnResult true, 'Customer created without group', callback
            else
              @returnResult false, 'Problem on creating customer:' + body, callback

exports.CustomerXmlImport.prototype.transform = (xml, customerGroupId, callback) ->
  parseString xml, (err, result) =>
    @returnResult false, 'Error on parsing XML:' + err, callback if err
    @mapCustomer result.root, customerGroupId, callback

exports.CustomerXmlImport.prototype.mapCustomer = (xmljs, customerGroupId, callback) ->
  customers = {}
  usedEmails = []
  for k,xml of xmljs.Customer
    cNr = @val xml, 'CustomerNr'
    customers[cNr] = []

    country = @val xml, 'country'
    if country is not 'D'
      console.log "Unsupported country"
      continue

    cg = @val xml, 'Group', 'NONE'
    for e in xml.Employee
      eNr = @val e, 'employeeNr'
      email = @val e, 'email'
      if not email
        email = @val xml, 'email'
      if not email
        continue
      if _.indexOf(usedEmails, email) is not -1
        continue
      usedEmails.push email
      s = @splitStreet @val xml, 'Street'
      d =
        email: email
        firstName: @val e, 'firstname', ''
        lastName: @val e, 'lastname'
        password: Math.random().toString(36).slice(2) # some random password
        addresses: [
          streetName: s.name
          streetNumber: s.number
          postalCode: @val xml, 'zip'
          city: @val xml, 'town'
          country: 'DE'
          phone: @val xml, 'phone'
        ]
      d.addresses[0].additionalStreetInfo = s.additionalStreetInfo if s.additionalStreetInfo
      if cg is 'B2B'
        d.customerGroup =
          typeId: 'customer-group'
          id: customerGroupId
      customers[cNr].push d
  callback(customers)

exports.CustomerXmlImport.prototype.splitStreet = (street) ->
  r = new RegExp /\d+/
  i = street.search r
  if i < 0
    d =
      name: street
    return d

  n = street.substring(i).trim()
  d =
    name: street.substring(0, i).trim()
    number: n

  r = new RegExp /[a-zA-Z]{2,}/
  i = n.search r
  if i > 0
    d.number = n.substring(0,i).trim()
    d.additionalStreetInfo = n.substring(i).trim()

  d

exports.CustomerXmlImport.prototype.getCustomerGroupId = (name) ->
  deferred = Q.defer()
  query = encodeURIComponent "name=\"#{name}\""
  @rest.GET "/customer-groups?where=#{query}", (error, response, body) ->
    if error
      deferred.reject error
    else
      if response.statusCode is 200
        res = JSON.parse(body).results
        if res.length > 0
          deferred.resolve res[0].id
        else
          deferred.reject "There is no customer group with name #{name}."
      else
        deferred.reject "Problem on getting customer group."
  deferred.promise