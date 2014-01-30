_ = require('underscore')._
{parseString} = require 'xml2js'
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
    @rest = new Rest options
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
      @transform(xmlString, customerGroupName2Id).then (data) =>
        @createOrUpdate data, callback
      .fail (msg) =>
        @returnResult false, msg, callback

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

      posts = []
      for customer of data.customers
        for employee in data.customers[customer]
          paymentInfo = data.paymentInfos[customer]
          if _.has email2id, employee.email
            # TODO: support updating of customers
            deferred = Q.defer()
            deferred.resolve 'Update of customer is not implemented yet!'
            posts.push deferred.promise
          else
            posts.push @create employee, paymentInfo, callback

      if _.size(posts) is 0
        @returnResult true, 'Nothing done.', callback

      @processInBatches posts, callback

  processInBatches: (posts, callback, numberOfParallelRequest = 20, acc = []) =>
    current = _.take posts, numberOfParallelRequest
    Q.all(current).then (msg) =>
      messages = acc.concat(msg)
      if _.size(current) < numberOfParallelRequest
        @returnResult true, messages, callback
      else
        @processInBatches _.tail(posts, numberOfParallelRequest), callback, numberOfParallelRequest, messages
    .fail (msg) =>
      @returnResult false, msg, callback

  create: (newCustomer, paymentInfo, callback) ->
    deferred = Q.defer()
    @createCustomer(newCustomer).fail (msg) ->
      deferred.reject msg
    .then (customer) =>
      @addAddress(customer, newCustomer.addresses[0]).fail (msg) ->
        deferred.reject msg
      .then (customer) =>
        posts = [
          @createPaymentInfo(customer, paymentInfo)
          @linkCustomerIntoGroup(customer, newCustomer.customerGroup)
        ]
        Q.all(posts).fail (msg) ->
          deferred.reject msg
        .then (msg) ->
          deferred.resolve "Customer created."

    deferred.promise

  createCustomer: (newCustomer) ->
    deferred = Q.defer()

    @rest.POST '/customers', JSON.stringify(newCustomer), (error, response, body) ->
      if error
        deferred.reject 'Error on creating customer: ' + error
      else if response.statusCode is 201
        deferred.resolve JSON.parse(body).customer
      else
        deferred.reject 'Problem on creating customer: ' + body

    deferred.promise

  createPaymentInfo: (customer, paymentInfo) ->
    deferred = Q.defer()

    unless paymentInfo
      deferred.resolve 'Customer has no paymentInfo.'
      return deferred.promise

    customObj =
      container: "paymentMethodInfo"
      key: customer.id
      value: paymentInfo

    @rest.POST '/custom-objects', JSON.stringify(customObj), (error, response, body) ->
      if error
        deferred.reject 'Error on creating payment-info object: ' + error
      else if response.statusCode is 201
        deferred.resolve 'Payment info created.'
      else
        deferred.reject 'Problem on creating payment-info object: ' + body

    deferred.promise

  linkCustomerIntoGroup: (customer, customerGroup) ->
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
      else if response.statusCode is 200
        deferred.resolve 'Customer linked to customer group.'
      else
        deferred.reject 'Problem on linking customer with group: ' + body

    deferred.promise

  addAddress: (customer, address) ->
    deferred = Q.defer()

    data =
      id: customer.id
      version: customer.version
      actions: [
        action: 'addAddress'
        address: address
      ]

    @rest.POST "/customers/#{customer.id}", JSON.stringify(data), (error, response, body) ->
      if error
        deferred.reject 'Error on adding address: ' + error
      else if response.statusCode is 200
        deferred.resolve JSON.parse(body)
      else
        deferred.reject 'Problem on adding address: ' + body

    deferred.promise

  transform: (rawXml, customerGroupName2Id) ->
    deferred = Q.defer()
    xmlHelpers.xmlTransform xmlHelpers.xmlFix(rawXml), (err, result) =>
      if err
        deferred.reject 'Error on parsing XML:' + err
      else
        deferred.resolve @mapCustomers(result.root, customerGroupName2Id)

    deferred.promise

  mapCustomers: (xmljs, customerGroupName2Id) ->
    paymentInfos = {}
    customers = {}
    @usedEmails = []
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
      discount = parseFloat discount

      # B2C: set customer group if she has a discount. Otherwise the customer isn't in any group
      customerGroup = CUSTOMER_GROUP_B2C_WITH_CARD_NAME if customerGroup is CUSTOMER_GROUP_B2C_NAME
      customerGroup = NO_CUSTOMER_GROUP if customerGroup is CUSTOMER_GROUP_B2C_WITH_CARD_NAME and discount is 0

      paymentMethodCode = xmlHelpers.xmlVal xml, 'PaymentMethodCode', []
      paymentMethod = xmlHelpers.xmlVal xml, 'PaymentMethod', []

      if _.isString paymentMethod
        paymentMethod = paymentMethod.split ','

      if _.isString paymentMethodCode
        paymentMethodCode = paymentMethodCode.split ','

      paymentInfos[customerNumber] =
        paymentMethod: paymentMethod
        paymentMethodCode: paymentMethodCode
        discount: discount

      unless xml.Employees
        customer = @createCustomerData xml, null, customerNumber, customerGroupName2Id, customerGroup
        customers[customerNumber].push customer if customer
      else
        for employee in xml.Employees[0].Employee
          customer = @createCustomerData xml, employee, customerNumber, customerGroupName2Id, customerGroup
          customers[customerNumber].push customer if customer

    data =
      customers: customers
      paymentInfos: paymentInfos

  createCustomerData: (xml, employee, customerNumber, customerGroupName2Id, customerGroup) ->
    employee = xml unless employee
    # TODO: add mapping for
    # - title
    # defaultShippingAddressId
    # defaultBillingAddressId

    email = xmlHelpers.xmlVal employee, 'email'
    email = xmlHelpers.xmlVal xml, 'EmailCompany' unless email

    return unless email # we can't import customers without email
    return if _.indexOf(@usedEmails, email) isnt -1 # email already used
    @usedEmails.push email

    streetInfo = @splitStreet xmlHelpers.xmlVal xml, 'Street', ''
    customer =
      email: email
      externalId: customerNumber
      firstName: xmlHelpers.xmlVal employee, 'firstname', ''
      lastName: xmlHelpers.xmlVal employee, 'lastname', xmlHelpers.xmlVal(xml, 'LastName')
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

    customer

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
