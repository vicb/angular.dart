/**
 * Used to create Javascript Web Components from Dart tests
 *
 * The prototype must inherit from `HTMLElement`.
 *
 * see http://w3c.github.io/webcomponents/spec/custom/#extensions-to-document-interface-to-register
 */
function angularTestsRegisterElement(name, prototype) {
  function F() {}
  F.prototype = HTMLElement;
  prototype.prototype = new F();
  document.registerElement(name, {prototype: prototype});
}
