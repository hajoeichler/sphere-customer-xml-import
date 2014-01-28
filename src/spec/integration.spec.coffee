_ = require('underscore')._
Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 10000

describe 'process', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'one existing customer', (done) ->
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
    @import.run rawXml, (msg) =>
      expect(msg.status).toBe false
      expect(msg.message).toBe 'Update of customer isnt implemented yet!'
      done()

  it 'one new customer', (done) ->
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
    @import.run rawXml, (result) =>
      console.log result unless result.status
      expect(result.status).toBe true
      expect(_.size(result.message)).toBe 2
      expect(result.message['Customer has no paymentInfo.']).toBe 1
      expect(result.message['Customer has no group.']).toBe 1
      done()