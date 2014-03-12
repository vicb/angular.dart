part of angular.core.dom;

/**
 * Callback function used to notify of attribute changes.
 */
typedef AttributeChanged(String newValue);

/**
 * NodeAttrs is a facade for element attributes. The facade is responsible
 * for normalizing attribute names as well as allowing access to the
 * value of the directive.
 */
class NodeAttrs {
  final dom.Element element;

  Map<String, List<AttributeChanged>> _observers;

  NodeAttrs(this.element);

  operator [](String attributeName) =>
      // todo honor notified values
      element.attributes[attributeName];

  operator []=(String attributeName, String value) {
    _notifyObservers(attributeName, value);
    _setValue(attributeName, value);
  }

  Function setDelayed(String attributeName, String value) {
    if (_notifyObservers(attributeName, value)) {
      // todo coalesce writes
      return () => _setValue(attributeName, value);
    }
    return null;
  }

  /**
   * Observe changes to the attribute by invoking the [AttributeChanged]
   * function. On registration the [AttributeChanged] function gets invoked
   * to synchronise with the current value.
   */
  observe(String attributeName, AttributeChanged notifyFn) {
    if (_observers == null) {
      _observers = new Map<String, List<AttributeChanged>>();
    }
    if (!_observers.containsKey(attributeName)) {
      _observers[attributeName] = new List<AttributeChanged>();
    }
    _observers[attributeName].add(notifyFn);
    notifyFn(this[attributeName]);
  }

  void forEach(void f(String k, String v)) {
    element.attributes.forEach(f);
  }

  bool containsKey(String attributeName) =>
      element.attributes.containsKey(attributeName);

  Iterable<String> get keys => element.attributes.keys;

  void _setValue(String attributeName, String value) {
    if (value == null) {
      element.attributes.remove(attributeName);
    } else {
      element.attributes[attributeName] = value;
    }
  }

  bool _notifyObservers(String attributeName, String value) {
    if (_observers != null && _observers.containsKey(attributeName)) {
      _observers[attributeName].forEach((fn) => fn(value));
      return true;
    }
    return false;
  }
}

/**
 * TemplateLoader is an asynchronous access to ShadowRoot which is
 * loaded asynchronously. It allows a Component to be notified when its
 * ShadowRoot is ready.
 */
class TemplateLoader {
  final async.Future<dom.ShadowRoot> _template;

  async.Future<dom.ShadowRoot> get template => _template;

  TemplateLoader(this._template);
}
