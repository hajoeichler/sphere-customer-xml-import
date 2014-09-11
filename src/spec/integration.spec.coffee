_ = require('underscore')._
Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 10000

describe '#run', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'should stop as updating customers isnt support yet', (done) ->
    rawXml = '
<root>
  <Customer>
    <CustomerNr>1234</CustomerNr>
    <Street>Foo 1</Street>
    <Group>B2B</Group>
    <country>D</country>
    <Employees>
      <Employee>
        <employeeNr>2</employeeNr>
        <email>some.one+27@example.com</email>
        <gender>Mrs.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
    </Employees>
  </Customer>
</root>'
    @import.run(rawXml)
    .then (result) ->
      expect(result[0]).toBe "Customer externalIds already in sync."
      done()
    .fail (err) ->
      console.log "E %j", err
      done err
    .done()

  it 'should create customer and payment info object', (done) ->
    unique = new Date().getTime()
    customerNumber = "5678#{unique}"
    rawXml = "
<root>
  <Customer>
    <CustomerNr>#{customerNumber}</CustomerNr>
    <Street>Foo 1</Street>
    <Group>B2C</Group>
    <country>A</country>
    <Employees>
      <Employee>
        <employeeNr>1</employeeNr>
        <email>some.one.else+#{unique}@example.com</email>
        <gender>Mrs.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
    </Employees>
    <Discount>3.7000</Discount>
    <PaymentMethodCode>101,105</PaymentMethodCode>
    <PaymentMethod>Gutschrift,Vorauskasse</PaymentMethod>
  </Customer>
</root>"
    @import.run(rawXml)
    .then (result) =>
      expect(result[0]).toBe 'Customer created.'
      @import.client.customers.where("customerNumber = \"#{customerNumber}\"").fetch()
    .then (result) =>
      expect(_.size result.body.results).toBe 1
      customer = result.body.results[0]
      expect(customer.customerNumber).toBe customerNumber
      expect(customer.externalId).toBe customerNumber
      expect(customer.firstName).toBe 'Some'
      expect(customer.lastName).toBe 'One'
      expect(customer.email).toBe "some.one.else+#{unique}@example.com"
      expect(customer.password).toBeDefined()
      expect(customer.title).toBe 'Mrs.'
      expect(_.size customer.addresses).toBe 1
      address = customer.addresses[0]
      expect(address.country).toBe 'AT'
      expect(address.streetName).toBe "Foo"
      expect(address.streetNumber).toBe '1'
      @import.client.customObjects.byId("paymentMethodInfo/#{customer.id}").fetch()
    .then (result) ->
      expect(result.body.value).toBeDefined()
      expect(result.body.value.discount).toBe 3.7
      expect(result.body.value.paymentMethod).toEqual [ 'Gutschrift', 'Vorauskasse' ]
      expect(result.body.value.paymentMethodCode).toEqual [ '101', '105' ]
      done()
    .fail (err) ->
      console.log "E %j", err
      done err
    .done()

   it 'should create customer with customer group', (done) ->
    unique = new Date().getTime()
    rawXml = "
<root>
  <Customer>
    <CustomerNr>12123-#{unique}</CustomerNr>
    <Street>Foo 1</Street>
    <Group>B2B</Group>
    <country>D</country>
    <Employees>
      <Employee>
        <employeeNr>1</employeeNr>
        <email>someoneelse+#{unique}@example.com</email>
        <gender>Mrs.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
    </Employees>
  </Customer>
</root>"
    @import.run(rawXml)
    .then (result) ->
      expect(result[0]).toBe 'Customer created.'
      done()
    .fail (err) ->
      console.log "E %j", err
      done err
    .done()

  it 'should create multiple customer', (done) ->
    unique = new Date().getTime()
    rawXml = "
<root>
  <Customer>
    <CustomerNr>multi1-#{unique}</CustomerNr>
    <Street>Foo 1</Street>
    <Group>B2B</Group>
    <country>A</country>
    <Employees>
      <Employee>
        <employeeNr>1</employeeNr>
        <email>mrs.someoneelse+#{unique}@example.com</email>
        <gender>Mrs.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
      <Employee>
        <employeeNr>7</employeeNr>
        <email>mr.someoneelse+#{unique}@example.com</email>
        <gender>Mr.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
    </Employees>
  </Customer>
  <Customer>
    <CustomerNr>multi2#{unique}</CustomerNr>
    <Street>There he goes 99-100</Street>
    <Group>B2C</Group>
    <country>D</country>
    <Employees>
      <Employee>
        <employeeNr>3</employeeNr>
        <email>max.mustermann+#{unique}@example.com</email>
        <gender>Mr.</gender>
        <firstname>Max</firstname>
        <lastname>Mustermann</lastname>
      </Employee>
    </Employees>
    <PaymentMethodCode>101,105</PaymentMethodCode>
    <PaymentMethod>Gutschrift,Vorauskasse</PaymentMethod>
  </Customer>
</root>"
    @import.run(rawXml)
    .then (result) ->
      expect(_.size result).toBe 2
      expect(result[0]).toBe 'Customer created.'
      expect(result[1]).toBe 'Customer created.'
      done()
    .fail (err) ->
      console.log "E %j", err
      done err
    .done()

  it 'should create customer and then update externalId', (done) ->
    unique = new Date().getTime()
    customerNumber = "externalId-update-#{unique}"
    externalNumber = "UPDATED-#{customerNumber}"
    rawXml = "
<root>
  <Customer>
    <CustomerNr>#{customerNumber}</CustomerNr>
    <REPLACE/>
    <Street>Foo 1</Street>
    <Group>B2C</Group>
    <country>A</country>
    <Employees>
      <Employee>
        <employeeNr>1</employeeNr>
        <email>ex.id.update+#{unique}@example.com</email>
        <gender>Mrs.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
    </Employees>
  </Customer>
</root>"
    @import.run(rawXml)
    .then (result) =>
      expect(result[0]).toBe 'Customer created.'
      @import.client.customers.where("customerNumber = \"#{customerNumber}\"").fetch()
    .then (result) =>
      expect(_.size result.body.results).toBe 1
      customer = result.body.results[0]
      expect(customer.customerNumber).toBe customerNumber
      expect(customer.externalId).toBe customerNumber

      rawXmlUpdated = rawXml.replace('<REPLACE/>', "<externalId>#{externalNumber}</externalId>")
      @import.run(rawXmlUpdated)
      .then (result) =>
        expect(result[0]).toBe 'Customer externalId synced.'
        @import.client.customers.where("customerNumber = \"#{customerNumber}\"").fetch()
      .then (result) ->
        expect(_.size result.body.results).toBe 1
        customer = result.body.results[0]
        expect(customer.customerNumber).toBe customerNumber
        expect(customer.externalId).toBe externalNumber
        done()
    .fail (err) ->
      console.log "E %j", err
      done err
    .done()
