library event_handler_spec;

import '../_specs.dart';

@Component(selector: 'bar',
    template: '''
              <div>
                <span on-abc="invoked=true;"></span>
                <content></content>
              </div>
              ''')
class BarComponent {
  var invoked = false;
  BarComponent(RootScope scope) {
    scope.context['barComponent'] = this;
  }
}

main() {
  describe('EventHandler', () {
    Element ngAppElement;
    beforeEachModule((Module module) {
      ngAppElement = new DivElement()..attributes['ng-app'] = '';
      module..bind(BarComponent);
      module..bind(Node, toValue: ngAppElement);
      document.body.append(ngAppElement);
    });

    afterEach(() {
      ngAppElement.remove();
      ngAppElement = null;
    });

    compile(_, html) {
      ngAppElement.setInnerHtml(html, treeSanitizer: new NullTreeSanitizer());
      _.compile(ngAppElement);
      return ngAppElement.firstChild;
    }

    it('should register and handle event', (TestBed _) {
      var e = compile(_,
        '''<div>
          <div on-abc="invoked=true;"></div>
        </div>''');

      _.triggerEvent(e.querySelector('[on-abc]'), 'abc');
      expect(_.rootScope.context['invoked']).toEqual(true);
    });

    it('shoud register and handle event with long name', (TestBed _) {
      var e = compile(_,
        '''<div>
          <div on-my-new-event="invoked=true;"></div>
        </div>''');

      _.triggerEvent(e.querySelector('[on-my-new-event]'), 'myNewEvent');
      expect(_.rootScope.context['invoked']).toEqual(true);
    });

    it('shoud have model updates applied correctly', (TestBed _) {
      var e = compile(_,
        '''<div>
          <div on-abc='description="new description";'>{{description}}</div>
        </div>''');
      var el = document.querySelector('[on-abc]');
      el.dispatchEvent(new Event('abc'));
      _.rootScope.apply();
      expect(el.text).toEqual("new description");
    });

    it('shoud register event when shadow dom is used', async((TestBed _) {
      var e = compile(_,'<bar></bar>');

      microLeap();

      var shadowRoot = e.shadowRoot;
      var span = shadowRoot.querySelector('span');
      span.dispatchEvent(new CustomEvent('abc'));
      BarComponent ctrl = _.rootScope.context['barComponent'];
      expect(ctrl.invoked).toEqual(true);
    }));

    it('shoud handle event within content only once', async((TestBed _) {
      var e = compile(_,
        '''<div>
             <bar>
               <div on-abc="invoked=true;"></div>
             </bar>
           </div>''');

      microLeap();

      document.querySelector('[on-abc]').dispatchEvent(new Event('abc'));
      var shadowRoot = document.querySelector('bar').shadowRoot;
      var shadowRootScope = _.getScope(shadowRoot);
      expect(shadowRootScope.context.invoked).toEqual(false);

      expect(_.rootScope.context['invoked']).toEqual(true);
    }));
  });
}
