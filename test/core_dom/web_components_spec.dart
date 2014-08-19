library angular.dom.web_components_spec;

import '../_specs.dart';
import 'dart:js' as js;

registerElement(String name, prototype) {
  js.context['angularTestsRegisterElement'].apply(
          [name, new js.JsObject.jsify(prototype)]);
}



main() {
  ddescribe('WebComponent support', () {
    TestBed _;

    /**
     * Returns the property [prop] as read through the JS interface.
     * [elt] is optional and defaults to the [TestBed]'s rootElement.
     */
    customProp(String prop, [Element elt]) {
      if (elt == null) elt = _.rootElement;
      return (new js.JsObject.fromBrowserObject(elt))[prop];
    }

    /**
     * Sets the property [prop] to [value] through the JS interface.
     * [elt] is optional and defaults to the [TestBed]'s rootElement.
     */
    void setCustomProp(String prop, value, [Element elt]) {
      if (elt == null) elt = _.rootElement;
      (new js.JsObject.fromBrowserObject(_.rootElement))[prop] = value;
    }

    compileAndUpgrade(String html) {
      _.compile(html);
      var CustomElements = js.context['CustomElements'];
      if (CustomElements != null) {
        CustomElements['upgradeAll'].apply([new js.JsObject.fromBrowserObject(_.rootElement)]);
      }
    }

    beforeEach((TestBed tb) {
      _ = tb;
    });

    it('should create custom elements', () {
      registerElement('tests-basic', {'prop-x': 6});

      // Create a web component
      compileAndUpgrade('<tests-basic></tests-basic>');
      expect(customProp('prop-x')).toEqual(6);
    });


    it('should bind to Custom Element properties', () {
      registerElement('tests-bound', {'prop-y': 10});
      compileAndUpgrade('<tests-bound bind-prop-y=27></tests-bound>');

      // Scope has not been digested yet
      expect(customProp('prop-y')).toEqual(10);

      _.rootScope.apply();
      expect(customProp('prop-y')).toEqual(27);
    });


    it('should bind to a non-existent property', () {
      registerElement('tests-empty', {});
      compileAndUpgrade('<tests-empty bind-new-prop=27></tests-empty>');
      _.rootScope.apply();
      expect(customProp('new-prop')).toEqual(27);
    });

    it('should bind to both directives and properties', () {
      registerElement('tests-double', {});
      compileAndUpgrade('<tests-double ng-bind bind-ng-bind="\'hello\'"></tests-double>');
      _.rootScope.apply();
      expect(customProp('ng-bind')).toEqual("hello");
      expect(_.rootElement).toHaveText('hello');
    });

    it('should support two-way bindings for components that trigger a change event', () {
      registerElement('tests-twoway', {});
      compileAndUpgrade('<tests-twoway bind-prop="x"></tests-twoway>');

      setCustomProp('prop', 6);
      _.rootElement.dispatchEvent(new Event.eventType('CustomEvent', 'change'));

      expect(_.rootScope.context['x']).toEqual(6);
    });
  });
}
