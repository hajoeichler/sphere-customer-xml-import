Config = require '../config'
CustomerXmlImport = require('../lib/customerxmlimport').CustomerXmlImport

# Increase timeout
jasmine.getEnv().defaultTimeoutInterval = 10000

describe 'process', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'one customer', (done) ->
    rawXml = '
<Customer>
  <CustomerNr>1234</CustomerNr>
  <Street>Foo 1</Street>
  <Group>B2B</Group>
  <Employee>
    <employeeNr>2</employeeNr>
    <email>some.one+13@example.com</email>
    <gender>Mrs.</gender>
    <firstname>Some</firstname>
    <lastname>One</lastname>
  </Employee>
</Customer>'
    d =
      attachments:
        customer: rawXml
    @import.process d, (msg) =>
      expect(msg.message.status).toBe false
      expect(msg.message.msg).toBe 'Not yet implemented'
      done()