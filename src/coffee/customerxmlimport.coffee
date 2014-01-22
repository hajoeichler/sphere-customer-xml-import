_ = require('underscore')._
{parseString} = require 'xml2js'
Config = require '../config'
Rest = require('sphere-node-connect').Rest
CommonUpdater = require('sphere-node-sync').CommonUpdater
Q = require 'q'
crypto = require 'crypto'
xmlHelpers = require '../lib/xmlhelpers'

class CustomerXmlImport extends CommonUpdater

  CUSTOMER_GROUP_B2B_NAME = 'B2B'

  constructor: (options = {}) ->
    super(options)
    @rest = new Rest Config
    @

  elasticio: (msg, cfg, cb, snapshot) ->
    throw new Error 'JSON Object required' unless _.isObject msg
    throw new Error 'Callback must be a function' unless _.isFunction cb

    if _.size(msg.attachments) > 0
      existing = Q.all [ @getCustomerGroupId(CUSTOMER_GROUP_B2B_NAME) ]
      existing.spread (customerGroupId) =>
        for fileName, content of msg.attachments
          @transform content, customerGroupId, (customers) =>
            @createOrUpdate customers, cb
      .fail (err) =>
        @returnResult false, 'Problem: ' + err, cb
    else
      @returnResult false, 'No XML attachments found!', cb

  createOrUpdate: (customers, callback) ->
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
            @returnResult false, 'Update of customer isnt implemented yet!', callback
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

  transform: (rawXml, customerGroupId, callback) ->
    xmlHelpers.xmlTransform xmlHelpers.xmlFix(rawXml), (err, result) =>
      @returnResult false, 'Error on parsing XML:' + err, callback if err
      @mapCustomers result.root, customerGroupId, callback

  mapCustomers: (xmljs, customerGroupId, callback) ->
    customers = {}
    usedEmails = []
    for k,xml of xmljs.Customer
      cNr = xmlHelpers.xmlVal xml, 'CustomerNr'
      customers[cNr] = []

      country = xmlHelpers.xmlVal xml, 'country'
      if country is not 'D'
        console.log "Unsupported country"
        continue

      cg = xmlHelpers.xmlVal xml, 'Group', 'NONE'
      for e in xml.Employee
        eNr = xmlHelpers.xmlVal e, 'employeeNr'
        email = xmlHelpers.xmlVal e, 'email'
        if not email
          email = xmlHelpers.xmlVal xml, 'email'
        if not email
          continue
        if _.indexOf(usedEmails, email) is not -1
          continue
        usedEmails.push email
        s = @splitStreet xmlHelpers.xmlVal xml, 'Street'
        d =
          email: email
          firstName: xmlHelpers.xmlVal e, 'firstname', ''
          lastName: xmlHelpers.xmlVal e, 'lastname'
          password: Math.random().toString(36).slice(2) # some random password
          addresses: [
            streetName: s.name
            streetNumber: s.number
            postalCode: xmlHelpers.xmlVal xml, 'zip'
            city: xmlHelpers.xmlVal xml, 'town'
            country: 'DE'
            phone: xmlHelpers.xmlVal xml, 'phone'
          ]
        d.addresses[0].additionalStreetInfo = s.additionalStreetInfo if s.additionalStreetInfo
        if cg is 'B2B'
          d.customerGroup =
            typeId: 'customer-group'
            id: customerGroupId
        customers[cNr].push d
    callback(customers)

  splitStreet: (street) ->
    regex = new RegExp /\d+/
    index = street.search regex
    if index < 0
      str =
        name: street
      return str

    num = street.substring(index).trim()
    str =
      name: street.substring(0, index).trim()
      number: num

    regex = new RegExp /[a-zA-Z]{2,}/
    index = num.search regex
    if index > 0
      str.number = num.substring(0,index).trim()
      str.additionalStreetInfo = num.substring(index).trim()

    str

  getCustomerGroupId: (name) ->
    deferred = Q.defer()
    query = encodeURIComponent "name=\"#{name}\""
    @rest.GET "/customer-groups?where=#{query}", (error, response, body) ->
      if error
        deferred.reject "Error on getting customer group: " + error
      else
        if response.statusCode is 200
          res = JSON.parse(body).results
          if res.length > 0
            deferred.resolve res[0].id
          else
            deferred.reject "There is no customer group with name #{name}."
        else
          deferred.reject "Problem on getting customer group (status: #{response.statusCode}): " + body
    deferred.promise


module.exports = CustomerXmlImport
