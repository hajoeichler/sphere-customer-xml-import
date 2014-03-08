_ = require('underscore')._
Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 20000

xdescribe '#run', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'should stop as updating customers isnt support yet', (done) ->
    rawXml = '
<Customer>
  <CustomerNr>1234</CustomerNr>
  <Street>Foo 1</Street>
  <Group>B2B</Group>
  <Employees>
    <Employee>
      <employeeNr>2</employeeNr>
      <email>some.one+27@example.com</email>
      <gender>Mrs.</gender>
      <firstname>Some</firstname>
      <lastname>One</lastname>
    </Employee>
  </Employees>
</Customer>'
    @import.run rawXml, (result) ->
      console.log result unless result.status
      expect(result.status).toBe true
      expect(result.message).toBe 'Update of customer is not implemented yet!'
      done()

  it 'should create customer and payment info object', (done) ->
    unique = new Date().getTime()
    rawXml = "
<Customer>
  <CustomerNr>5678</CustomerNr>
  <Street>Foo 1</Street>
  <Group>B2C</Group>
  <Employees>
    <Employee>
      <employeeNr>1</employeeNr>
      <email>some.one.else+#{unique}@example.com</email>
      <gender>Mrs.</gender>
      <firstname>Some</firstname>
      <lastname>One</lastname>
    </Employee>
  </Employees>
</Customer>"
    @import.run rawXml, (result) ->
      console.log result unless result.status
      expect(result.status).toBe true
      expect(result.message).toBe 'Customer created.'
      done()

   it 'should create customer with customer group', (done) ->
    unique = new Date().getTime()
    rawXml = "
<Customer>
  <CustomerNr>12123</CustomerNr>
  <Street>Foo 1</Street>
  <Group>B2B</Group>
  <Employees>
    <Employee>
      <employeeNr>1</employeeNr>
      <email>someoneelse+#{unique}@example.com</email>
      <gender>Mrs.</gender>
      <firstname>Some</firstname>
      <lastname>One</lastname>
    </Employee>
  </Employees>
</Customer>"
    @import.run rawXml, (result) ->
      console.log result unless result.status
      expect(result.status).toBe true
      expect(result.message).toBe 'Customer created.'
      done()

  it 'should create multiple customer', (done) ->
    unique = new Date().getTime()
    rawXml = "
<Customer>
  <CustomerNr>multi1</CustomerNr>
  <Street>Foo 1</Street>
  <Group>B2B</Group>
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
  <CustomerNr>multi2</CustomerNr>
  <Street>There he goes 99-100</Street>
  <Group>B2C</Group>
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
"
    @import.run rawXml, (result) =>
      console.log result unless result.status
      expect(result.status).toBe true
      expect(_.size result.message).toBe 1
      expect(result.message['Customer created.']).toBe 3
      done()