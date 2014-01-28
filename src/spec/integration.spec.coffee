Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'

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