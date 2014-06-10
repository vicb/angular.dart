library angular.watch_group;

import 'package:angular/change_detection/change_detection.dart';
import 'dart:collection';

part 'linked_list.dart';
part 'ast.dart';
part 'prototype_map.dart';

/**
 * A function that is notified of changes to the model.
 *
 * ReactionFn is a function implemented by the developer that executes when a change is detected
 * in a watched expression.
 *
 * * [value]: The current value of the watched expression.
 * * [previousValue]: The previous value of the watched expression.
 *
 * If the expression is watching a collection (an iterable or a map), then [value] is wrapped in
 * a [CollectionChangeRecord] or a [MapChangeRecord] that lists all the changes.
 */
typedef void ReactionFn(value, previousValue);
typedef void ChangeLog(String expression, current, previous);

/**
 * Extend this class if you wish to pretend to be a function, but you don't know
 * number of arguments with which the function will get called with.
 */
abstract class FunctionApply {
  dynamic call() { throw new StateError('Use apply()'); }
  dynamic apply(List arguments);
}

/**
 * [WatchGroup] is a logical grouping of a set of watches. [WatchGroup]s are
 * organized into a hierarchical tree parent-children configuration.
 * [WatchGroup] builds upon [ChangeDetector] and adds expression (field chains
 * as in `a.b.c`) support as well as support function/closure/method (function
 * invocation as in `a.b()`) watching.
 */
class WatchGroup implements _EvalWatchList, _WatchGroupList {
  /** A unique ID for the WatchGroup */
  final String id;
  /**
   * A marker to be inserted when a group has no watches. We need the marker to
   * hold our position information in the linked list of all [Watch]es.
   */
  final _EvalWatchRecord _marker = new _EvalWatchRecord.marker();

  /** All Expressions are evaluated against a context object. */
  final Object context;

  /** [ChangeDetector] used for field watching */
  final ChangeDetectorGroup<_Handler> _changeDetector;
  /// A cache for sharing sub expression watching. Watching `a` and `a.b` will watch `a` only once.
  final Map<String, WatchRecord<_Handler>> _cache;
  final RootWatchGroup _rootGroup;

  /// STATS: Number of field watchers which are in use.
  int _fieldCost = 0;
  int _collectionCost = 0;
  int _evalCost = 0;

  /// STATS: Number of field watchers which are in use including child [WatchGroup]s.
  int get fieldCost => _fieldCost;
  int get totalFieldCost {
    var cost = _fieldCost;
    for (WatchGroup group = _childHead; group != null; group = group._next) {
      cost += group.totalFieldCost;
    }
    return cost;
  }

  /// STATS: Number of collection watchers which are in use including child [WatchGroup]s.
  int get collectionCost => _collectionCost;
  int get totalCollectionCost {
    var cost = _collectionCost;
    for (WatchGroup group = _childHead; group != null; group = group._next) {
      cost += group.totalCollectionCost;
    }
    return cost;
  }

  /// STATS: Number of invocation watchers (closures/methods) which are in use.
  int get evalCost => _evalCost;

  /// STATS: Number of invocation watchers which are in use including child [WatchGroup]s.
  int get totalEvalCost {
    var cost = _evalCost;
    for (WatchGroup group = _childHead; group != null; group = group._next) {
      cost += group.evalCost;
    }
    return cost;
  }

  int _nextChildId = 0;
  _EvalWatchRecord _recordHead, _recordTail;
  /// Pointer for creating tree of [WatchGroup]s.
  WatchGroup _parent;
  WatchGroup _childHead, _childTail;
  WatchGroup _prev, _next;

  WatchGroup._child(_parent, this._changeDetector, this.context, this._cache, this._rootGroup)
      : _parent = _parent,
        id = '${_parent.id}.${_parent._nextChildId++}'
  {
    _marker.watchGrp = this;
    _recordTail = _recordHead = _marker;
  }

  WatchGroup._root(this._changeDetector, this.context)
      : id = '',
        _rootGroup = null,
        _parent = null,
        _cache = new HashMap<String, WatchRecord<_Handler>>()
  {
    _marker.watchGrp = this;
    _recordTail = _recordHead = _marker;
  }

  /// Returns whether this groups is attached (reachable from the root group)
  bool get isAttached {
    for (var group = this; group != null; group = group._parent) {
      if (group == _rootGroup) return true;
    }
    return false;
  }

