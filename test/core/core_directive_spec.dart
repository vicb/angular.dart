library core_directive_spec;

import '../_specs.dart';
import 'package:angular/application_factory.dart';

void main() {
  describe('DirectiveMap', () {

    beforeEachModule((Module module) {
      module..bind(AnnotatedIoComponent);
    });

    it('should extract attr map from annotated component', (DirectiveMap directives) {
      var tuples = directives['annotated-io'];
      expect(tuples.length).toEqual(1);
      expect(tuples[0].directive is Component).toBeTruthy();

      Component annotation = tuples[0].directive;
      expect(annotation.selector).toEqual('annotated-io');
      expect(annotation.visibility).toEqual(Visibility.LOCAL);
      expect(annotation.exportExpressions).toEqual(['exportExpressions']);
      expect(annotation.module).toEqual(AnnotatedIoComponent.module);
      expect(annotation.template).toEqual('template');
      expect(annotation.templateUrl).toEqual('templateUrl');
      expect(annotation.cssUrls).toEqual(['cssUrls']);
      expect(annotation.map).toEqual({
          'foo': '=>foo',
          'attr': '@attr',
          'expr': '<=>expr',
          'expr-one-way': '=>exprOneWay',
          'expr-one-way-one-shot': '=>!exprOneWayOneShot',
          'callback': '&callback',
          'expr-one-way2': '=>exprOneWay2',
          'expr-two-way': '<=>exprTwoWay'
      });
    });

    describe('exceptions', () {
      var baseModule;
      beforeEach(() {
        baseModule = new Module()
          ..bind(DirectiveMap)
          ..bind(DirectiveSelectorFactory)
          ..bind(MetadataExtractor);
      });

      it('should throw when annotation is for existing mapping', () {
        var module = new Module()
            ..bind(Bad1Component);

        var injector = applicationFactory().addModule(module).createInjector();
        expect(() {
          injector.get(DirectiveMap);
        }).toThrowWith(message: 'Mapping for attribute foo is already defined (while '
        'processing annottation for field foo of Bad1Component)');
      });

      it('should throw when annotated both getter and setter', () {
        var module = new Module()
            ..bind(Bad2Component);

        var injector = applicationFactory().addModule(module).createInjector();
        expect(() {
          injector.get(DirectiveMap);
        }).toThrowWith(message: 'Attribute annotation for foo is defined more than once '
        'in Bad2Component');
      });
    });

    describe("Inheritance", () {
      var element;
      var nodeAttrs;

      beforeEachModule((Module module) {
        module..bind(Sub)..bind(Base);
      });

      it("should extract attr map from annotated component which inherits other component", (DirectiveMap directives) {
        var tupls = directives['[sub]'];
        expect(tupls.length).toEqual(1);
        expect(tupls[0].directive is Directive).toBeTruthy();

        Directive annotation = tupls[0].directive;
        expect(annotation.selector).toEqual('[sub]');
        expect(annotation.map).toEqual({
          "foo": "=>foo",
          "bar": "=>bar",
          "baz": "=>baz"
        });
      });
    });
  });
}

class NullParser implements Parser {
  call(x) {
    throw "NullParser";
  }
}

@Component(
    selector: 'annotated-io',
    template: 'template',
    templateUrl: 'templateUrl',
    cssUrl: const ['cssUrls'],
    module: AnnotatedIoComponent.module,
    visibility: Visibility.LOCAL,
    exportExpressions: const ['exportExpressions'],
    map: const {
      'foo': '=>foo'
    })
class AnnotatedIoComponent {
  static module(i) => i.bind(String,
                             toFactory: (i) => i.get(AnnotatedIoComponent),
                             visibility: Visibility.LOCAL);

  AnnotatedIoComponent(Scope scope) {
    scope.rootScope.context['ioComponent'] = this;
  }

  @NgAttr('attr')
  String attr;

  @NgTwoWay('expr')
  String expr;

  @NgOneWay('expr-one-way')
  String exprOneWay;

  @NgOneWayOneTime('expr-one-way-one-shot')
  String exprOneWayOneShot;

  @NgCallback('callback')
  Function callback;

  @NgOneWay('expr-one-way2')
  set exprOneWay2(val) {}

  @NgTwoWay('expr-two-way')
  get exprTwoWay => null;
  set exprTwoWay(val) {}
}

@Component(
    selector: 'bad1',
    template: r'<content></content>',
    map: const {
      'foo': '=>foo'
    })
class Bad1Component {
  @NgOneWay('foo')
  String foo;
}

@Component(
    selector: 'bad2',
    template: r'<content></content>')
class Bad2Component {
  @NgOneWay('foo')
  get foo => null;

  @NgOneWay('foo')
  set foo(val) {}
}

@Decorator(selector: '[sub]')
class Sub extends Base {
  @NgOneWay('bar')
  String bar;
}

class Base {
  @NgOneWay('baz')
  String baz;

  @NgOneWay('foo')
  String foo;
}

