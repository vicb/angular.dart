/**
 * Used to create Javascript Web Components from Dart tests
 */
function angularTestsRegisterElement(name, _prototype) {
  // Polymer requires that all prototypes are chained to HTMLElement
  // https://github.com/Polymer/CustomElements/issues/121
  _prototype = _prototype || {};
  function F() {}
  F.prototype = HTMLElement;
  var prototype = new F();
  for (var p in _prototype) {
    if (_prototype.hasOwnProperty(p)) {
      prototype[p] = _prototype[p];
    }
  }
  prototype.createdCallback = function() {};
  document.registerElement(name, {prototype: prototype});
}
