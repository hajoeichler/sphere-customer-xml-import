_ = require('underscore')._
Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 20000

describe '#run', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'should stop as updating customers isnt support yet', (done) ->
    rawXml = '
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
</Customer>'
    @import.run(rawXml)
    .then (result) ->
      expect(result[0]).toBe 'Update of customer is not implemented yet!'
      done()
    .fail (err) ->
      console.log "E %j", err
      done err

  it 'should create customer and payment info object', (done) ->
    unique = new Date().getTime()
    rawXml = "
<Customer>
  <CustomerNr>5678#{unique}</CustomerNr>
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
</Customer>"
    @import.run(rawXml)
    .then (result) ->
      expect(result[0]).toBe 'Customer created.'
      done()
    .fail (err) ->
      console.log "E %j", err
      done err

   it 'should create customer with customer group', (done) ->
    unique = new Date().getTime()
    rawXml = "
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
</Customer>"
    @import.run(rawXml)
    .then (result) ->
      expect(result[0]).toBe 'Customer created.'
      done()
    .fail (err) ->
      console.log "E %j", err
      done err

  it 'should create multiple customer', (done) ->
    unique = new Date().getTime()
    rawXml = "
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
"
    @import.run(rawXml)
    .then (result) ->
      expect(_.size result).toBe 2
      expect(result[0]).toBe 'Customer created.'
      expect(result[1]).toBe 'Customer created.'
      done()
    .fail (err) ->
      console.log "E %j", err
      done err