  Watch watch(AST ast, ReactionFn reactionFn) {
    WatchRecord<_Handler> watchRecord = _cache[ast.expression];
    if (watchRecord == null) {
      _cache[ast.expression] = watchRecord = ast.setupWatch(this);
    }
    return watchRecord.handler.addReactionFn(reactionFn);
  }

  /// Watch a [name] field on [lhs] represented by [expression].
  WatchRecord<_Handler> addFieldWatch(AST lhs, String name, String expression) {
    var fieldHandler = new _FieldHandler(this, expression);

    // Create a Record for the current field and assign the change record to the handler.
    var watchRecord = _changeDetector.watch(null, name, fieldHandler);
    _fieldCost++;
    fieldHandler.watchRecord = watchRecord;

    WatchRecord<_Handler> lhsWR = _cache[lhs.expression];
    if (lhsWR == null) {
      lhsWR = _cache[lhs.expression] = lhs.setupWatch(this);
    }

    // We set a field forwarding handler on LHS. This will allow the change
    // objects to propagate to the current WatchRecord.
    lhsWR.handler.addForwardHandler(fieldHandler);

    // propagate the value from the LHS to here
    fieldHandler.acceptValue(lhsWR.currentValue);
    return watchRecord;
  }

  WatchRecord<_Handler> addCollectionWatch(AST ast) {
    var collectionHandler = new _CollectionHandler(this, ast.expression);
    var watchRecord = _changeDetector.watch(null, null, collectionHandler);
    _collectionCost++;
    collectionHandler.watchRecord = watchRecord;
    WatchRecord<_Handler> astWR = _cache[ast.expression];
    if (astWR == null) {
      astWR = _cache[ast.expression] = ast.setupWatch(this);
    }

    // We set a field forwarding handler on LHS. This will allow the change
    // objects to propagate to the current WatchRecord.
    astWR.handler.addForwardHandler(collectionHandler);

    // propagate the value from the LHS to here
    collectionHandler.acceptValue(astWR.currentValue);
    return watchRecord;
  }

  /**
   * Watch a [fn] function represented by an [expression].
   *
   * - [fn] function to evaluate.
   * - [argsAST] list of [AST]es which represent arguments passed to function.
   * - [namedArgsAST] map of [AST]es which represent named arguments passed to method.
   * - [expression] normalized expression used for caching.
   * - [isPure] A pure function is one which holds no internal state. This implies that the
   *   function is idempotent.
   */
  _EvalWatchRecord addFunctionWatch(Function fn, List<AST> argsAST, Map<Symbol, AST> namedArgsAST,
                                    String expression, bool isPure) =>
      _addEvalWatch(null, fn, null, argsAST, namedArgsAST, expression, isPure);

  /**
   * Watch a method [name]ed represented by an [expression].
   *
   * - [lhs] left-hand-side of the method.
   * - [name] name of the method.
   * - [argsAST] list of [AST]es which represent arguments passed to method.
   * - [namedArgsAST] map of [AST]es which represent named arguments passed to method.
   * - [expression] normalized expression used for caching.
   */
  _EvalWatchRecord addMethodWatch(AST lhs, String name, List<AST> argsAST,
                                  Map<Symbol, AST> namedArgsAST, String expression) =>
     _addEvalWatch(lhs, null, name, argsAST, namedArgsAST, expression, false);



