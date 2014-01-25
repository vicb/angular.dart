part of angular.watch_group;

class PrototypeMap<K, V> extends Map<K,V> {
  PrototypeMap(Map prototype) : this.from(prototype);
}
