library ng_show_hide_spec;

import '../_specs.dart';


main() {
  describe('NgHide', () {
    TestBed _;
    beforeEach((TestBed tb) => _ = tb);

    it('should add/remove ng-hide class', () {
      _.compile('<div bind-ng-hide="isHidden"></div>');

      expect(_.rootElement).not.toHaveClass('ng-hide');

      _.rootScope.apply('isHidden = true');
      expect(_.rootElement).toHaveClass('ng-hide');

      _.rootScope.apply('isHidden = false');
      expect(_.rootElement).not.toHaveClass('ng-hide');
    });
  });

  describe('NgShow', () {
    TestBed _;
    beforeEach((TestBed tb) => _ = tb);

    it('should add/remove ng-hide class', () {
      _.compile('<div bind-ng-show="isShown"></div>');

      expect(_.rootElement).not.toHaveClass('ng-hide');

      _.rootScope.apply('isShown = true');
      expect(_.rootElement).not.toHaveClass('ng-hide');

      _.rootScope.apply('isShown = false');
      expect(_.rootElement).toHaveClass('ng-hide');
    });
  });
}
