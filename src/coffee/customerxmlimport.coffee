{_} = require 'underscore'
{parseString} = require 'xml2js'
CommonUpdater = require('sphere-node-sync').CommonUpdater
SphereClient = require 'sphere-node-client'
Q = require 'q'
crypto = require 'crypto'
xmlHelpers = require '../lib/xmlhelpers'

class CustomerXmlImport extends CommonUpdater

  NO_CUSTOMER_GROUP: 'NONE'
  CUSTOMER_GROUP_B2C_NAME: 'B2C'
  CUSTOMER_GROUP_B2B_NAME: 'B2B'
  CUSTOMER_GROUP_B2C_WITH_CARD_NAME: 'B2C with card'

  constructor: (options = {}) ->
    super options
    @client = new SphereClient options
    this

  run: (xmlString) ->
    Q.all([
      @ensureCustomerGroupByName @CUSTOMER_GROUP_B2B_NAME
      @ensureCustomerGroupByName @CUSTOMER_GROUP_B2C_WITH_CARD_NAME
    ])
    .spread (b2bCustomerGroup, b2cWithCardCustomerGroup) =>
      customerGroupName2Id = {}
      customerGroupName2Id[@CUSTOMER_GROUP_B2B_NAME] = b2bCustomerGroup.id
      customerGroupName2Id[@CUSTOMER_GROUP_B2C_WITH_CARD_NAME] = b2cWithCardCustomerGroup.id
      @transform(xmlString, customerGroupName2Id)
    .then (customerData) =>
      @createOrUpdate customerData

  ensureCustomerGroupByName: (name) ->
    @client.customerGroups.fetch()
    .then (result) =>
      customerGroup = _.find result.results, (cg) ->
        cg.name is name
      if customerGroup?
        Q customerGroup
      else
        customerGroup =
          groupName: name
        @client.customerGroups.save customerGroup

  createOrUpdate: (customerData) ->
    deferred = Q.defer()
    @client.customers.perPage(500).fetch()
    .then (result) =>

      existingCustomers = result.results
      email2id = {}
      for ec in existingCustomers
        email2id[ec.email] = ec.id
      console.log "Existing customers: " + _.size(email2id)

      posts = []
      for data in customerData
        customer = data.customer
        paymentInfo = data.paymentInfo
        if _.has email2id, customer.email
          # TODO: support updating of customers
          posts.push Q('Update of customer is not implemented yet!')
        else
          posts.push @create customer, paymentInfo

      if _.size(posts) is 0
        Q 'Nothing done.'

      @processInBatches posts

  processInBatches: (posts, numberOfParallelRequest = 20, acc = []) =>
    current = _.take posts, numberOfParallelRequest
    Q.all(current).then (msg) =>
      messages = acc.concat(msg)
      if _.size(current) < numberOfParallelRequest
        Q messages
      else
        @processInBatches _.tail(posts, numberOfParallelRequest), numberOfParallelRequest, messages

  create: (newCustomer, paymentInfo) ->
    @createCustomer(newCustomer)
    .then (customer) =>
      @addAddress(customer.customer, newCustomer.addresses[0])
    .then (customer) =>
      @linkCustomerIntoGroup(customer, newCustomer.customerGroup)
    .then (customer) =>
      @createPaymentInfo(customer, paymentInfo)
    .then (customer) ->
      Q 'Customer created.'

  createCustomer: (newCustomer) ->
    @client.customers.save newCustomer

  addAddress: (customer, address) ->
    data =
      id: customer.id
      version: customer.version
      actions: [
        action: 'addAddress'
        address: address
      ]

    @client.customers.byId(customer.id).save data

  linkCustomerIntoGroup: (customer, customerGroup) ->
    unless customerGroup?
      Q customer
    else
      data =
        id: customer.id
        version: customer.version
        actions: [
          action: 'setCustomerGroup'
          customerGroup: customerGroup
        ]

      @client.customers.byId(customer.id).save data

  createPaymentInfo: (customer, paymentInfo) ->
    unless paymentInfo?
      Q customer
    else
      customObj =
        container: "paymentMethodInfo"
        key: customer.id
        value: paymentInfo

      @client.customObjects.save customObj

  transform: (rawXml, customerGroupName2Id) ->
    deferred = Q.defer()
    xmlHelpers.xmlTransform xmlHelpers.xmlFix(rawXml), (err, result) =>
      if err
        deferred.reject 'Error on parsing XML:' + err
      else
        deferred.resolve @mapCustomers(result.root, customerGroupName2Id)

    deferred.promise

  mapCustomers: (xmljs, customerGroupName2Id) ->
    customerData = []
    @usedEmails = []
    for k, xml of xmljs.Customer
      customerNumber = xmlHelpers.xmlVal xml, 'CustomerNr'

      country = xmlHelpers.xmlVal xml, 'country'
      country = switch country
        when 'D' then 'DE'
        when 'A' then 'AT'

      unless country?
        console.error "Unsupported country '#{country}'"
        continue

      customerGroup = xmlHelpers.xmlVal xml, 'group', @NO_CUSTOMER_GROUP
      discount = xmlHelpers.xmlVal xml, 'Discount', '0.0'
      discount = parseFloat discount

      # B2C: set customer group if she has a discount. Otherwise the customer isn't in any group
      customerGroup = @CUSTOMER_GROUP_B2C_WITH_CARD_NAME if customerGroup is @CUSTOMER_GROUP_B2C_NAME
      customerGroup = @NO_CUSTOMER_GROUP if customerGroup is @CUSTOMER_GROUP_B2C_WITH_CARD_NAME and discount is 0

      paymentMethodCode = xmlHelpers.xmlVal xml, 'PaymentMethodCode', []
      paymentMethod = xmlHelpers.xmlVal xml, 'PaymentMethod', []

      if _.isString paymentMethod
        paymentMethod = paymentMethod.split ','

      if _.isString paymentMethodCode
        paymentMethodCode = paymentMethodCode.split ','

      paymentInfo =
        paymentMethod: paymentMethod
        paymentMethodCode: paymentMethodCode
        discount: discount

      xml.Employees or= [ { Employee: [] } ]
      customer = @createCustomerData xml, xml.Employees[0].Employee[0], customerNumber, customerGroupName2Id, customerGroup, country
      if customer
        data =
          customer: customer
          paymentInfo: paymentInfo
        customerData.push data

    customerData

  createCustomerData: (xml, employee, customerNumber, customerGroupName2Id, customerGroup, country) ->
    email = xmlHelpers.xmlVal employee, 'email', xmlHelpers.xmlVal(xml, 'EmailCompany')
    return unless email # we can't import customers without email
    return if _.indexOf(@usedEmails, email) isnt -1 # email already used
    @usedEmails.push email

    streetInfo = @splitStreet xmlHelpers.xmlVal xml, 'Street', ''
    customer =
      email: email
      externalId: customerNumber
      customerNumber: customerNumber
      title: xmlHelpers.xmlVal employee, 'gender', xmlHelpers.xmlVal(xml, 'gender')
      firstName: xmlHelpers.xmlVal employee, 'firstname', xmlHelpers.xmlVal(xml, 'firstname')
      lastName: xmlHelpers.xmlVal employee, 'lastname', xmlHelpers.xmlVal(xml, 'lastname')
      password: xmlHelpers.xmlVal xml, 'password', Math.random().toString(36).slice(2) # some random password
      addresses: [
        streetName: streetInfo.name
        streetNumber: streetInfo.number
        postalCode: xmlHelpers.xmlVal xml, 'zip'
        city: xmlHelpers.xmlVal xml, 'town'
        country: 'DE'
        phone: xmlHelpers.xmlVal xml, 'phone'
      ]

    customer.addresses[0].additionalStreetInfo = streetInfo.additionalStreetInfo if streetInfo.additionalStreetInfo
    if customerGroup isnt @NO_CUSTOMER_GROUP
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

module.exports = CustomerXmlImport