  _EvalWatchRecord _addEvalWatch(AST lhsAST, Function fn, String name, List<AST> argsAST,
                                 Map<Symbol, AST> namedArgsAST, String expression, bool isPure) {
    _InvokeHandler invokeHandler = new _InvokeHandler(this, expression);
    var evalWatchRecord = new _EvalWatchRecord(
        _rootGroup._fieldGetterFactory, this, invokeHandler, fn, name, argsAST.length, isPure);
    invokeHandler.watchRecord = evalWatchRecord;

    if (lhsAST != null) {
      var lhsWR = _cache[lhsAST.expression];
      if (lhsWR == null) {
        lhsWR = _cache[lhsAST.expression] = lhsAST.setupWatch(this);
      }
      lhsWR.handler.addForwardHandler(invokeHandler);
      invokeHandler.acceptValue(lhsWR.currentValue);
    }

    // Convert the args from AST to WatchRecords
    for (var i = 0; i < argsAST.length; i++) {
      var ast = argsAST[i];
      WatchRecord<_Handler> record = _cache[ast.expression];
      if (record == null) {
        record = _cache[ast.expression] = ast.setupWatch(this);
      }
      _ArgHandler handler = new _PositionalArgHandler(this, evalWatchRecord, i);
      _ArgHandlerList._add(invokeHandler, handler);
      record.handler.addForwardHandler(handler);
      handler.acceptValue(record.currentValue);
    }

    namedArgsAST.forEach((Symbol name, AST ast) {
      WatchRecord<_Handler> record = _cache[ast.expression];
      if (record == null) {
        record = _cache[ast.expression] = ast.setupWatch(this);
      }
      _ArgHandler handler = new _NamedArgHandler(this, evalWatchRecord, name);
      _ArgHandlerList._add(invokeHandler, handler);
      record.handler.addForwardHandler(handler);
      handler.acceptValue(record.currentValue);
    });

    // Must be done last
    _EvalWatchList._add(this, evalWatchRecord);
    _evalCost++;
    if (_rootGroup.isInsideInvokeDirty) {
      // This check means that we are inside invoke reaction function.
      // Registering a new EvalWatch at this point will not run the
      // .check() on it which means it will not be processed, but its
      // reaction function will be run with null. So we process it manually.
      evalWatchRecord.check();
    }
    return evalWatchRecord;
  }

    /// Similar to [_recordTail] but includes child-group records as well.
  _EvalWatchRecord get _recordTailInclChildren {
    var group = this;
    while (group._childTail != null) {
      group = group._childTail;
    }
    return group._recordTail;
  }

  /**
   * Create a new child [WatchGroup].
   *
   * - [context] if present the the child [WatchGroup] expressions will evaluate
   * against the new [context]. If not present than child expressions will
   * evaluate on same context allowing the reuse of the expression cache.
   */
  WatchGroup createChild([Object context]) {
    _EvalWatchRecord prev = _recordTailInclChildren;
    _EvalWatchRecord next = prev._next;
    var childGroup = new WatchGroup._child(
        this,
        _changeDetector.createChild(),
        context == null ? this.context : context,
        new HashMap<String, WatchRecord<_Handler>>(),
        _rootGroup == null ? this : _rootGroup);
    _WatchGroupList._addChild(this, childGroup);
    var marker = childGroup._marker;

    marker._prev = prev;
    marker._next = next;
    prev._next = marker;
    if (next != null) next._prev = marker;

    return childGroup;
  }

  /// Remove/destroy this [WatchGroup] and all of its [Watch]es.
  void remove() {
    // TODO:(misko) This code is not right.
    // 1) It fails to release [ChangeDetector] [WatchRecord]s.

    _WatchGroupList._removeChild(_parent, this);
    _parent = _next = _prev = null;
    _rootGroup._removeCount++;
    _changeDetector.remove();

    // Unlink the [_EvalWatchRecord]s
    _EvalWatchRecord previous = _recordHead._prev;
    _EvalWatchRecord next = _recordTailInclChildren._next;
    if (previous != null) previous._next = next;
    if (next != null) next._prev = previous;
    _recordHead._prev = null;
    _recordTail._next = null;
    _recordHead = _recordTail = null;
  }

  String toString() {
    var lines = [];
    if (this == _rootGroup) {
      var allWatches = [];
      var watch = _recordHead;
      var prev = null;
      while (watch != null) {
        allWatches.add(watch.toString());
        assert(watch._prev == prev);
        prev = watch;
        watch = watch._next;
      }
      lines.add('WATCHES: ${allWatches.join(', ')}');
    }

    var watches = [];
    var watch = _recordHead;
    while (watch != _recordTail) {
      watches.add(watch.toString());
      watch = watch._next;
    }
    watches.add(watch.toString());

    lines.add('WatchGroup[$id](watches: ${watches.join(', ')})');
    var childGroup = _childHead;
    while (childGroup != null) {
      lines.add('  ' + childGroup.toString().replaceAll('\n', '\n  '));
      childGroup = childGroup._next;
    }
    return lines.join('\n');
  }
}

/**
 * [RootWatchGroup]
 */
class RootWatchGroup extends WatchGroup {
  final FieldGetterFactory _fieldGetterFactory;
  Watch _dirtyWatchHead, _dirtyWatchTail;

