fs = require 'fs'
package_json = require '../package.json'
CustomerXmlImport = require '../lib/customerxmlimport'
argv = require('optimist')
  .usage('Usage: $0 --projectKey key --clientId id --clientSecret secret --xmlfile file --timeout timeout')
  .default('timeout', 300000)
  .describe('projectKey', 'your SPHERE.IO project-key')
  .describe('clientId', 'your OAuth client id for the SPHERE.IO API')
  .describe('clientSecret', 'your OAuth client secret for the SPHERE.IO API')
  .describe('xmlfile', 'xmlfile file containing the customers to import')
  .describe('timeout', 'Set timeout for requests')
  .demand(['projectKey', 'clientId', 'clientSecret', 'xmlfile'])
  .argv

options =
  config:
    project_key: argv.projectKey
    client_id: argv.clientId
    client_secret: argv.clientSecret
  timeout: argv.timeout
  user_agent: "#{package_json.name} - #{package_json.version}"

importer = new CustomerXmlImport options

fs.readFile argv.xmlfile, 'utf8', (err, content) ->
  if err
    console.error "Problems on reading file '#{argv.xmlfile}': #{err}"
    process.exit 2
  importer.run(content)
  .then (result) ->
    console.log result
    process.exit 0
  .fail (err) ->
    console.error err
    process.exit 1
  .done()