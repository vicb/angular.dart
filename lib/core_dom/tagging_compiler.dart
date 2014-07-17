part of angular.core.dom_internal;

NodeBinder _addBinder(List list, NodeBinder binder) {
  assert(binder.parentBinderOffset != list.length); // Do not point to yourself!
  list.add(binder);
  return binder;
}

@Injectable()
class TaggingCompiler implements Compiler {
  final Profiler _perf;
  final Expando _expando;

  TaggingCompiler(this._perf, this._expando);

  _compileSiblings(NodeCursor domCursor,
                   DirectiveSelector selector,
                   List<NodeBinder> elementBinders,
                   NodeBinder parentNodeBinder,
                   int parentNodeBinderOffset) {
    if (domCursor.current == null) return null;

    int index = 0;
    do {
      var node = domCursor.current;
      if (node.nodeType == dom.Node.ELEMENT_NODE) {
        NodeBinder binder = selector.matchElement(node);
        binder.parentBinderOffset = parentNodeBinderOffset;
        elementBinders.add(binder);
        NodeBinder transcludeBinder = binder.transcludeBinder;
        if (transcludeBinder != null) {
          binder.viewFactory = _compileTransclusion(domCursor, binder.anchorAttrs,
              transcludeBinder, selector);
        }
        if (!binder.isTerminal && domCursor.descend()) {
          _compileSiblings(domCursor, selector, elementBinders, binder, elementBinders.length - 1);
          domCursor.ascend();
        }
      } else if (node.nodeType == dom.Node.TEXT_NODE) {
        if (parentNodeBinder == null) throw "Can not bind to naked Text nodes.";
        selector.matchText(parentNodeBinder, index, node);
      }
      index++;
    } while (domCursor.moveNext());
  }

  TaggingViewFactory _compileTransclusion(
      NodeCursor templateCursor,
      Map<String, String> anchorAttrs,
      NodeBinder transcludedNodeBinder,
      DirectiveSelector selector)
  {
    var parent = templateCursor.current.parent;
    var transcludeCursor = templateCursor.replaceWithAnchor(anchorAttrs);
    dom.TemplateElement template = new dom.TemplateElement();
    transcludeCursor.elements.forEach((e) => template.append(e));
    transcludedNodeBinder.parentBinderOffset = 0;
    var elementBinders = [new NodeBinder.root(), transcludedNodeBinder];
    if (!transcludedNodeBinder.isTerminal && transcludeCursor.descend()) {
      _compileSiblings(transcludeCursor, selector, elementBinders, transcludedNodeBinder, 1);
      transcludeCursor.ascend();
    }

    return new TaggingViewFactory(template, _treeShakeBinders(elementBinders), _perf);
  }

  TaggingViewFactory call(List<dom.Node> elements, DirectiveMap directiveMap,
                          { bool compileInPlace: false }) {
    var timerId;
    assert(elements != null);
    bool inPlaceMode = compileInPlace && elements.length > 0;
    assert((timerId = _perf.startTimer('ng.compile', _html(elements))) != false);
    dom.Element rootElement;
    NodeBinder rootBinder = null;
    List<NodeBinder> elementBinders = <NodeBinder>[];
    NodeCursor cursor = new NodeCursor(elements);
    if (inPlaceMode) {
      if (elements.length != 1) throw "Only single root is allowed with compileInPlace mode.";
      rootElement = elements[0];
    } else {
      rootElement = new dom.TemplateElement();
      elements.forEach((e) => rootElement.append(e));
      rootBinder = new NodeBinder.root();
      elementBinders.add(rootBinder);
    }
    _compileSiblings(cursor, directiveMap.selector, elementBinders, rootBinder, compileInPlace ? -1 : 0);

    var viewFactory = new TaggingViewFactory(inPlaceMode ? elements[0] : rootElement,
        _treeShakeBinders(elementBinders, compileInPlace: compileInPlace),
        _perf, compileInPlace: compileInPlace);

    assert(_perf.stopTimer(timerId) != false);
    return viewFactory;
  }

  List<NodeBinder> _treeShakeBinders(List<NodeBinder> binders, {bool compileInPlace: false}) {
    assert(binders.isNotEmpty);
    final rootBinder = binders[0]; // This one is special;
    const NO_PARENT = -1;
    // In order to support text nodes with directiveless parents, we
    // add dummy NodeBinders to the list.  After the entire template
    // has been compiled, we remove the dummies and update the offset indices
    //
    // Index      (Parent index)
    // 0: -- Root  (-1)
    // 1:  +-- A   (0)
    // 2:    +-- B (1)
    //
    // Let's assume only B needs to stay (B is not empty)
    // parentIndexes = [-1, -1, 0]
    // output = [B]
    final output = <NodeBinder>[rootBinder];
    // todo(vicb) check: removed +1 to length ?
    final parentIndexes = new List<int>(binders.length);
    parentIndexes[0] = compileInPlace ? 0 : NO_PARENT;
    int dstIndex = 1;

    for (var srcIndex = 1; srcIndex <  binders.length; srcIndex++) {
      NodeBinder binder = binders[srcIndex];
      if (binder.isEmpty) {
        // The binder is empty and will be removed, set the parent to the parent's parent
        parentIndexes[srcIndex] = parentIndexes[binder.parentIndex];
      } else {
        binder.parentIndex = parentIndexes[binder.parentIndex];
        output.add(binder);
        parentIndexes[srcIndex] = dstIndex++;
      }
    }
    assert(output.isNotEmpty);
    assert(output[0] == rootBinder);
    return output;
  }
}