  /**
   * Every time a [WatchGroup] is destroyed we increment the counter. During
   * [detectChanges] we reset the count. Before calling the reaction function,
   * we check [_removeCount] and if it is unchanged we can safely call the
   * reaction function. If it is changed we only call the reaction function
   * if the [WatchGroup] is still attached.
   */
  int _removeCount = 0;


  RootWatchGroup(this._fieldGetterFactory,
                 ChangeDetector changeDetector,
                 Object context)
      : super._root(changeDetector, context);

  RootWatchGroup get _rootGroup => this;

  /**
   * Detect changes and process the [ReactionFn]s.
   *
   * Algorithm:
   * 1) process the [ChangeDetector.collectChanges].
   * 2) process function/closure/method changes
   * 3) call an [ReactionFn]s
   *
   * Each step is called in sequence. ([ReactionFn]s are not called until all
   * previous steps are completed).
   */
  int detectChanges({ EvalExceptionHandler exceptionHandler,
                      ChangeLog changeLog,
                      AvgStopwatch fieldStopwatch,
                      AvgStopwatch evalStopwatch,
                      AvgStopwatch processStopwatch}) {
    // Process the Records from the change detector
    print('**** detectChanges(): dccd');
    Iterator<Record<_Handler>> changes =
        (_changeDetector as ChangeDetector<_Handler>).collectChanges(
            exceptionHandler: exceptionHandler,
            stopwatch: fieldStopwatch);
    if (processStopwatch != null) processStopwatch.start();
    while (changes.moveNext()) {
      var record = changes.current;
      if (changeLog != null) {
        changeLog(record.handler.expression, record.currentValue, record.previousValue);
      }
      record.handler.onChange(record);
    }
    if (processStopwatch != null) processStopwatch.stop();

    // Process our own function evaluations
    if (evalStopwatch != null) evalStopwatch.start();

    print('**** detectChanges(): watch group');
    int evalCount = 0;
    for (_EvalWatchRecord record = _recordHead; record != null; record = record._next) {
      try {
        evalCount++;
        if (record.check() && changeLog != null) {
          changeLog(record.handler.expression, record.currentValue, record.previousValue);
        }
      } catch (e, s) {
        if (exceptionHandler == null) {
          rethrow;
        } else {
          exceptionHandler(e, s);
        }
      }

    }
    if (evalStopwatch != null) evalStopwatch..stop()..increment(evalCount);


    print('**** detectChanges(): dirty watches');
    // Because the handlers can forward changes between each other synchronously
    // We need to call reaction functions asynchronously. This processes the
    // asynchronous reaction function queue.
    int count = 0;
    if (processStopwatch != null) processStopwatch.start();
    Watch dirtyWatch = _dirtyWatchHead;
    _dirtyWatchHead = null;
    try {
      while (dirtyWatch != null) {
        count++;
        try {
          if (_removeCount == 0 || dirtyWatch._watchGroup.isAttached) {
            dirtyWatch.invoke();
          }
        } catch (e, s) {
          if (exceptionHandler == null) rethrow; else exceptionHandler(e, s);
        }
        var nextDirtyWatch = dirtyWatch._nextDirtyWatch;
        dirtyWatch._nextDirtyWatch = null;
        dirtyWatch = nextDirtyWatch;
      }
    } finally {
      _dirtyWatchTail = null;
      _removeCount = 0;
    }
    if (processStopwatch != null) processStopwatch..stop()..increment(count);
    return count;
  }

  bool get isInsideInvokeDirty => _dirtyWatchHead == null && _dirtyWatchTail != null;

  /// Add a [watch] into the asynchronous queue for later processing.
  Watch _addDirtyWatch(Watch watch) {
    print('RootWatchGroup addDirtyWatch, dirty: ${watch._dirty}');
    if (!watch._dirty) {
      watch._dirty = true;
      if (_dirtyWatchTail == null) {
        _dirtyWatchHead = _dirtyWatchTail = watch;
      } else {
        _dirtyWatchTail._nextDirtyWatch = watch;
        _dirtyWatchTail = watch;
      }
      watch._nextDirtyWatch = null;
    }
    return watch;
  }
}

/// [Watch] corresponds to an individual [watch] registration on the watchGrp.
class Watch {
  Watch _previous, _next;

  final Record<_Handler> _record;
  final ReactionFn reactionFn;
  final WatchGroup _watchGroup;

