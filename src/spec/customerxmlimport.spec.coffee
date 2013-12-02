Config = require '../config'
CustomerXmlImport = require('../lib/customerxmlimport').CustomerXmlImport

describe 'CustomerXmlImport', ->
  beforeEach ->
    @import = new CustomerXmlImport('foo')

  it 'should initialize', ->
    expect(@import).toBeDefined()

  it 'should initialize with options', ->
    expect(@import._options).toBe 'foo'


describe 'process', ->
  beforeEach ->
    @import = new CustomerXmlImport()

  it 'should throw error if no JSON object is passed', ->
    expect(@import.process).toThrow new Error('JSON Object required')

  it 'should throw error if no JSON object is passed', ->
    expect(=> @import.process({})).toThrow new Error('Callback must be a function')

  it 'should call the given callback and return messge', (done) ->
    @import.process {}, (data)->
      expect(data.message.status).toBe false
      expect(data.message.msg).toBe 'No XML data attachments found.'
      done()

describe 'transform', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'single attachment - customer with one employee', (done) ->
    rawXml = '
<Customer>
  <CustomerNr>123</CustomerNr>
  <uidShop></uidShop>
  <SessionLanguage></SessionLanguage>
  <EmailCompany>some.one@example.com</EmailCompany>
  <genderCode>1</genderCode>
  <gender>Dear Mrs.</gender>
  <Firstname></Firstname>
  <LastName>One</LastName>
  <Password></Password>
  <Group>B2C</Group>
  <Street>Somewhere 42</Street>
  <zip>12345</zip>
  <town>Gotham City</town>
  <country>D</country>
  <phone>001-1234567890</phone>
  <Employee>
    <employeeNr>1</employeeNr>
    <email>some.one@example.com</email>
    <gender>Mrs.</gender>
    <firstname>Some</firstname>
    <lastname>One</lastname>
  </Employee>
</Customer>'

    @import.transform @import.getAndFix(rawXml), (customers) ->
      expect(customers.length).toBe 1
      c = customers[0]
      expect(c.email).toBe 'some.one@example.com'
      expect(c.lastName).toBe 'One'
      expect(c.password).toBeDefined
      console.log c.password
      done()

  it 'single attachment - customer with two employee', (done) ->
    rawXml = '
<Customer>
  <CustomerNr>1234</CustomerNr>
  <Employee>
    <employeeNr>2</employeeNr>
    <email>some.one@example.com</email>
    <gender>Mrs.</gender>
    <firstname>Some</firstname>
    <lastname>One</lastname>
  </Employee>
  <Employee>
    <employeeNr>4</employeeNr>
    <email>else@example.com</email>
    <gender>Mr.</gender>
    <lastname>Else</lastname>
  </Employee>
</Customer>'

    @import.transform @import.getAndFix(rawXml), (customers) ->
      expect(customers.length).toBe 2
      c = customers[0]
      expect(c.email).toBe 'some.one@example.com'
      expect(c.lastName).toBe 'One'
      expect(c.password).toBeDefined
      c = customers[1]
      expect(c.email).toBe 'else@example.com'
      expect(c.lastName).toBe 'Else'
      expect(c.password).toBeDefined

      done()