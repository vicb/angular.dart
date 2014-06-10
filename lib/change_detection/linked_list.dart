part of angular.watch_group;


class _LinkedListItem<I extends _LinkedListItem> {
  I _prev, _next;
}

class _LinkedList<L extends _LinkedListItem> {
  L _head, _tail;

  static _Handler _add(_Handler list, _LinkedListItem item) {
    assert(item._next     == null);
    assert(item._prev == null);
    if (list._tail == null) {
      list._head = list._tail = item;
    } else {
      item._prev = list._tail;
      list._tail._next = item;
      list._tail = item;
    }
    return item;
  }

  static bool _isEmpty(_Handler list) => list._head == null;

  static void _remove(_Handler list, _Handler item) {
    var prev = item._prev;
    var next = item._next;

    if (prev == null) list._head = next;     else prev._next = next;
    if (next == null)     list._tail = prev; else next._prev = prev;
  }
}

class _ArgHandlerList {
  _ArgHandler _argHandlerHead, _argHandlerTail;

  static _Handler _add(_ArgHandlerList list, _ArgHandler item) {
    assert(item._nextArgHandler     == null);
    assert(item._previousArgHandler == null);
    if (list._argHandlerTail == null) {
      list._argHandlerHead = list._argHandlerTail = item;
    } else {
      item._previousArgHandler = list._argHandlerTail;
      list._argHandlerTail._nextArgHandler = item;
      list._argHandlerTail = item;
    }
    return item;
  }

  static bool _isEmpty(_InvokeHandler list) => list._argHandlerHead == null;

  static void _remove(_InvokeHandler list, _ArgHandler item) {
    var previous = item._previousArgHandler;
    var next = item._nextArgHandler;

    if (previous == null) list._argHandlerHead = next;     else previous._nextArgHandler = next;
    if (next == null)     list._argHandlerTail = previous; else next._previousArgHandler = previous;
  }
}

class _WatchList {
  Watch _watchHead, _watchTail;

  static Watch _add(_WatchList list, Watch item) {
    assert(item._next     == null);
    assert(item._previous == null);
    if (list._watchTail == null) {
      list._watchHead = list._watchTail = item;
    } else {
      item._previous = list._watchTail;
      list._watchTail._next = item;
      list._watchTail = item;
    }
    return item;
  }

  static bool _isEmpty(_Handler list) => list._watchHead == null;

  static void _remove(_Handler list, Watch item) {
    var previous = item._previous;
    var next = item._next;

    if (previous == null) list._watchHead = next;     else previous._next = next;
    if (next == null)     list._watchTail = previous; else next._previous = previous;
  }
}

abstract class _EvalWatchList {
  _EvalWatchRecord _recordHead, _recordTail;
  _EvalWatchRecord get _marker;

  static _EvalWatchRecord _add(_EvalWatchList list, _EvalWatchRecord item) {
    assert(item._next == null);
    assert(item._prev == null);
    var prev = list._recordTail;
    var next = prev._next;

    if (prev == list._marker) {
      list._recordHead = list._recordTail = item;
      prev = prev._prev;
      list._marker._prev = null;
      list._marker._next = null;
    }
    item._next = next;
    item._prev = prev;

    if (prev != null) prev._next = item;
    if (next != null) next._prev = item;

    return list._recordTail = item;
  }

  static bool _isEmpty(_EvalWatchList list) => list._recordHead == null;

  static void _remove(_EvalWatchList list, _EvalWatchRecord item) {
    assert(item.watchGrp == list);
    var prev = item._prev;
    var next = item._next;

    if (list._recordHead == list._recordTail) {
      list._recordHead = list._recordTail = list._marker;
      list._marker.._next = next
                  .._prev = prev;
      if (prev != null) prev._next = list._marker;
      if (next != null) next._prev = list._marker;
    } else {
      if (item == list._recordHead) list._recordHead = next;
      if (item == list._recordTail) list._recordTail = prev;
      if (prev != null) prev._next = next;
      if (next != null) next._prev = prev;
    }
  }
}

class _WatchGroupList {
  WatchGroup _childHead, _childTail;

  static WatchGroup _addChild(_WatchGroupList list, WatchGroup item) {
    assert(item._next     == null);
    assert(item._prev == null);
    if (list._childTail == null) {
      list._childHead = list._childTail = item;
    } else {
      item._prev = list._childTail;
      list._childTail._next = item;
      list._childTail = item;
    }
    return item;
  }

  static bool _HasChildren(_WatchGroupList list) => list._childHead == null;

  static void _removeChild(_WatchGroupList list, WatchGroup item) {
    var previous = item._prev;
    var next = item._next;

    if (previous == null) list._childHead = next;     else previous._next = next;
    if (next == null)     list._childTail = previous; else next._prev = previous;
  }
}