  bool _dirty = false;
  bool _deleted = false;
  Watch _nextDirtyWatch;

  Watch(this._watchGroup, this._record, this.reactionFn);

  String get expression => _record.handler.expression;

  void invoke() {
    if (_deleted || !_dirty) return;
    _dirty = false;
    reactionFn(_record.currentValue, _record.previousValue);
  }

  void remove() {
    if (_deleted) throw new StateError('Already deleted!');
    _deleted = true;
    var handler = _record.handler;
    _WatchList._remove(handler, this);
    handler.release();
  }
}

/**
 * This class processes changes from the change detector. The changes are
 * forwarded onto the next [_Handler] or queued up in case of reaction function.
 *
 * Given these two expression: 'a.b.c' => rfn1 and 'a.b' => rfn2
 * The resulting data structure is:
 *
 * _Handler             +--> _Handler             +--> _Handler
 *   - delegateHandler -+      - delegateHandler -+      - delegateHandler = null
 *   - expression: 'a'         - expression: 'a.b'       - expression: 'a.b.c'
 *   - watchObject: context    - watchObject: context.a  - watchObject: context.a.b
 *   - watchRecord: 'a'        - watchRecord 'b'         - watchRecord 'c'
 *   - reactionFn: null        - reactionFn: rfn1        - reactionFn: rfn2
 *
 * Notice how the [_Handler]s coalesce their watching. Also notice that any
 * changes detected at one handler are propagated to the next handler.
 */
abstract class _Handler implements _LinkedList, _LinkedListItem, _WatchList {
  // Used for forwarding changes to delegates
  _Handler _head, _tail;
  _Handler _next, _prev;
  Watch _watchHead, _watchTail;

  final String expression;
  final WatchGroup watchGrp;

  WatchRecord<_Handler> watchRecord;
  /// The [_Handler] that forward its change to us, if any
  _Handler forwardingHandler;

  _Handler(this.watchGrp, this.expression) {
    assert(watchGrp != null);
    assert(expression != null);
  }

  Watch addReactionFn(ReactionFn reactionFn) {
    assert(_next != this); // verify we are not detached
    Watch watch = _WatchList._add(this, new Watch(watchGrp, watchRecord, reactionFn));
    return watchGrp._rootGroup._addDirtyWatch(watch);
  }

  /// Forward changes to the [forwardToHandler]
  void addForwardHandler(_Handler forwardToHandler) {
    assert(forwardToHandler.forwardingHandler == null);
    _LinkedList._add(this, forwardToHandler);
    forwardToHandler.forwardingHandler = this;
  }

  /// Return true if release has happened
  bool release() {
    // If there is no more handler not delegate handlers we can unlink this handler
    if (_WatchList._isEmpty(this) && _LinkedList._isEmpty(this)) {
      _releaseWatch();
      // Remove ourselves from cache, or else new registrations will go to us, but we are dead
      watchGrp._cache.remove(expression);

      if (forwardingHandler != null) {
        /// Unsubscribe from the forwarding handler
        _LinkedList._remove(forwardingHandler, this);
        /// May be release the forwarding handler (if it has no more handlers & delegate handlers)
        forwardingHandler.release();
      }

      // We can remove ourselves
      assert((_next = _prev = this) == this); // mark ourselves as detached
      return true;
    } else {
      return false;
    }
  }

  void _releaseWatch() {
    watchRecord.remove();
    watchGrp._fieldCost--;
  }

  void acceptValue(object) {}

  void onChange(Record<_Handler> record) {
    print('Handler of "$expression", onChange()');
    assert(_next != this); // verify we are not detached

    // If we have reaction functions than queue them up for asynchronous processing.
    for (Watch watch = _watchHead; watch != null; watch = watch._next) {
      print('# Handler: add dirty watch ${watch.expression}');
      watchGrp._rootGroup._addDirtyWatch(watch);
    }

    // If we have a delegateHandler then forward the new value to it.
    for (_Handler dlgHandler = _head; dlgHandler != null; dlgHandler = dlgHandler._next) {
      print('# Handler: forward onChange from $expression to ${dlgHandler.expression} = ${record.currentValue}');
      dlgHandler.acceptValue(record.currentValue);
    }
  }
}

