/* ===========================================================
# sphere-customer-xml-import - v0.1.3
# ==============================================================
# Copyright (c) 2013 Hajo Eichler
# Licensed under the MIT license.
*/
var parseString;

parseString = require('xml2js').parseString;

exports.xmlFix = function(xml) {
  return xml;
};

exports.xmlTransform = function(xml, callback) {
  return parseString(xml, callback);
};

exports.xmlVal = function(elem, attribName, fallback) {
  if (!(elem && elem[attribName])) {
    return fallback;
  }
  return elem[attribName][0];
};
