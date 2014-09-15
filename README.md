# sphere-customer-xml-import

[![Build Status](https://secure.travis-ci.org/hajoeichler/sphere-customer-xml-import.png?branch=master)](http://travis-ci.org/hajoeichler/sphere-customer-xml-import) [![Dependency Status](https://david-dm.org/hajoeichler/sphere-customer-xml-import.png?theme=shields.io)](https://david-dm.org/hajoeichler/sphere-customer-xml-import) [![devDependency Status](https://david-dm.org/hajoeichler/sphere-customer-xml-import/dev-status.png?theme=shields.io)](https://david-dm.org/hajoeichler/sphere-customer-xml-import#info=devDependencies)

This repository contains a mapping compontent to translate products from XML data into SPHERE.IO products JSON format.

## Getting Started
Install the module with: `npm install sphere-customer-xml-import`

Put your SPHERE.IO credentials into `config.js` or generate it with execute `./create_config.sh`.

```javascript
var customerXmlImport = require('sphere-store-xml-import').XmlCustomerImport;
```

## Contributing
In lieu of a formal styleguide, take care to maintain the existing coding style. Add unit tests for any new or changed functionality. Lint and test your code using [Grunt](http://gruntjs.com/).

## License
Copyright (c) 2013 Hajo Eichler and Nicola Molinari
Licensed under the MIT license.