class _ConstantHandler extends _Handler {
  _ConstantHandler(WatchGroup watchGroup, String expression, constantValue)
      : super(watchGroup, expression)
  {
    watchRecord = new _EvalWatchRecord.constant(this, constantValue);
  }

  bool release() => null;
}

class _FieldHandler extends _Handler {
  _FieldHandler(watchGrp, expression): super(watchGrp, expression);

  /// This function forwards the watched object to the next [_Handler]
  void acceptValue(object) {
    watchRecord.object = object;
    if (watchRecord.check()) onChange(watchRecord);
  }
}

class _CollectionHandler extends _Handler {
  _CollectionHandler(WatchGroup watchGrp, String expression): super(watchGrp, expression);

  /// This function forwards the watched object to the next [_Handler] synchronously.
  void acceptValue(object) {
    watchRecord.object = object;
    if (watchRecord.check()) onChange(watchRecord);
  }

  void _releaseWatch() {
    watchRecord.remove();
    watchGrp._collectionCost--;
  }
}

abstract class _ArgHandler extends _Handler {
  _ArgHandler _previousArgHandler, _nextArgHandler;

  @override // The parent is a WatchRecord<_Handler>
  final _EvalWatchRecord watchRecord;
  _ArgHandler(WatchGroup watchGrp, String expression, this.watchRecord)
      : super(watchGrp, expression);

  void _releaseWatch() {}
}

class _PositionalArgHandler extends _ArgHandler {
  static final List<String> _ARGS = new List.generate(20, (index) => 'arg[$index]');
  final int index;

  _PositionalArgHandler(WatchGroup watchGrp, _EvalWatchRecord record, int index)
      : this.index = index,
        super(watchGrp, _ARGS[index], record);

  void acceptValue(object) {
    watchRecord.dirtyArgs = true;
    watchRecord.args[index] = object;
  }
}

class _NamedArgHandler extends _ArgHandler {
  static final Map<Symbol, String> _NAMED_ARG = new HashMap<Symbol, String>();
  static String _GET_NAMED_ARG(Symbol symbol) {
    String name = _NAMED_ARG[symbol];
    if (name == null) name = _NAMED_ARG[symbol] = 'namedArg[$name]';
    return name;
  }
  final Symbol name;

  _NamedArgHandler(WatchGroup watchGrp, _EvalWatchRecord record, Symbol name)
      : name = name,
        super(watchGrp, _GET_NAMED_ARG(name), record);


  void acceptValue(object) {
    if (watchRecord.namedArgs == null) {
      watchRecord.namedArgs = new HashMap<Symbol, dynamic>();
    }
    watchRecord.dirtyArgs = true;
    watchRecord.namedArgs[name] = object;
  }
}

class _InvokeHandler extends _Handler implements _ArgHandlerList {
  _ArgHandler _argHandlerHead, _argHandlerTail;

  _InvokeHandler(WatchGroup watchGrp, String expression)
      : super(watchGrp, expression);

  void acceptValue(object) {
    watchRecord.object = object;
  }

  void _releaseWatch() {
    watchRecord.remove();
  }

  bool release() {
    if (super.release()) {
      _ArgHandler current = _argHandlerHead;
      while (current != null) {
        current.release();
        current = current._nextArgHandler;
      }
      return true;
    } else {
      return false;
    }
  }
}

class _EvalWatchRecord implements WatchRecord<_Handler> {
  static const int _MODE_INVALID_                  = -2;
  static const int _MODE_DELETED_                  = -1;
  static const int _MODE_MARKER_                   = 0;
  static const int _MODE_PURE_FUNCTION_            = 1;
  static const int _MODE_FUNCTION_                 = 2;
  static const int _MODE_PURE_FUNCTION_APPLY_      = 3;
  static const int _MODE_NULL_                     = 4;
  static const int _MODE_FIELD_OR_METHOD_CLOSURE_  = 5;
  static const int _MODE_METHOD_                   = 6;
  static const int _MODE_FIELD_CLOSURE_            = 7;
  static const int _MODE_MAP_CLOSURE_              = 8;
  WatchGroup watchGrp;
  final _Handler handler;
  final List args;
  Map<Symbol, dynamic> namedArgs = null;
  final String name;
  int mode;
  Function fn;
  FieldGetterFactory _fieldGetterFactory;
  bool dirtyArgs = true;

  dynamic currentValue, previousValue, _object;

  _EvalWatchRecord _prev, _next;

