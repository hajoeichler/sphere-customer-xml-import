_ = require('underscore')._
{parseString} = require 'xml2js'
Config = require '../config'
Rest = require('sphere-node-connect').Rest
CommonUpdater = require('sphere-node-sync').CommonUpdater
Q = require 'q'
crypto = require 'crypto'
xmlHelpers = require '../lib/xmlhelpers'

class CustomerXmlImport extends CommonUpdater

  NO_CUSTOMER_GROUP = 'NONE'
  CUSTOMER_GROUP_B2C_NAME = 'B2C'
  CUSTOMER_GROUP_B2B_NAME = 'B2B'
  CUSTOMER_GROUP_B2C_WITH_CARD_NAME = 'B2C with card'

  constructor: (options = {}) ->
    super options
    @rest = new Rest Config
    @

  elasticio: (msg, cfg, cb, snapshot) ->
    throw new Error 'JSON Object required' unless _.isObject msg
    throw new Error 'Callback must be a function' unless _.isFunction cb

    if _.size(msg.attachments) > 0
      for fileName, content of msg.attachments
        @run content, cb
    else
      @returnResult false, 'No XML attachments found!', cb

  run: (xmlString, callback) ->
    groups = [ @ensureCustomerGroupByName(CUSTOMER_GROUP_B2B_NAME), @ensureCustomerGroupByName(CUSTOMER_GROUP_B2C_WITH_CARD_NAME)]
    Q.all(groups).fail (msg) =>
      @returnResult false, msg, callback
    .then ([b2bCustomerGroup, b2cWithCardCustomerGroup]) =>
      customerGroupName2Id = {}
      customerGroupName2Id[CUSTOMER_GROUP_B2B_NAME] = b2bCustomerGroup.id
      customerGroupName2Id[CUSTOMER_GROUP_B2C_WITH_CARD_NAME] = b2cWithCardCustomerGroup.id
      @transform xmlString, customerGroupName2Id, (data) =>
        @createOrUpdate data, callback

  createOrUpdate: (data, callback) ->
    @rest.GET "/customers?limit=0", (error, response, body) =>
      if error
        @returnResult false, 'Error on fetch existing customers: ' + error, callback
        return
      if response.statusCode isnt 200
        @returnResult false, 'Problem on fetch existing customers: ' + body, callback
        return
      existingCustomers = JSON.parse(body).results
      email2id = {}
      for ec in existingCustomers
        email2id[ec.email] = ec.id
      console.log "Existing customers: " + _.size(email2id)

      foundOne = false
      for customer of data.customers
        for employee in data.customers[customer]
          foundOne = true
          if _.has email2id, employee.email
            @returnResult false, 'Update of customer isnt implemented yet!', callback
          else
            @create employee, null, callback

      unless foundOne
        @returnResult true, 'Nothing done.', callback

  create: (newCustomer, paymentInfo, callback) ->
    console.log "create"
    @createCustomer(newCustomer).fail (msg) =>
      @returnResult false, msg, callback
    .then (customer) =>
      posts = [@createPaymentInfo(customer, paymentInfo), @linkCustomerIntoGroup(customer, newCustomer.customerGroup)]
      Q.all(posts).fail (msg) =>
        @returnResult false, msg, callback
      .then (msg) =>
        @returnResult true, msg, callback

  createCustomer: (newCustomer) ->
    console.log 'createCustomer'
    deferred = Q.defer()

    @rest.POST '/customers', JSON.stringify(newCustomer), (error, response, body) ->
      if error
        deferred.reject 'Error on creating customer: ' + error
      if response.statusCode is 201
        deferred.resolve JSON.parse(body).customer
      else
        deferred.reject 'Problem on creating customer: ' + body

    deferred.promise

  createPaymentInfo: (customer, paymentInfo) ->
    console.log 'createPaymentInfo'
    deferred = Q.defer()

    unless paymentInfo
      deferred.resolve 'Customer has no paymentInfo.'
      return deferred.promise

    customObj =
      container: "paymentMethodInfo"
      key: id
      value:
        methodCodes: [103, 105]
        paymentNames: ['', '']
        discount: 'TODO'

    @rest.POST '/custom-objects', JSON.stringify(customObj), (error, response, body) ->
      if error
        deferred.reject 'Error on creating payment-info object: ' + error
      if response.statusCode is 201
        deferred.resolve 'Payment info created.'
      else
        deferred.reject 'Problem on creating payment-info object: ' + body

    deferred.promise

  linkCustomerIntoGroup: (customer, customerGroup) ->
    console.log 'linkCustomerIntoGroup'
    deferred = Q.defer()

    unless customerGroup
      deferred.resolve 'Customer has no group.'
      return deferred.promise

    data =
      id: customer.id
      version: customer.version
      actions: [
        action: 'setCustomerGroup'
        customerGroup: customerGroup
      ]

    @rest.POST "/customers/#{customer.id}", JSON.stringify(data), (error, response, body) ->
      if error
        deferred.reject 'Error on linking customer with group: ' + error
      if response.statusCode is 200
        deferred.resolve 'Customer linked to customer group.'
      else
        deferred.reject 'Problem on linking customer with group: ' + body

    deferred.promise

  transform: (rawXml, customerGroupName2Id, callback) ->
    xmlHelpers.xmlTransform xmlHelpers.xmlFix(rawXml), (err, result) =>
      @returnResult false, 'Error on parsing XML:' + err, callback if err
      @mapCustomers result.root, customerGroupName2Id, callback

  mapCustomers: (xmljs, customerGroupName2Id, callback) ->
    console.log 'mapCustomers'
    customInfo ={}
    customers = {}
    usedEmails = []
    for k, xml of xmljs.Customer
      customerNumber = xmlHelpers.xmlVal xml, 'CustomerNr'
      customers[customerNumber] = []

      country = xmlHelpers.xmlVal xml, 'country'
      if country is not 'D'
        # TODO support multiple countries
        console.log "Unsupported country '#{country}'"
        continue

      customerGroup = xmlHelpers.xmlVal xml, 'Group', NO_CUSTOMER_GROUP
      discount = xmlHelpers.xmlVal xml, 'Discount', '0.0'
      intDiscount = parseInt discount
      # set customer group if b2c has a discount. Otherwise the customer isn't in any group
      customerGroup = CUSTOMER_GROUP_B2C_WITH_CARD_NAME if customerGroup is CUSTOMER_GROUP_B2C_NAME
      customerGroup = NO_CUSTOMER_GROUP if customerGroup is CUSTOMER_GROUP_B2C_WITH_CARD_NAME and intDiscount is 0

      paymentMethodCode = xmlHelpers.xmlVal xml, 'PaymentMethodCode'
      paymentMethod = xmlHelpers.xmlVal xml, 'PaymentMethod'

      customInfo[customerNumber] =
        paymentMethod: paymentMethod
        paymentMethodCode: paymentMethodCode
        discount: discount

      for employee in xml.Employees[0].Employee
        eNr = xmlHelpers.xmlVal employee, 'employeeNr'
        email = xmlHelpers.xmlVal employee, 'email'
        email = xmlHelpers.xmlVal xml, 'EmailCompany' unless email

        continue unless email # we can't import customers without email
        continue if _.indexOf(usedEmails, email) isnt -1 # email already used

        usedEmails.push email

