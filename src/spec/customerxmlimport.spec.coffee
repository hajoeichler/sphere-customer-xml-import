Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'

describe 'CustomerXmlImport', ->
  beforeEach ->
    @import = new CustomerXmlImport('foo')

  it 'should initialize', ->
    expect(@import).toBeDefined()

describe 'process', ->
  beforeEach ->
    @import = new CustomerXmlImport()

  it 'should throw error if no JSON object is passed', ->
    expect(@import.elasticio).toThrow new Error('JSON Object required')

  it 'should throw error if no JSON object is passed', ->
    expect(=> @import.elasticio({})).toThrow new Error('Callback must be a function')

  it 'should call the given callback and return messge', (done) ->
    @import.elasticio {}, {}, (data)->
      expect(data.status).toBe false
      expect(data.message).toBe 'No XML attachments found!'
      done()

describe '#splitStreet', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it '0', ->
    s = @import.splitStreet "Here"
    expect(s.name).toBe "Here"

  it '1', ->
    s = @import.splitStreet "Segelfalterweg 9"
    expect(s.name).toBe "Segelfalterweg"
    expect(s.number).toBe "9"

  it '2', ->
    s = @import.splitStreet "Foo Bar Str. 7 c"
    expect(s.name).toBe "Foo Bar Str."
    expect(s.number).toBe "7 c"

  it '3', ->
    s = @import.splitStreet "Somewhere. 26 - 28"
    expect(s.name).toBe "Somewhere."
    expect(s.number).toBe "26 - 28"

  it '4', ->
    s = @import.splitStreet "Long Street Name 101/09"
    expect(s.name).toBe "Long Street Name"
    expect(s.number).toBe "101/09"

  it '5', ->
    s = @import.splitStreet "Musterstr. 75 RGB"
    expect(s.name).toBe "Musterstr."
    expect(s.number).toBe "75"
    expect(s.additionalStreetInfo).toBe "RGB"

  it '6', ->
    s = @import.splitStreet "Memminger Str. 58 / Am Stadion"
    expect(s.name).toBe "Memminger Str."
    expect(s.number).toBe "58 /"
    expect(s.additionalStreetInfo).toBe "Am Stadion"

  it '7', ->
    s = @import.splitStreet "Karolinenstrasse 10 - WA : Hinter der Metzg Nr. 7"
    expect(s.name).toBe "Karolinenstrasse"
    expect(s.number).toBe "10 -"
    expect(s.additionalStreetInfo).toBe "WA : Hinter der Metzg Nr. 7"

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
  <Group>B2B</Group>
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

    @import.transform rawXml, 'cg123', (customers) ->
      expect(customers['123'].length).toBe 1
      c = customers['123'][0]
      expect(c.email).toBe 'some.one@example.com'
      expect(c.lastName).toBe 'One'
      expect(c.password).toBeDefined

      expect(c.addresses.length).toBe 1
      a = c.addresses[0]
      expect(a.streetName).toBe 'Somewhere'
      expect(a.streetNumber).toBe '42'
      expect(a.postalCode).toBe '12345'
      expect(a.city).toBe 'Gotham City'
      expect(a.country).toBe 'DE'
      expect(a.phone).toBe '001-1234567890'

      expect(c.customerGroup).toBeDefined
      expect(c.customerGroup.typeId).toBe 'customer-group'
      expect(c.customerGroup.id).toBe 'cg123'
      expect(c.password.length).toBeGreaterThan 7
      done()

  it 'single attachment - customer with two employee', (done) ->
    rawXml = '
<Customer>
  <CustomerNr>1234</CustomerNr>
  <Street>Somewhere 42</Street>
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

    @import.transform rawXml, 'cg123', (customers) ->
      expect(customers['1234'].length).toBe 2
      c = customers['1234'][0]
      expect(c.email).toBe 'some.one@example.com'
      expect(c.lastName).toBe 'One'
      expect(c.password).toBeDefined
      c = customers['1234'][1]
      expect(c.email).toBe 'else@example.com'
      expect(c.lastName).toBe 'Else'
      expect(c.password).toBeDefined
      done()