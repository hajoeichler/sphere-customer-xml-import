/* ===========================================================
# sphere-customer-xml-import - v0.1.3
# ==============================================================
# Copyright (c) 2013 Hajo Eichler
# Licensed under the MIT license.
*/
var CUSTOMER_GROUP_B2B_NAME, CUSTOMER_GROUP_B2C_NAME, CUSTOMER_GROUP_B2C_WITH_CARD_NAME, CustomerXmlImport, NO_CUSTOMER_GROUP, Q, SphereClient, crypto, parseString, xmlHelpers, _;

_ = require('underscore');

parseString = require('xml2js').parseString;

SphereClient = require('sphere-node-client');

Q = require('q');

crypto = require('crypto');

xmlHelpers = require('../lib/xmlhelpers');

NO_CUSTOMER_GROUP = 'NONE';

CUSTOMER_GROUP_B2C_NAME = 'B2C';

CUSTOMER_GROUP_B2B_NAME = 'B2B';

CUSTOMER_GROUP_B2C_WITH_CARD_NAME = 'B2C with card';

CustomerXmlImport = (function() {
  function CustomerXmlImport(options) {
    if (options == null) {
      options = {};
    }
    this.client = new SphereClient(options);
    this;
  }

  CustomerXmlImport.prototype.run = function(xmlString) {
    return Q.all([this.ensureCustomerGroupByName(CUSTOMER_GROUP_B2B_NAME), this.ensureCustomerGroupByName(CUSTOMER_GROUP_B2C_WITH_CARD_NAME)]).spread((function(_this) {
      return function(b2bCustomerGroup, b2cWithCardCustomerGroup) {
        var customerGroupName2Id;
        customerGroupName2Id = {};
        customerGroupName2Id[CUSTOMER_GROUP_B2B_NAME] = b2bCustomerGroup.id;
        customerGroupName2Id[CUSTOMER_GROUP_B2C_WITH_CARD_NAME] = b2cWithCardCustomerGroup.id;
        return _this.transform(xmlString, customerGroupName2Id);
      };
    })(this)).then((function(_this) {
      return function(customerData) {
        return _this.createOrUpdate(customerData);
      };
    })(this));
  };

  CustomerXmlImport.prototype.ensureCustomerGroupByName = function(name) {
    return this.client.customerGroups.fetch().then((function(_this) {
      return function(result) {
        var customerGroup;
        customerGroup = _.find(result.body.results, function(cg) {
          return cg.name === name;
        });
        if (customerGroup != null) {
          return Q(customerGroup);
        } else {
          customerGroup = {
            groupName: name
          };
          return _this.client.customerGroups.save(customerGroup);
        }
      };
    })(this));
  };

  CustomerXmlImport.prototype.createOrUpdate = function(customerData) {
    return this.client.customers.perPage(0).fetch().then((function(_this) {
      return function(result) {
        var ec, email2id, existingCustomers, posts, usedCustomerNumbers, _i, _len;
        existingCustomers = result.body.results;
        email2id = {};
        usedCustomerNumbers = [];
        for (_i = 0, _len = existingCustomers.length; _i < _len; _i++) {
          ec = existingCustomers[_i];
          email2id[ec.email] = ec;
          usedCustomerNumbers.push(ec.customerNumber);
        }
        console.log("Existing customers: " + _.size(email2id));
        posts = _.map(customerData, function(data) {
          var customer, index, paymentInfo;
          customer = data.customer;
          paymentInfo = data.paymentInfo;
          if (_.has(email2id, customer.email)) {
            if (_.size(email2id[customer.email].addresses || []) === 0) {
              return Q("Customer without address");
            } else {
              return _this.syncIdenfifier(customer, email2id[customer.email]);
            }
          } else if (_.contains(usedCustomerNumbers, customer.customerNumber)) {
            index = _.indexOf(usedCustomerNumbers, customer.customerNumber);
            console.log("Email has changed: '" + existingCustomers[index].email + "' -> '" + customer.email + "'");
            return Q("Update of customer is not implemented yet - number '" + customer.customerNumber + "' exists!");
          } else {
            return _this.create(customer, paymentInfo);
          }
        });
        if (_.size(posts) === 0) {
          return Q('Nothing done.');
        } else {
          console.log("Processing " + (_.size(posts)) + " customer(s)...");
          return Q.all(posts);
        }
      };
    })(this));
  };

  CustomerXmlImport.prototype.resetPassword = function(newCustomer, email, existingCustomer) {
    return this.client.customers._task.addTask((function(_this) {
      return function() {
        var deferred;
        deferred = Q.defer();
        _this.client._rest.POST('/customers/password-token', {
          email: email
        }, function(error, response, body) {
          var data;
          if (error != null) {
            return deferred.reject("Error on getting passwd reset token: " + error);
          } else if (response.statusCode !== 200) {
            console.error("Password token: %j", body);
            return deferred.reject("Problem on getting passwd reset token: " + body);
          } else {
            data = {
              id: existingCustomer.id,
              version: existingCustomer.version,
              tokenValue: body.value,
              newPassword: newCustomer.password
            };
            return _this.client._rest.POST('/customers/password/reset', data, function(error, response, body) {
              if (error != null) {
                return deferred.reject("Error on reseting passwd: " + error);
              } else if (response.statusCode !== 200) {
                console.error("Password reset: %j", body);
                return deferred.reject("Problem on getting passwd reset token: " + body);
              } else {
                return deferred.resolve("Password reset done.");
              }
            });
          }
        });
        return deferred.promise;
      };
    })(this));
  };

  CustomerXmlImport.prototype.ensurePaymentInfo = function(existingCustomer, paymentInfo) {
    var deferred;
    deferred = Q.defer();
    this.createPaymentInfo(existingCustomer, paymentInfo).then(function(result) {
      return deferred.resolve('PaymentMethodInfo ensured.');
    }).fail(function(err) {
      return deferred.reject(err);
    }).done();
    return deferred.promise;
  };

  CustomerXmlImport.prototype.syncIdenfifier = function(newCustomer, existingCustomer) {
    var data, deferred;
    deferred = Q.defer();
    if (newCustomer.customerNumber === existingCustomer.customerNumber) {
      if (newCustomer.externalId !== existingCustomer.externalId) {
        data = {
          id: existingCustomer.id,
          version: existingCustomer.version,
          actions: [
            {
              action: 'setExternalId',
              externalId: newCustomer.externalId
            }
          ]
        };
        this.client.customers.byId(existingCustomer.id).save(data).then(function(result) {
          return deferred.resolve('Customer externalId synced.');
        }).fail(function(err) {
          return deferred.reject(err);
        }).done();
      } else {
        deferred.resolve("Customer externalIds already in sync.");
      }
    } else {
      console.log("Customer number has changed: '" + existingCustomer.customerNumber + "' -> '" + newCustomer.customerNumber + "'");
      deferred.resolve("Customer numbers do not match for externalId sync.");
    }
    return deferred.promise;
  };

  CustomerXmlImport.prototype.create = function(newCustomer, paymentInfo) {
    var deferred;
    deferred = Q.defer();
    this.createCustomer(newCustomer).then((function(_this) {
      return function(result) {
        return _this.addAddress(result.body.customer, newCustomer.addresses[0]);
      };
    })(this)).then((function(_this) {
      return function(result) {
        return _this.linkCustomerIntoGroup(result.body, newCustomer.customerGroup);
      };
    })(this)).then((function(_this) {
      return function(result) {
        return _this.createPaymentInfo(result.body, paymentInfo);
      };
    })(this)).then(function(result) {
      return deferred.resolve('Customer created.');
    }).fail(function(err) {
      return deferred.reject(err);
    }).done();
    return deferred.promise;
  };

  CustomerXmlImport.prototype.createCustomer = function(newCustomer) {
    return this.client.customers.save(newCustomer);
  };

  CustomerXmlImport.prototype.addAddress = function(customer, address) {
    var data;
    data = {
      id: customer.id,
      version: customer.version,
      actions: [
        {
          action: 'addAddress',
          address: address
        }
      ]
    };
    return this.client.customers.byId(customer.id).save(data);
  };

  CustomerXmlImport.prototype.linkCustomerIntoGroup = function(customer, customerGroup) {
    var data;
    if (customerGroup == null) {
      return Q({
        body: customer
      });
    } else {
      data = {
        id: customer.id,
        version: customer.version,
        actions: [
          {
            action: 'setCustomerGroup',
            customerGroup: customerGroup
          }
        ]
      };
      return this.client.customers.byId(customer.id).save(data);
    }
  };

  CustomerXmlImport.prototype.createPaymentInfo = function(customer, paymentInfo) {
    var customObj, msg;
    if (paymentInfo == null) {
      msg = "No paymentMethodInfo for customer " + customer.id;
      console.error(msg);
      return Q(msg);
    } else {
      customObj = {
        container: "paymentMethodInfo",
        key: customer.id,
        value: paymentInfo
      };
      return this.client.customObjects.save(customObj);
    }
  };

  CustomerXmlImport.prototype.transform = function(rawXml, customerGroupName2Id) {
    var deferred;
    deferred = Q.defer();
    xmlHelpers.xmlTransform(xmlHelpers.xmlFix(rawXml), (function(_this) {
      return function(err, result) {
        if (err != null) {
          return deferred.reject('Error on parsing XML:' + err);
        } else {
          return deferred.resolve(_this.mapCustomers(result.root, customerGroupName2Id));
        }
      };
    })(this));
    return deferred.promise;
  };

  CustomerXmlImport.prototype.mapCustomers = function(xmljs, customerGroupName2Id) {
    var country, customer, customerData, customerGroup, customerNumber, data, discount, externalId, k, paymentInfo, paymentMethod, paymentMethodCode, rawCountry, xml, _ref;
    customerData = [];
    this.usedEmails = [];
    _ref = xmljs.Customer;
    for (k in _ref) {
      xml = _ref[k];
      customerNumber = xmlHelpers.xmlVal(xml, 'CustomerNr');
      externalId = xmlHelpers.xmlVal(xml, 'externalId');
      rawCountry = xmlHelpers.xmlVal(xml, 'country');
      country = (function() {
        switch (rawCountry) {
          case 'D':
            return 'DE';
          case 'A':
            return 'AT';
        }
      })();
      if (country == null) {
        console.error("Unsupported country '" + rawCountry + "'");
        continue;
      }
      customerGroup = xmlHelpers.xmlVal(xml, 'group', NO_CUSTOMER_GROUP);
      discount = xmlHelpers.xmlVal(xml, 'Discount', '0.0');
      discount = parseFloat(discount);
      if (customerGroup === CUSTOMER_GROUP_B2C_NAME) {
        customerGroup = CUSTOMER_GROUP_B2C_WITH_CARD_NAME;
      }
      if (customerGroup === CUSTOMER_GROUP_B2C_WITH_CARD_NAME && discount === 0) {
        customerGroup = NO_CUSTOMER_GROUP;
      }
      paymentMethodCode = xmlHelpers.xmlVal(xml, 'PaymentMethodCode', []);
      paymentMethod = xmlHelpers.xmlVal(xml, 'PaymentMethod', []);
      if (_.isString(paymentMethod)) {
        paymentMethod = paymentMethod.split(',');
      }
      if (_.isString(paymentMethodCode)) {
        paymentMethodCode = paymentMethodCode.split(',');
      }
      paymentInfo = {
        paymentMethod: paymentMethod,
        paymentMethodCode: paymentMethodCode,
        discount: discount
      };
      xml.Employees || (xml.Employees = [
        {
          Employee: []
        }
      ]);
      customer = this.createCustomerData(xml, xml.Employees[0].Employee[0], customerNumber, externalId, customerGroupName2Id, customerGroup, country);
      if (customer != null) {
        data = {
          customer: customer,
          paymentInfo: paymentInfo
        };
        customerData.push(data);
      }
    }
    return customerData;
  };

  CustomerXmlImport.prototype.createCustomerData = function(xml, employee, customerNumber, externalId, customerGroupName2Id, customerGroup, country) {
    var customer, email, streetInfo;
    email = xmlHelpers.xmlVal(employee, 'email', xmlHelpers.xmlVal(xml, 'EmailCompany'));
    if (email == null) {
      return;
    }
    if (_.indexOf(this.usedEmails, email) !== -1) {
      console.warn("Email " + email + " at least twice in XML!");
      return;
    }
    this.usedEmails.push(email);
    streetInfo = this.splitStreet(xmlHelpers.xmlVal(xml, 'Street', ''));
    customer = {
      email: email,
      externalId: externalId || customerNumber,
      customerNumber: customerNumber,
      title: xmlHelpers.xmlVal(employee, 'gender', xmlHelpers.xmlVal(xml, 'gender')),
      firstName: xmlHelpers.xmlVal(employee, 'firstname', xmlHelpers.xmlVal(xml, 'firstname', '-')),
      lastName: xmlHelpers.xmlVal(employee, 'lastname', xmlHelpers.xmlVal(xml, 'lastname')),
      password: xmlHelpers.xmlVal(xml, 'password', Math.random().toString(36).slice(2)),
      addresses: [
        {
          streetName: streetInfo.name,
          streetNumber: streetInfo.number,
          postalCode: xmlHelpers.xmlVal(xml, 'zip'),
          city: xmlHelpers.xmlVal(xml, 'town'),
          country: country,
          phone: xmlHelpers.xmlVal(xml, 'phone')
        }
      ]
    };
    if (streetInfo.additionalStreetInfo) {
      customer.addresses[0].additionalStreetInfo = streetInfo.additionalStreetInfo;
    }
    if (customerGroup !== NO_CUSTOMER_GROUP) {
      customer.customerGroup = {
        typeId: 'customer-group',
        id: customerGroupName2Id[customerGroup]
      };
    }
    return customer;
  };

  CustomerXmlImport.prototype.splitStreet = function(street) {
    var index, num, regex, str;
    regex = new RegExp(/\d+/);
    index = street.search(regex);
    if (index < 0) {
      str = {
        name: street
      };
      return str;
    }
    num = street.substring(index).trim();
    str = {
      name: street.substring(0, index).trim(),
      number: num
    };
    regex = new RegExp(/[a-zA-Z]{2,}/);
    index = num.search(regex);
    if (index > 0) {
      str.number = num.substring(0, index).trim();
      str.additionalStreetInfo = num.substring(index).trim();
    }
    return str;
  };

  return CustomerXmlImport;

})();

module.exports = CustomerXmlImport;
