{parseString} = require 'xml2js'

exports.xmlFix = (xml) ->
#  if not xml.match /\?xml/
#    xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>#{xml}"
  xml

exports.xmlTransform = (xml, callback) ->
  parseString xml, callback

exports.xmlVal = (elem, attribName, fallback) ->
  return fallback unless elem and elem[attribName]
  elem[attribName][0]