# TODO
# title - String - Optional
# defaultShippingAddressId - String - Optional
# defaultBillingAddressId - String - Optional

        streetInfo = @splitStreet xmlHelpers.xmlVal xml, 'Street'
        customer =
          email: email
          externalId: customerNumber
          firstName: xmlHelpers.xmlVal employee, 'firstname', ''
          lastName: xmlHelpers.xmlVal employee, 'lastname'
          password: Math.random().toString(36).slice(2) # some random password
          addresses: [
            streetName: streetInfo.name
            streetNumber: streetInfo.number
            postalCode: xmlHelpers.xmlVal xml, 'zip'
            city: xmlHelpers.xmlVal xml, 'town'
            country: 'DE'
            phone: xmlHelpers.xmlVal xml, 'phone'
          ]
        customer.addresses[0].additionalStreetInfo = streetInfo.additionalStreetInfo if streetInfo.additionalStreetInfo
        if customerGroup isnt NO_CUSTOMER_GROUP
          customer.customerGroup =
            typeId: 'customer-group'
            id: customerGroupName2Id[customerGroup]
        customers[customerNumber].push customer

    data =
      customers: customers
      customInfo: customInfo

    callback data

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

  ensureCustomerGroupByName: (name) ->
    deferred = Q.defer()
    query = encodeURIComponent "name=\"#{name}\""
    @rest.GET "/customer-groups?where=#{query}", (error, response, body) =>
      if error
        deferred.reject "Error on getting customer group: " + error
      else
        if response.statusCode is 200
          res = JSON.parse(body).results
          if res.length is 1
            deferred.resolve res[0]
          else
            customerGroup =
              groupName: name
            @rest.POST '/customer-groups', JSON.stringify(customerGroup), (error, response, body) ->
              if error
                deferred.reject "Error on creating customerGroup '#{name}': " + error
              else if response.statusCode is 201
                deferred.resolve JSON.parse(body)
              else
                deferred.reject 'Problem on creating customerGroup: ' + body
        else
          deferred.reject "Problem on getting customer group (status: #{response.statusCode}): " + body
    deferred.promise


module.exports = CustomerXmlImport