  _EvalWatchRecord(this._fieldGetterFactory, this.watchGrp, this.handler,
                   this.fn, this.name, int arity, bool pure)
      : args = new List(arity)
  {
    if (fn is FunctionApply) {
      mode = pure ? _MODE_PURE_FUNCTION_APPLY_: _MODE_INVALID_;
    } else if (fn is Function) {
      mode = pure ? _MODE_PURE_FUNCTION_ : _MODE_FUNCTION_;
    } else {
      mode = _MODE_NULL_;
    }
  }

  _EvalWatchRecord.marker()
      : mode = _MODE_MARKER_,
        _fieldGetterFactory = null,
        watchGrp = null,
        handler = null,
        args = null,
        fn = null,
        name = null;

  _EvalWatchRecord.constant(_Handler handler, constantValue)
      : mode = _MODE_MARKER_,
        _fieldGetterFactory = null,
        handler = handler,
        currentValue = constantValue,
        watchGrp = null,
        args = null,
        fn = null,
        name = null;

  Object get object => _object;

  void set object(value) {
    assert(mode != _MODE_DELETED_);
    assert(mode != _MODE_MARKER_);
    assert(mode != _MODE_FUNCTION_);
    assert(mode != _MODE_PURE_FUNCTION_);
    assert(mode != _MODE_PURE_FUNCTION_APPLY_);
    _object = value;

    if (value == null) {
      mode = _MODE_NULL_;
    } else {
      if (value is Map) {
        mode =  _MODE_MAP_CLOSURE_;
      } else {
        mode = _MODE_FIELD_OR_METHOD_CLOSURE_;
        fn = _fieldGetterFactory.getter(value, name);
      }
    }
  }

  bool check() {
    var value;
    switch (mode) {
      case _MODE_MARKER_:
      case _MODE_NULL_:
        return false;
      case _MODE_PURE_FUNCTION_:
        if (!dirtyArgs) return false;
        value = Function.apply(fn, args, namedArgs);
        dirtyArgs = false;
        break;
      case _MODE_FUNCTION_:
        value = Function.apply(fn, args, namedArgs);
        dirtyArgs = false;
        break;
      case _MODE_PURE_FUNCTION_APPLY_:
        if (!dirtyArgs) return false;
        value = (fn as FunctionApply).apply(args);
        dirtyArgs = false;
        break;
      case _MODE_FIELD_OR_METHOD_CLOSURE_:
        var closure = fn(_object);
        // NOTE: When Dart looks up a method "foo" on object "x", it returns a
        // new closure for each lookup.  They compare equal via "==" but are no
        // identical().  There's no point getting a new value each time and
        // decide it's the same so we'll skip further checking after the first
        // time.
        if (closure is Function && !identical(closure, fn(_object))) {
          fn = closure;
          mode = _MODE_METHOD_;
        } else {
          mode = _MODE_FIELD_CLOSURE_;
        }
        value = (closure == null) ? null : Function.apply(closure, args, namedArgs);
        break;
      case _MODE_METHOD_:
        value = Function.apply(fn, args, namedArgs);
        break;
      case _MODE_FIELD_CLOSURE_:
        var closure = fn(_object);
        value = (closure == null) ? null : Function.apply(closure, args, namedArgs);
        break;
      case _MODE_MAP_CLOSURE_:
        var closure = object[name];
        value = (closure == null) ? null : Function.apply(closure, args, namedArgs);
        break;
      default:
        assert(false);
    }

    var current = currentValue;
    if (!identical(current, value)) {
      if (value is String && current is String && value == current) {
        // it is really the same, recover and save so next time identity is same
        current = value;
      } else if (value is num && value.isNaN && current is num && current.isNaN) {
        // we need this for the compiled JavaScript since in JS NaN !== NaN.
      } else {
        previousValue = current;
        currentValue = value;
        handler.onChange(this);
        return true;
      }
    }
    return false;
  }

  void remove() {
    assert(mode != _MODE_DELETED_);
    assert((mode = _MODE_DELETED_) == _MODE_DELETED_); // Mark as deleted.
    watchGrp._evalCost--;
    _EvalWatchList._remove(watchGrp, this);
  }

  String toString() {
    if (mode == _MODE_MARKER_) return 'MARKER[$currentValue]';
    return '${watchGrp.id}:${handler.expression}';
  }
}
