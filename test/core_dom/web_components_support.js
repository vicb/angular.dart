/**
 * Used to create Javascript Web Components from Dart tests
 */
function angularTestsRegisterElement(name, prototype) {
  // Polymer requires that all prototypes are chained to HTMLElement
  // https://github.com/Polymer/CustomElements/issues/121
  //_prototype = _prototype || {};
  //function F() {}
  //F.prototype = HTMLElement;
  //var prototype = new F();
  //for (var p in _prototype) {
  //  if (_prototype.hasOwnProperty(p)) {
  //    prototype[p] = _prototype[p];
  //  }
  //}
  //prototype.__proto__ = HTMLElement.prototype;
  var proto = Object.create(HTMLElement.prototype);
  for (var p in prototype) {
    if (prototype.hasOwnProperty(p)) {
      proto[p] = prototype[p];
    }
  }


  prototype.createdCallback = function() {};
  document.registerElement(name, {prototype: proto});
}
