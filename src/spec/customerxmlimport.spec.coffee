Config = require '../config'
CustomerXmlImport = require '../lib/customerxmlimport'
_ = require('underscore')._

describe 'CustomerXmlImport', ->
  beforeEach ->
    @import = new CustomerXmlImport Config

  it 'should initialize', ->
    expect(@import).toBeDefined()

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

  it 'single attachment - customer without employee', (done) ->
    rawXml = '
<root>
  <Customer>
    <CustomerNr>customer123</CustomerNr>
    <EmailCompany>me@example.com</EmailCompany>
    <genderCode>1</genderCode>
    <gender>Dear Mrs.</gender>
    <firstname>Me</firstname>
    <lastname>Be</lastname>
    <group>B2B</group>
    <Street>Somewhere 42</Street>
    <zip>12345</zip>
    <town>Gotham City</town>
    <country>D</country>
    <phone>001-1234567890</phone>
    <Discount>3.500</Discount>
  </Customer>
</root>'

    @import.transform(rawXml, B2B: 'customerGroupA').then (customerData) ->
      expect(_.size customerData).toBe 1
      c = customerData[0].customer
      expect(c.email).toBe 'me@example.com'
      expect(c.externalId).toBe 'customer123'
      expect(c.customerNumber).toBe 'customer123'
      expect(c.firstName).toBe 'Me'
      expect(c.lastName).toBe 'Be'
      expect(c.password).toBeDefined

      done()

  it 'single attachment - customer with one employee', (done) ->
    rawXml = '
<root>
  <Customer>
    <CustomerNr>123</CustomerNr>
    <EmailCompany>some.one@example.com</EmailCompany>
    <genderCode>1</genderCode>
    <gender>Dear Mrs.</gender>
    <firstname></firstname>
    <lastname>One</lastname>
    <group>B2B</group>
    <Street>Somewhere 42</Street>
    <zip>12345</zip>
    <town>Gotham City</town>
    <country>D</country>
    <phone>001-1234567890</phone>
    <Employees>
      <Employee>
        <employeeNr>1</employeeNr>
        <email>some.one@example.com</email>
        <gender>Mrs.</gender>
        <firstname>Some</firstname>
        <lastname>One</lastname>
      </Employee>
    </Employees>
    <Discount>3.500</Discount>
  </Customer>
</root>'

    @import.transform(rawXml, B2B: 'cg123').then (customerData) ->
      expect(_.size customerData).toBe 1
      c = customerData[0].customer
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

      paymentInfo = customerData[0].paymentInfo
      expect(paymentInfo.paymentMethodCode).toEqual [ ]
      expect(paymentInfo.paymentMethod).toEqual [ ]
      expect(paymentInfo.discount).toEqual 3.5

      done()
    .fail (msg) ->
      console.log msg
      expect(true).toBe false
      done()

  it 'single attachment - customer with two employee', (done) ->
    rawXml = '
<root>
<Customer>
  <CustomerNr>1234</CustomerNr>
  <Street>Somewhere 42</Street>
  <EmailCompany>company@example.com</EmailCompany>
  <country>A</country>
  <Employees>
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
  </Employees>
  <PaymentMethodCode>101,105</PaymentMethodCode>
  <PaymentMethod>Gutschrift,Vorauskasse</PaymentMethod>
</Customer>
</root>'

    @import.transform(rawXml, B2C: 'cg123').then (customerData) ->
      expect(_.size customerData).toBe 1
      c = customerData[0].customer
      expect(c.email).toBe 'some.one@example.com'
      expect(c.firstName).toBe 'Some'
      expect(c.lastName).toBe 'One'
      expect(c.password).toBeDefined
      paymentInfo = customerData[0].paymentInfo
      expect(paymentInfo.paymentMethodCode).toEqual ['101','105']
      expect(paymentInfo.paymentMethod).toEqual ['Gutschrift','Vorauskasse']
      expect(paymentInfo.discount).toEqual 0

      done()
    .fail (msg) ->
      console.log msg
      expect(true).toBe false
      done()
